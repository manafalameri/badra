-- ============================================================
-- بذرة (Badra) — تفعيل تقييد الحساب بالجهاز (Android ID)
-- إضافات فقط على الموجود: لا جداول جديدة، لا أعمدة جديدة
-- ============================================================
-- 1. check_login_device — يُستدعى بعد نجاح كلمة المرور:
--    لا جهاز محفور → يربط هذا الجهاز فوراً (أول دخول)
--    الجهاز محفور → سماح + تحديث last_login
--    جهاز محفور آخر → رفض "هذا الحساب مرتبط بجهاز آخر"
-- 2. verify_authorized_device — حارس الـ RPCs الحساسة
-- 3. carve_device — إضافة حماية: يرفض حفر جهاز جديد إن وُجد محفور آخر
-- 4. get_my_profile / sync_home_data — معامل p_device_id إجباري
--    ورفض أي جلسة من جهاز غير محفور
-- ============================================================

-- ── 1. check_login_device ──
CREATE OR REPLACE FUNCTION badra_core.check_login_device(
  p_device_id TEXT,
  p_device_name TEXT DEFAULT '',
  p_device_model TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_carved_count INT;
  v_is_carved BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT COUNT(*) INTO v_carved_count
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND carved_at IS NOT NULL;

  -- لا يمكن التعرف على الجهاز: إن وُجد جهاز محفور → فشل مغلق
  IF p_device_id IS NULL OR p_device_id = '' OR p_device_id = 'unknown_device_id' THEN
    IF v_carved_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'تعذر التحقق من هذا الجهاز. حاول مرة أخرى.');
    END IF;
    RETURN jsonb_build_object('success', true, 'bound', false);
  END IF;

  -- أول دخول: لا أجهزة محفورة → اربط هذا الجهاز فوراً
  IF v_carved_count = 0 THEN
    INSERT INTO badra_core.user_devices (
      user_id, device_id, device_name, device_model, carved_at, last_login
    ) VALUES (
      v_user_id, p_device_id, p_device_name, p_device_model, now(), now()
    )
    ON CONFLICT (user_id, device_id) DO UPDATE SET
      carved_at = COALESCE(badra_core.user_devices.carved_at, now()),
      last_login = now(),
      device_name = CASE WHEN p_device_name != '' THEN p_device_name ELSE badra_core.user_devices.device_name END;
    RETURN jsonb_build_object('success', true, 'bound', true);
  END IF;

  -- يوجد جهاز محفور — هل هو هذا الجهاز؟
  SELECT EXISTS (
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = v_user_id AND device_id = p_device_id AND carved_at IS NOT NULL
  ) INTO v_is_carved;

  IF NOT v_is_carved THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الحساب مرتبط بجهاز آخر');
  END IF;

  UPDATE badra_core.user_devices
  SET last_login = now(),
      device_name = CASE WHEN p_device_name != '' THEN p_device_name ELSE device_name END
  WHERE user_id = v_user_id AND device_id = p_device_id;

  RETURN jsonb_build_object('success', true, 'bound', false);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.check_login_device(text, text, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.check_login_device(text, text, text) TO authenticated;

-- ── 2. verify_authorized_device ──
CREATE OR REPLACE FUNCTION badra_core.verify_authorized_device(
  p_device_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_ok BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_device_id IS NULL OR p_device_id = '' OR p_device_id = 'unknown_device_id' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مصرح');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = v_user_id AND device_id = p_device_id AND carved_at IS NOT NULL
  ) INTO v_ok;

  IF NOT v_ok THEN
    RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مصرح');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.verify_authorized_device(text) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.verify_authorized_device(text) TO authenticated;

-- ── 3. carve_device: إضافة الحماية فقط (الباقي مطابق للتعريف الحي) ──
CREATE OR REPLACE FUNCTION badra_core.carve_device(
  p_device_id TEXT,
  p_device_name TEXT,
  p_device_model TEXT DEFAULT '',
  p_public_key_n TEXT DEFAULT '',
  p_public_key_e TEXT DEFAULT '',
  p_public_key_x TEXT DEFAULT '',
  p_public_key_y TEXT DEFAULT '',
  p_key_source TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_existing_carved_at TIMESTAMPTZ;
  v_carved_at TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT carved_at INTO v_existing_carved_at
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND device_id = p_device_id;

  IF v_existing_carved_at IS NOT NULL THEN
    UPDATE badra_core.user_devices
    SET last_login = now(),
        device_name = p_device_name,
        device_model = CASE WHEN p_device_model != '' THEN p_device_model ELSE device_model END,
        public_key_n = CASE WHEN p_public_key_n != '' THEN p_public_key_n ELSE public_key_n END,
        public_key_e = CASE WHEN p_public_key_e != '' THEN p_public_key_e ELSE public_key_e END,
        public_key_x = CASE WHEN p_public_key_x != '' THEN p_public_key_x ELSE public_key_x END,
        public_key_y = CASE WHEN p_public_key_y != '' THEN p_public_key_y ELSE public_key_y END,
        key_source = CASE WHEN p_key_source != '' THEN p_key_source ELSE key_source END,
        key_created_at = CASE WHEN p_public_key_x != '' OR p_public_key_n != '' THEN now() ELSE key_created_at END
    WHERE user_id = v_user_id AND device_id = p_device_id;
    RETURN jsonb_build_object('success', true, 'carved_at', v_existing_carved_at, 'already_carved', true);
  END IF;

  -- ── حماية جديدة: يرفض حفر جهاز جديد إن وُجد جهاز محفور آخر ──
  IF EXISTS (
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = v_user_id AND carved_at IS NOT NULL AND device_id <> p_device_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الحساب مرتبط بجهاز آخر. لا يمكن ربط جهاز جديد.');
  END IF;

  INSERT INTO badra_core.user_devices (
    user_id, device_id, device_name, device_model,
    carved_at, last_login,
    public_key_n, public_key_e,
    public_key_x, public_key_y, key_source, key_created_at
  ) VALUES (
    v_user_id, p_device_id, p_device_name, p_device_model,
    now(), now(),
    p_public_key_n, p_public_key_e,
    p_public_key_x, p_public_key_y, p_key_source,
    CASE WHEN p_public_key_x != '' OR p_public_key_n != '' THEN now() ELSE NULL END
  )
  ON CONFLICT (user_id, device_id) DO UPDATE SET
    last_login = now(),
    carved_at = COALESCE(badra_core.user_devices.carved_at, now()),
    public_key_n = CASE WHEN p_public_key_n != '' THEN p_public_key_n ELSE badra_core.user_devices.public_key_n END,
    public_key_e = CASE WHEN p_public_key_e != '' THEN p_public_key_e ELSE badra_core.user_devices.public_key_e END,
    public_key_x = CASE WHEN p_public_key_x != '' THEN p_public_key_x ELSE badra_core.user_devices.public_key_x END,
    public_key_y = CASE WHEN p_public_key_y != '' THEN p_public_key_y ELSE badra_core.user_devices.public_key_y END,
    key_source = CASE WHEN p_key_source != '' THEN p_key_source ELSE badra_core.user_devices.key_source END,
    key_created_at = CASE WHEN p_public_key_x != '' OR p_public_key_n != '' THEN now() ELSE badra_core.user_devices.key_created_at END;

  SELECT carved_at INTO v_carved_at
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND device_id = p_device_id;

  RETURN jsonb_build_object('success', true, 'carved_at', v_carved_at);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.carve_device(text, text, text, text, text, text, text, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.carve_device(text, text, text, text, text, text, text, text) TO authenticated;

-- ── 4. get_my_profile: معامل device إجباري ──
DROP FUNCTION IF EXISTS badra_core.get_my_profile();

CREATE OR REPLACE FUNCTION badra_core.get_my_profile(
  p_device_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_check JSONB;
BEGIN
  v_check := badra_core.verify_authorized_device(p_device_id);
  IF v_check->>'success' != 'true' THEN
    RETURN jsonb_build_object('error', COALESCE(v_check->>'error', 'الجهاز غير مصرح'));
  END IF;

  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profile not found');
  END IF;

  RETURN jsonb_build_object(
    'name', v_profile.name,
    'balance', v_profile.balance,
    'is_active', v_profile.is_active
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.get_my_profile(text) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.get_my_profile(text) TO authenticated;

-- ── 5. sync_home_data: معامل device إجباري ──
DROP FUNCTION IF EXISTS badra_core.sync_home_data();

CREATE OR REPLACE FUNCTION badra_core.sync_home_data(
  p_device_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_check JSONB;
  v_pending JSONB;
  v_has_device BOOLEAN;
  v_setup_required BOOLEAN;
  v_locked BOOLEAN;
  v_attempt_count INT;
  v_max_attempts INT := 5;
  v_lockout_minutes INT := 30;
BEGIN
  v_check := badra_core.verify_authorized_device(p_device_id);
  IF v_check->>'success' != 'true' THEN
    RETURN jsonb_build_object('error', COALESCE(v_check->>'error', 'الجهاز غير مصرح'));
  END IF;

  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profile not found');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', pr.id,
      'merchant_name', m.name,
      'amount', pr.amount,
      'order_ref', pr.order_ref,
      'items', pr.items,
      'expires_at', pr.expires_at,
      'created_at', pr.created_at,
      'expires_in_seconds', extract(epoch from (pr.expires_at - now()))
    ) ORDER BY pr.created_at DESC
  ), '[]'::jsonb) INTO v_pending
  FROM badra_core.payment_requests pr
  JOIN badra_core.merchants m ON m.id = pr.merchant_id
  WHERE pr.user_id = auth.uid()
    AND pr.status = 'pending'
    AND pr.expires_at > now();

  SELECT EXISTS(
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = auth.uid() AND carved_at IS NOT NULL
  ) INTO v_has_device;

  SELECT security_code IS NULL OR security_code = '' INTO v_setup_required
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = auth.uid()
    AND attempt_type = 'security_code'
    AND attempted_at > now() - (v_lockout_minutes || ' minutes')::INTERVAL;

  v_locked := v_attempt_count >= v_max_attempts;

  RETURN jsonb_build_object(
    'profile', jsonb_build_object(
      'name', v_profile.name,
      'balance', v_profile.balance
    ),
    'pending_requests', v_pending,
    'has_device', v_has_device,
    'setup_required', v_setup_required,
    'locked', v_locked
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.sync_home_data(text) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.sync_home_data(text) TO authenticated;