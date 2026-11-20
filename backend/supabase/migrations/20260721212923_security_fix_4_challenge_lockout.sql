-- =============================================================================
-- SECURITY FIX 4: Add lockout to verify_challenge_code RPC
-- =============================================================================
-- Vulnerability: verify_challenge_code recorded failures but never checked the
-- attempt count before verifying. This allowed unlimited brute-force attempts
-- through this RPC. Lockout was only enforced client-side (easily bypassed).
-- =============================================================================

CREATE OR REPLACE FUNCTION badra_core.verify_challenge_code(
  p_code TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_stored TEXT;
  v_attempt_count INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  -- SECURITY: Check lockout BEFORE verifying (max 5 attempts in 30 min)
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = 'challenge_code'
    AND attempted_at > now() - interval '30 minutes';

  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم قفل كود التحدي مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  -- Fetch stored challenge code
  SELECT challenge_code INTO v_stored
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  IF v_stored IS NULL OR v_stored = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين كود التحدي');
  END IF;

  -- Verify code
  IF v_stored = crypt(p_code, v_stored) THEN
    -- Success: clear lockout
    DELETE FROM badra_core.challenge_attempts
    WHERE user_id = v_user_id AND attempt_type = 'challenge_code';
    RETURN jsonb_build_object('success', true);
  END IF;

  -- Failed attempt: record it
  INSERT INTO badra_core.challenge_attempts (user_id, attempt_type)
  VALUES (v_user_id, 'challenge_code');

  RETURN jsonb_build_object('success', false, 'error', 'كود التحدي غير صحيح');
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.verify_challenge_code(TEXT) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.verify_challenge_code(TEXT) TO authenticated;

COMMENT ON FUNCTION badra_core.verify_challenge_code IS
  'SECURITY: Includes server-side lockout (max 5 attempts per 30 minutes).';
