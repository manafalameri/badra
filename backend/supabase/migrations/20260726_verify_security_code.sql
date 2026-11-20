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
BEGIN
  SELECT security_code INTO v_stored_hash
  FROM badra_core.profiles
  WHERE user_id = p_user_id;

  IF v_stored_hash IS NULL OR v_stored_hash = '' THEN
    RETURN jsonb_build_object('valid', false, 'error', 'لم يتم تعيين الرقم السري');
  END IF;

  IF v_stored_hash = crypt(p_security_code, v_stored_hash) THEN
    RETURN jsonb_build_object('valid', true);
  END IF;

  RETURN jsonb_build_object('valid', false, 'error', 'الرقم السري غير صحيح');
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.verify_security_code FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.verify_security_code TO authenticated;