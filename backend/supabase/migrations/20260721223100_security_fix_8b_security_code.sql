-- =============================================================================
-- SECURITY FIX 8b: Enforce 6-digit PIN in set_security_code + bcrypt-only (M5/H7)
-- =============================================================================
-- Keeps the existing 2-param signature (p_new_code, p_current_code) which
-- requires the current PIN to change it. Hardens:
--   1. Exactly 6 digits for the new code (was: 4+ any chars)
--   2. bcrypt-only current-code check (plaintext fallback removed)
-- =============================================================================

CREATE OR REPLACE FUNCTION badra_core.set_security_code(
  p_new_code TEXT,
  p_current_code TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'badra_core', 'public', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_stored_hash TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  -- SECURITY: exactly 6 digits, enforced server-side
  IF p_new_code !~ '^\d{6}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الرقم السري يجب أن يكون 6 أرقام');
  END IF;

  SELECT security_code INTO v_stored_hash
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  -- If a code is already set, require the current code to change it
  IF v_stored_hash IS NOT NULL AND v_stored_hash != '' THEN
    IF p_current_code = '' THEN
      RETURN jsonb_build_object('success', false, 'error', 'يجب إدخال الرقم السري الحالي لتغييره');
    END IF;

    -- bcrypt-only comparison (all PINs migrated to bcrypt)
    IF v_stored_hash NOT LIKE '$2%' THEN
      RETURN jsonb_build_object('success', false, 'error', 'يجب إعادة تعيين الرقم السري');
    END IF;

    IF v_stored_hash != crypt(p_current_code, v_stored_hash) THEN
      RETURN jsonb_build_object('success', false, 'error', 'الرقم السري الحالي غير صحيح');
    END IF;
  END IF;

  UPDATE badra_core.profiles
  SET security_code = crypt(p_new_code, gen_salt('bf', 10)),
      updated_at = now()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('success', true);
END;
$function$;

REVOKE EXECUTE ON FUNCTION badra_core.set_security_code(TEXT, TEXT) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.set_security_code(TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION badra_core.set_security_code IS
  'SECURITY: Exactly 6 digits + bcrypt-only + current-code required for changes.';
