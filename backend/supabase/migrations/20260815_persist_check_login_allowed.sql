-- =============================================================================
-- SECURITY: Persist check_login_allowed (rescued from LIVE DB)
-- =============================================================================
-- This function existed ONLY in the live database (created via dashboard),
-- never in migrations. Any `supabase db reset` or new branch would silently
-- lose it, leaving login without its lockout pre-check (time bomb).
--
-- Definition copied VERBATIM from the live database on 2026-08-15.
-- It is superseded by the secure `login` Edge Function + lockout_v2
-- (see 20260815_lockout_v2.sql), but must survive resets until the
-- Flutter app fully migrates to the new path.
-- =============================================================================

CREATE OR REPLACE FUNCTION badra_core.check_login_allowed(p_phone text, p_action text DEFAULT 'login'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'badra_core', 'public'
AS $function$
DECLARE
  v_user_id UUID;
  v_attempt_count INT;
  v_profile RECORD;
BEGIN
  -- Look up user by phone
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE phone = p_phone;

  IF NOT FOUND THEN
    -- No user: don't reveal existence, allow to proceed
    RETURN jsonb_build_object('success', true, 'allowed', true, 'reason', 'no_user');
  END IF;

  -- Check if account is active
  IF NOT v_profile.is_active THEN
    RETURN jsonb_build_object('success', true, 'allowed', false, 'reason', 'inactive', 'error', 'الحساب غير نشط');
  END IF;

  -- Check lockout: max 5 failed login attempts in 30 minutes
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_profile.user_id
    AND attempt_type = 'login'
    AND attempted_at > now() - interval '30 minutes';

  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', true, 'allowed', false, 'reason', 'locked', 'error', 'تم قفل الحساب مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  -- Login allowed
  RETURN jsonb_build_object('success', true, 'allowed', true, 'reason', 'ok');
END;
$function$;

REVOKE EXECUTE ON FUNCTION badra_core.check_login_allowed(text, text) FROM public;
GRANT EXECUTE ON FUNCTION badra_core.check_login_allowed(text, text) TO anon;
GRANT EXECUTE ON FUNCTION badra_core.check_login_allowed(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION badra_core.check_login_allowed(text, text) TO service_role;

COMMENT ON FUNCTION badra_core.check_login_allowed IS
  'SECURITY: pre-login lockout check (legacy, superseded by login Edge Function + check_lockout_v2).';
