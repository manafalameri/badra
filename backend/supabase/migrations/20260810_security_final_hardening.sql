-- =============================================================================
-- SECURITY FINAL HARDENING
-- =============================================================================
-- 1. verify_security_code: mandatory server-side lockout (max 5 attempts / 30 min).
--    Previously the Edge Function checked nothing before verifying the PIN,
--    so the 6-digit PIN was brute-forceable through the approval endpoint.
-- 2. Revoke the legacy client-side approval RPC (dead path, larger attack surface).
-- 3. Revoke client-writable lockout counters (record_failed_attempt / clear_attempts)
--    so a user can no longer reset their own lockout.
-- 4. security_events table + report_security_event RPC for real threat telemetry.
-- =============================================================================

-- ── 1. verify_security_code with mandatory lockout ──
CREATE OR REPLACE FUNCTION badra_core.verify_security_code(
  p_user_id UUID,
  p_security_code TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_stored_hash TEXT;
  v_attempt_count INT;
BEGIN
  -- SECURITY: check lockout BEFORE verifying (unbypassable: enforced server-side).
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = p_user_id AND attempt_type = 'security_code'
    AND attempted_at > now() - interval '30 minutes';

  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object(
      'valid', false,
      'locked', true,
      'error', 'تم قفل الرقم السري مؤقتاً. حاول بعد 30 دقيقة.'
    );
  END IF;

  SELECT security_code INTO v_stored_hash
  FROM badra_core.profiles
  WHERE user_id = p_user_id;

  IF v_stored_hash IS NULL OR v_stored_hash = '' THEN
    RETURN jsonb_build_object('valid', false, 'error', 'لم يتم تعيين الرقم السري');
  END IF;

  IF v_stored_hash = crypt(p_security_code, v_stored_hash) THEN
    DELETE FROM badra_core.challenge_attempts
    WHERE user_id = p_user_id AND attempt_type = 'security_code';
    RETURN jsonb_build_object('valid', true);
  END IF;

  INSERT INTO badra_core.challenge_attempts (user_id, attempt_type)
  VALUES (p_user_id, 'security_code');

  RETURN jsonb_build_object('valid', false, 'error', 'الرقم السري غير صحيح');
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.verify_security_code FROM anon, public, authenticated;

COMMENT ON FUNCTION badra_core.verify_security_code IS
  'SECURITY: server-side lockout (max 5 attempts / 30 min) enforced inside verification.';

-- ── 2. Revoke the legacy approval RPC (dead code in the app, never used) ──
REVOKE EXECUTE ON FUNCTION badra_core.approve_payment_request_v2
  FROM anon, public, authenticated;

-- ── 3. Lockout counters are server-managed only ──
REVOKE EXECUTE ON FUNCTION badra_core.record_failed_attempt
  FROM anon, public, authenticated;
REVOKE EXECUTE ON FUNCTION badra_core.clear_attempts
  FROM anon, public, authenticated;

-- ── 4. security_events telemetry ──
CREATE TABLE IF NOT EXISTS badra_core.security_events (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'app',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_security_events_user
  ON badra_core.security_events(user_id, created_at DESC);

ALTER TABLE badra_core.security_events ENABLE ROW LEVEL SECURITY;

-- Users may only insert their own events; nobody (except service role) may read them.
CREATE POLICY "security_events_insert_own"
  ON badra_core.security_events
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION badra_core.report_security_event(
  p_event_type TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_event_type IS NULL
     OR p_event_type = ''
     OR length(p_event_type) > 64 THEN
    RETURN jsonb_build_object('success', false, 'error', 'نوع الحدث غير صالح');
  END IF;

  INSERT INTO badra_core.security_events (user_id, event_type, source)
  VALUES (v_user_id, p_event_type, 'app');

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.report_security_event FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.report_security_event TO authenticated;

COMMENT ON FUNCTION badra_core.report_security_event IS
  'SECURITY: client reports a detected threat (freeRASP) — insert-only telemetry.';