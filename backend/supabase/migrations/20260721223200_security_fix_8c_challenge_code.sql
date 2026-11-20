CREATE OR REPLACE FUNCTION badra_core.set_challenge_code(
  p_new_code TEXT
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

  -- SECURITY: exactly 6 digits, enforced server-side
  IF p_new_code !~ '^\d{6}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'كود التحدي يجب أن يكون 6 أرقام');
  END IF;

  UPDATE badra_core.profiles
  SET challenge_code = crypt(p_new_code, gen_salt('bf', 10)),
      updated_at = now()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.set_challenge_code(TEXT) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.set_challenge_code(TEXT) TO authenticated;
