-- =============================================================================
-- بذرة (Badra) — Secure Admin Verification & Password Reset
-- =============================================================================
-- Provides two strictly-guarded administrative RPC functions:
--   1. admin_verify_user_info: Inspects user profile, carved device, and recent txs
--   2. admin_verify_and_reset_password: Atomically verifies Phone + Name + Device ID
--      before updating the password in auth.users and clearing any lockouts.
--
-- Access Control:
--   REVOKE ALL from anon, public, authenticated.
--   GRANT EXECUTE to service_role and postgres (Supabase Dashboard SQL Editor).
-- =============================================================================

CREATE OR REPLACE FUNCTION badra_core.admin_verify_user_info(
  p_phone TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, auth, public, extensions
AS $$
DECLARE
  v_clean_phone TEXT;
  v_profile RECORD;
  v_device RECORD;
  v_txs JSONB;
BEGIN
  v_clean_phone := regexp_replace(p_phone, '[^0-9]', '', 'g');
  IF v_clean_phone LIKE '00967%' THEN
    v_clean_phone := substr(v_clean_phone, 6);
  ELSIF v_clean_phone LIKE '967%' THEN
    v_clean_phone := substr(v_clean_phone, 4);
  ELSIF v_clean_phone LIKE '0%' THEN
    v_clean_phone := substr(v_clean_phone, 2);
  END IF;

  SELECT id, user_id, phone, name, wallet_id, balance, is_active, created_at
  INTO v_profile
  FROM badra_core.profiles
  WHERE phone IN (v_clean_phone, '967' || v_clean_phone, '+967' || v_clean_phone)
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'لم يتم العثور على أي حساب مسجل بهذا الرقم: ' || p_phone
    );
  END IF;

  SELECT device_id, device_name, device_model, carved_at, last_login
  INTO v_device
  FROM badra_core.user_devices
  WHERE user_id = v_profile.user_id
  ORDER BY carved_at DESC NULLS LAST, last_login DESC NULLS LAST
  LIMIT 1;

  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'date', t.date,
    'amount', t.amount,
    'is_in', t.is_in,
    'title', t.title,
    'store', t.store,
    'status', t.status
  )), '[]'::jsonb)
  INTO v_txs
  FROM (
    SELECT date, amount, is_in, title, store, status
    FROM badra_core.transactions_v2
    WHERE user_id = v_profile.user_id
    ORDER BY date DESC
    LIMIT 3
  ) t;

  RETURN jsonb_build_object(
    'success', true,
    'profile', jsonb_build_object(
      'name', v_profile.name,
      'phone', v_profile.phone,
      'wallet_id', v_profile.wallet_id,
      'balance', v_profile.balance,
      'is_active', v_profile.is_active,
      'created_at', to_char(v_profile.created_at, 'YYYY-MM-DD HH24:MI:SS')
    ),
    'device', jsonb_build_object(
      'device_id', COALESCE(v_device.device_id, 'لا يوجد جهاز محفور'),
      'device_name', COALESCE(v_device.device_name, ''),
      'device_model', COALESCE(v_device.device_model, ''),
      'carved_at', to_char(v_device.carved_at, 'YYYY-MM-DD HH24:MI:SS'),
      'last_login', to_char(v_device.last_login, 'YYYY-MM-DD HH24:MI:SS')
    ),
    'recent_transactions', v_txs
  );
END;
$$;

