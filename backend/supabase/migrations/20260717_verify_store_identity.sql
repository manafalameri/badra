-- RPC: verify_store_identity v4 — 2026-07-18
-- بدون wallet_id + created_at نص DD/MM
CREATE OR REPLACE FUNCTION badra_core.verify_store_identity(
  p_phone TEXT, p_name TEXT, p_security_code TEXT, p_created_at TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = badra_core, public, extensions
AS $$ DECLARE v_profile badra_core.profiles%ROWTYPE; v_auth_created TIMESTAMPTZ; v_ddmm TEXT;
BEGIN
  SELECT * INTO v_profile FROM badra_core.profiles WHERE phone = p_phone AND is_active = true;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود'); END IF;
  IF v_profile.name != p_name THEN RETURN jsonb_build_object('success', false, 'error', 'الاسم غير صحيح'); END IF;
  IF v_profile.security_code IS NULL OR v_profile.security_code = '' THEN RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين كود الأمان'); END IF;
  IF v_profile.security_code ~ '^\$2[ayb]\$.{56}$' THEN
    IF v_profile.security_code != crypt(p_security_code, v_profile.security_code) THEN RETURN jsonb_build_object('success', false, 'error', 'كود الأمان غير صحيح'); END IF;
  ELSE
    IF v_profile.security_code != p_security_code THEN RETURN jsonb_build_object('success', false, 'error', 'كود الأمان غير صحيح'); END IF;
  END IF;
  SELECT created_at INTO v_auth_created FROM auth.users WHERE id = v_profile.user_id;
  IF v_auth_created IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'بيانات غير مكتملة'); END IF;
  v_ddmm := to_char(v_auth_created, 'DD/MM');
  IF v_ddmm != p_created_at THEN RETURN jsonb_build_object('success', false, 'error', 'تاريخ الإنشاء غير صحيح', 'expected', v_ddmm, 'provided', p_created_at); END IF;
  RETURN jsonb_build_object('success', true, 'user_id', v_profile.user_id);
END; $$;
REVOKE EXECUTE ON FUNCTION badra_core.verify_store_identity FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.verify_store_identity TO service_role;
