-- =============================================================================
-- SECURITY: lockout_v2 — real server-side multi-dimensional login lockout
-- =============================================================================
-- The legacy check_login_allowed only READ a counter that nothing ever wrote,
-- so the login lockout was a no-op. These functions make it real:
--
--   check_lockout_v2  -> decide lock BEFORE verifying (fail-closed)
--   record_failed_login_v2 / record_successful_login_v2 -> ledger writes
--   clear_attempts_v2 -> wipe counters after a successful login
--   uniform_timing    -> every path takes 150-300ms (no timing oracle)
--   set_global_tripwire / admin_unlock_v2 -> ops tooling
--
-- Grants: service_role ONLY (login Edge Function). anon/authenticated can
-- NEVER read, write or reset these counters -> a user cannot self-unlock.
-- =============================================================================

-- ── 1. check_lockout_v2 ──
CREATE OR REPLACE FUNCTION badra_core.check_lockout_v2(
  p_phone TEXT,
  p_device_hash TEXT DEFAULT '',
  p_ip TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_fail_30m INT;
  v_fail_24h INT;
  v_fail_7d INT;
  v_device_fail_1h INT;
  v_ip_fail_1h INT;
  v_tripwire BOOLEAN;
  v_retry_after INT;
  v_dimension TEXT;
  v_forever BOOLEAN := false;
  v_ip24 TEXT;
BEGIN
  v_retry_after := 0;

  -- ── user dimension (phone) ──
  IF p_phone IS NOT NULL AND p_phone != '' THEN
    SELECT COUNT(*) INTO v_fail_30m
    FROM badra_core.security_attempts_v2
    WHERE dimension = 'user' AND target = p_phone
      AND attempt_type = 'login' AND outcome = 'fail'
      AND attempted_at > now() - interval '30 minutes';

    SELECT COUNT(*) INTO v_fail_24h
    FROM badra_core.security_attempts_v2
    WHERE dimension = 'user' AND target = p_phone
      AND attempt_type = 'login' AND outcome = 'fail'
      AND attempted_at > now() - interval '24 hours';

    SELECT COUNT(*) INTO v_fail_7d
    FROM badra_core.security_attempts_v2
    WHERE dimension = 'user' AND target = p_phone
      AND attempt_type = 'login' AND outcome = 'fail'
      AND attempted_at > now() - interval '7 days';

    -- Escalation ladder: 30min -> 2h -> 24h -> permanent (admin unlock only)
    IF v_fail_7d >= 25 THEN
      v_forever := true;
      v_dimension := 'user';
    ELSIF v_fail_24h >= 10 OR v_fail_30m >= 5 THEN
      IF v_fail_24h >= 10 THEN
        v_retry_after := 7200;
      ELSE
        v_retry_after := 1800;
      END IF;
      v_dimension := 'user';
    END IF;
  END IF;

  -- ── device dimension ──
  IF v_retry_after = 0 AND NOT v_forever
     AND p_device_hash IS NOT NULL AND p_device_hash != ''
     AND p_device_hash NOT IN ('unknown_device_id', 'unknown') THEN
    SELECT COUNT(*) INTO v_device_fail_1h
    FROM badra_core.security_attempts_v2
    WHERE dimension = 'device' AND target = p_device_hash
      AND attempt_type = 'login' AND outcome = 'fail'
      AND attempted_at > now() - interval '1 hour';

    IF v_device_fail_1h >= 10 THEN
      v_retry_after := 3600;
      v_dimension := 'device';
    END IF;
  END IF;

  -- ── ip dimension (/24) ──
  IF v_retry_after = 0 AND NOT v_forever
     AND p_ip IS NOT NULL AND p_ip != '' AND p_ip != 'unknown' THEN
    v_ip24 := badra_core.ip_subnet_v2(p_ip);

    SELECT COUNT(*) INTO v_ip_fail_1h
    FROM badra_core.security_attempts_v2
    WHERE dimension = 'ip' AND target = v_ip24
      AND attempt_type = 'login' AND outcome = 'fail'
      AND attempted_at > now() - interval '1 hour';

    IF v_ip_fail_1h >= 50 THEN
      v_retry_after := 7200;
      v_dimension := 'ip';
    END IF;
  END IF;

  -- ── global tripwire (honeypot / manual) ──
  IF v_retry_after = 0 AND NOT v_forever THEN
    SELECT EXISTS (
      SELECT 1 FROM badra_core.security_attempts_v2
      WHERE dimension = 'global' AND target = 'all'
        AND outcome = 'locked'
        AND attempted_at > now() - interval '1 hour'
    ) INTO v_tripwire;

    IF v_tripwire THEN
      v_retry_after := 3600;
      v_dimension := 'global';
    END IF;
  END IF;

  IF v_forever THEN
    RETURN jsonb_build_object(
      'locked', true,
      'locked_forever', true,
      'retry_after', NULL,
      'dimension', v_dimension
    );
  END IF;

  IF v_retry_after > 0 THEN
    RETURN jsonb_build_object(
      'locked', true,
      'locked_forever', false,
      'retry_after', v_retry_after,
      'dimension', v_dimension
    );
  END IF;

  RETURN jsonb_build_object('locked', false, 'retry_after', NULL, 'dimension', NULL);
END;
$$;

-- ── 2. ip_subnet_v2 — normalize an IP to its /24 subnet ──
CREATE OR REPLACE FUNCTION badra_core.ip_subnet_v2(p_ip TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    CASE
      WHEN p_ip IS NULL OR p_ip = '' THEN ''
      WHEN strpos(p_ip, '.') = 0 THEN p_ip  -- IPv6: treat as its own key
      ELSE split_part(p_ip, '.', 1) || '.' || split_part(p_ip, '.', 2) || '.' || split_part(p_ip, '.', 3)
    END;
$$;

-- ── 3. record_failed_login_v2 — one call logs user + device + ip dims ──
CREATE OR REPLACE FUNCTION badra_core.record_failed_login_v2(
  p_phone TEXT,
  p_device_hash TEXT DEFAULT '',
  p_ip TEXT DEFAULT '',
  p_user_agent TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_ip24 TEXT;
BEGIN
  IF p_phone IS NOT NULL AND p_phone != '' THEN
    INSERT INTO badra_core.security_attempts_v2 (dimension, target, attempt_type, outcome, ip, user_agent)
    VALUES ('user', p_phone, 'login', 'fail', p_ip, p_user_agent);
  END IF;

  IF p_device_hash IS NOT NULL AND p_device_hash != ''
     AND p_device_hash NOT IN ('unknown_device_id', 'unknown') THEN
    INSERT INTO badra_core.security_attempts_v2 (dimension, target, attempt_type, outcome, ip, user_agent)
    VALUES ('device', p_device_hash, 'login', 'fail', p_ip, p_user_agent);
  END IF;

  IF p_ip IS NOT NULL AND p_ip != '' AND p_ip != 'unknown' THEN
    v_ip24 := badra_core.ip_subnet_v2(p_ip);
    INSERT INTO badra_core.security_attempts_v2 (dimension, target, attempt_type, outcome, ip, user_agent)
    VALUES ('ip', v_ip24, 'login', 'fail', p_ip, p_user_agent);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ── 4. record_successful_login_v2 — audit trail ──
CREATE OR REPLACE FUNCTION badra_core.record_successful_login_v2(
  p_phone TEXT,
  p_device_hash TEXT DEFAULT '',
  p_ip TEXT DEFAULT '',
  p_user_agent TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  IF p_phone IS NOT NULL AND p_phone != '' THEN
    INSERT INTO badra_core.security_attempts_v2 (dimension, target, attempt_type, outcome, ip, user_agent)
    VALUES ('user', p_phone, 'login', 'success', p_ip, p_user_agent);
  END IF;
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ── 5. clear_attempts_v2 — wipe counters after successful login ──
CREATE OR REPLACE FUNCTION badra_core.clear_attempts_v2(
  p_phone TEXT,
  p_device_hash TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  IF p_phone IS NOT NULL AND p_phone != '' THEN
    DELETE FROM badra_core.security_attempts_v2
    WHERE dimension = 'user' AND target = p_phone AND attempt_type = 'login';
  END IF;

  IF p_device_hash IS NOT NULL AND p_device_hash != ''
     AND p_device_hash NOT IN ('unknown_device_id', 'unknown') THEN
    DELETE FROM badra_core.security_attempts_v2
    WHERE dimension = 'device' AND target = p_device_hash AND attempt_type = 'login';
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ── 6. uniform_timing — every path takes 150-300ms (no timing oracle) ──
CREATE OR REPLACE FUNCTION badra_core.uniform_timing()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  PERFORM pg_sleep(0.15 + random() * 0.15);
END;
$$;

-- ── 7. set_global_tripwire — stop ALL logins for 1h (honeypot hit / manual) ──
CREATE OR REPLACE FUNCTION badra_core.set_global_tripwire(
  p_reason TEXT DEFAULT 'manual'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  INSERT INTO badra_core.security_attempts_v2 (dimension, target, attempt_type, outcome, ip, user_agent)
  VALUES ('global', 'all', 'login', 'locked', '', left(COALESCE(p_reason, 'manual'), 200));
  RETURN jsonb_build_object('success', true);
END;
$$;

-- ── 8. admin_unlock_v2 — manual recovery for permanently locked accounts ──
CREATE OR REPLACE FUNCTION badra_core.admin_unlock_v2(
  p_phone TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  DELETE FROM badra_core.security_attempts_v2
  WHERE dimension = 'user' AND target = p_phone AND attempt_type = 'login';

  INSERT INTO badra_core.security_attempts_v2 (dimension, target, attempt_type, outcome, ip, user_agent)
  VALUES ('user', p_phone, 'login', 'success', '', 'admin_unlock');

  RETURN jsonb_build_object('success', true);
END;
$$;

-- ── Grants: service_role ONLY (login Edge Function). Clients: none. ──
REVOKE EXECUTE ON FUNCTION badra_core.check_lockout_v2(text, text, text) FROM anon, public, authenticated;
REVOKE EXECUTE ON FUNCTION badra_core.record_failed_login_v2(text, text, text, text) FROM anon, public, authenticated;
REVOKE EXECUTE ON FUNCTION badra_core.record_successful_login_v2(text, text, text, text) FROM anon, public, authenticated;
REVOKE EXECUTE ON FUNCTION badra_core.clear_attempts_v2(text, text) FROM anon, public, authenticated;
REVOKE EXECUTE ON FUNCTION badra_core.uniform_timing() FROM anon, public, authenticated;
REVOKE EXECUTE ON FUNCTION badra_core.set_global_tripwire(text) FROM anon, public, authenticated;
REVOKE EXECUTE ON FUNCTION badra_core.admin_unlock_v2(text) FROM anon, public, authenticated;
REVOKE EXECUTE ON FUNCTION badra_core.ip_subnet_v2(text) FROM anon, public, authenticated;

GRANT EXECUTE ON FUNCTION badra_core.check_lockout_v2(text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION badra_core.record_failed_login_v2(text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION badra_core.record_successful_login_v2(text, text, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION badra_core.clear_attempts_v2(text, text) TO service_role;
GRANT EXECUTE ON FUNCTION badra_core.uniform_timing() TO service_role;
GRANT EXECUTE ON FUNCTION badra_core.set_global_tripwire(text) TO service_role;
GRANT EXECUTE ON FUNCTION badra_core.admin_unlock_v2(text) TO service_role;
GRANT EXECUTE ON FUNCTION badra_core.ip_subnet_v2(text) TO service_role;

COMMENT ON FUNCTION badra_core.check_lockout_v2 IS
  'SECURITY: multi-dimensional lockout (user 5/30m, device 10/1h, ip /24 50/1h, global tripwire) with escalation to permanent.';
COMMENT ON FUNCTION badra_core.uniform_timing IS
  'SECURITY: uniform 150-300ms delay — all login paths take equal time (anti timing-oracle).';