CREATE OR REPLACE FUNCTION badra_core.admin_verify_and_reset_password(
  p_phone TEXT,
  p_name TEXT,
  p_device_id TEXT,
  p_new_password TEXT,
  p_force_device_replace BOOLEAN DEFAULT false
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, auth, public, extensions
AS $$
DECLARE
  v_clean_phone TEXT;
  v_profile RECORD;
  v_existing_device RECORD;
  v_name_clean TEXT;
  v_profile_name_clean TEXT;
BEGIN
  IF p_new_password IS NULL OR length(p_new_password) < 6 THEN
    RETURN jsonb_build_object('success', false, 'error', 'كلمة المرور الجديدة يجب أن تكون 6 أحرف أو أكثر');
  END IF;

  IF p_name IS NULL OR trim(p_name) = '' OR trim(p_name) = 'ضع اسمك هنا' OR trim(p_name) = 'اكتب اسمك هنا' THEN
    RETURN jsonb_build_object('success', false, 'error', 'يجب إدخال اسم العميل للتحقق من هويته');
  END IF;

  IF p_device_id IS NULL OR trim(p_device_id) = '' OR trim(p_device_id) = 'unknown_device_id' THEN
    RETURN jsonb_build_object('success', false, 'error', 'معرّف الجهاز (Device ID) مطلوب للتحقق الأمني');
  END IF;

  v_clean_phone := regexp_replace(p_phone, '[^0-9]', '', 'g');
  IF v_clean_phone LIKE '00967%' THEN
    v_clean_phone := substr(v_clean_phone, 6);
  ELSIF v_clean_phone LIKE '967%' THEN
    v_clean_phone := substr(v_clean_phone, 4);
  ELSIF v_clean_phone LIKE '0%' THEN
    v_clean_phone := substr(v_clean_phone, 2);
  END IF;

  SELECT id, user_id, phone, name
  INTO v_profile
  FROM badra_core.profiles
  WHERE phone IN (v_clean_phone, '967' || v_clean_phone, '+967' || v_clean_phone)
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'رقم الهاتف غير مسجل في النظام');
  END IF;

  -- 1. التحقق من تطابق الاسم
  v_name_clean := lower(trim(regexp_replace(p_name, '\s+', ' ', 'g')));
  v_profile_name_clean := lower(trim(regexp_replace(v_profile.name, '\s+', ' ', 'g')));

  IF v_name_clean NOT LIKE '%' || split_part(v_profile_name_clean, ' ', 1) || '%'
     AND v_profile_name_clean NOT LIKE '%' || split_part(v_name_clean, ' ', 1) || '%' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'فشل التحقق الأمني: الاسم المدخل (' || p_name || ') غير متطابق مع اسم صاحب الحساب (' || v_profile.name || ')'
    );
  END IF;

  -- 2. التحقق من تطابق معرّف الجهاز (Device ID)
  SELECT id, device_id INTO v_existing_device
  FROM badra_core.user_devices
  WHERE user_id = v_profile.user_id
  ORDER BY carved_at DESC NULLS LAST, last_login DESC NULLS LAST
  LIMIT 1;

  IF NOT p_force_device_replace THEN
    IF v_existing_device.device_id IS NOT NULL AND v_existing_device.device_id != '' AND v_existing_device.device_id != trim(p_device_id) THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'فشل التحقق الأمني: معرّف الجهاز (' || trim(p_device_id) || ') غير متطابق مع الجهاز المسجل للحساب (' || v_existing_device.device_id || '). إن كان الهاتف مفقوداً وتريد استبداله، مرر p_force_device_replace := true'
      );
    END IF;
  ELSE
    -- في حال استبدال جهاز مفقود بتفويض الأدمن
    UPDATE badra_core.user_devices
    SET device_id = trim(p_device_id),
        carved_at = COALESCE(carved_at, now()),
        last_login = now()
    WHERE user_id = v_profile.user_id;
  END IF;

  -- 3. تحديث كلمة المرور في auth.users
  UPDATE auth.users
  SET encrypted_password = crypt(p_new_password, gen_salt('bf', 10)),
      updated_at = now()
  WHERE id = v_profile.user_id;

  -- 4. فك أي قفل سابق على الحساب ومسح العدادات الفاشلة
  DELETE FROM badra_core.security_attempts_v2
  WHERE target IN (v_clean_phone, '967' || v_clean_phone, '+967' || v_clean_phone, trim(p_device_id))
    AND attempt_type = 'login';

  INSERT INTO badra_core.security_attempts_v2 (dimension, target, attempt_type, outcome, ip, user_agent)
  VALUES ('user', v_profile.phone, 'password_reset', 'success', 'supabase_sql_dashboard', 'admin_verified_reset');

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم التحقق بنجاح وتحديث كلمة المرور وفك القفل عن الحساب فوراً',
    'phone', v_profile.phone,
    'name', v_profile.name,
    'device_id', trim(p_device_id)
  );
END;
$$;

REVOKE ALL ON FUNCTION badra_core.admin_verify_user_info(TEXT) FROM anon, public, authenticated;
REVOKE ALL ON FUNCTION badra_core.admin_verify_and_reset_password(TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM anon, public, authenticated;

GRANT EXECUTE ON FUNCTION badra_core.admin_verify_user_info(TEXT) TO service_role, postgres;
GRANT EXECUTE ON FUNCTION badra_core.admin_verify_and_reset_password(TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO service_role, postgres;
