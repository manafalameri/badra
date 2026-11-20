-- ============================================================
-- Security Step 1: Carving + Device Binding + RPC Fixes
-- ============================================================
-- يضيف:
--   1. carved_at / device_model إلى user_devices
--   2. UNIQUE (user_id, device_id) — يمنع تكرار الجهاز
--   3. RLS: يمنع UPDATE المباشر (لا يُسمح للمستخدم بتحديث carved_at أو device_id)
--   4. RPC carve_device — حفر الجهاز بشكل دائم (مرة واحدة)
--   5. RPC set_security_code — المفقود من قبل (يستخدمه Flutter)
--   6. RPC verify_device — التحقق من أن الجهاز مسجل
--   7. جدول challenge_attempts + RPCs للـ lockout
-- ============================================================

-- 1. Add carved_at and device_model to user_devices
ALTER TABLE badra_core.user_devices
  ADD COLUMN IF NOT EXISTS carved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS device_model TEXT DEFAULT '';

-- 2. Add UNIQUE constraint on (user_id, device_id)
ALTER TABLE badra_core.user_devices
  DROP CONSTRAINT IF EXISTS user_devices_user_device_unique;
ALTER TABLE badra_core.user_devices
  ADD CONSTRAINT user_devices_user_device_unique UNIQUE (user_id, device_id);

-- 3. Fix RLS: Remove permissive UPDATE policy
--    المستخدم العادي لا يستطيع تحديث user_devices مباشرة
--    كل التحديثات تكون عبر SECURITY DEFINER RPCs فقط
DROP POLICY IF EXISTS user_devices_update_own ON badra_core.user_devices;

-- 4. RPC: carve_device — الحفر لمرة واحدة فقط
-- Updated in 20260724000300: accepts public key params, stores them in user_devices
CREATE OR REPLACE FUNCTION badra_core.carve_device(
  p_device_id TEXT,
  p_device_name TEXT,
  p_device_model TEXT DEFAULT '',
  p_public_key_n TEXT DEFAULT '',
  p_public_key_e TEXT DEFAULT ''
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

  -- Check if this device is already carved
  SELECT carved_at INTO v_existing_carved_at
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND device_id = p_device_id;

  IF v_existing_carved_at IS NOT NULL THEN
    -- Already carved: just update last_login, device info, and public keys
    UPDATE badra_core.user_devices
    SET last_login = now(),
        device_name = p_device_name,
        device_model = CASE WHEN p_device_model != '' THEN p_device_model ELSE device_model END,
        public_key_n = CASE WHEN p_public_key_n != '' THEN p_public_key_n ELSE public_key_n END,
        public_key_e = CASE WHEN p_public_key_e != '' THEN p_public_key_e ELSE public_key_e END,
        key_created_at = CASE WHEN p_public_key_n != '' THEN now() ELSE key_created_at END
    WHERE user_id = v_user_id AND device_id = p_device_id;
    RETURN jsonb_build_object('success', true, 'carved_at', v_existing_carved_at, 'already_carved', true);
  END IF;

  -- New device: carve it permanently
  INSERT INTO badra_core.user_devices (
    user_id, device_id, device_name, device_model,
    carved_at, last_login, public_key_n, public_key_e, key_created_at
  ) VALUES (
    v_user_id, p_device_id, p_device_name, p_device_model,
    now(), now(), p_public_key_n, p_public_key_e,
    CASE WHEN p_public_key_n != '' THEN now() ELSE NULL END
  )
  ON CONFLICT (user_id, device_id) DO UPDATE SET
    last_login = now(),
    carved_at = COALESCE(badra_core.user_devices.carved_at, now()),
    public_key_n = CASE WHEN p_public_key_n != '' THEN p_public_key_n ELSE badra_core.user_devices.public_key_n END,
    public_key_e = CASE WHEN p_public_key_e != '' THEN p_public_key_e ELSE badra_core.user_devices.public_key_e END,
    key_created_at = CASE WHEN p_public_key_n != '' THEN now() ELSE badra_core.user_devices.key_created_at END;

  SELECT carved_at INTO v_carved_at
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND device_id = p_device_id;

  RETURN jsonb_build_object('success', true, 'carved_at', v_carved_at);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.carve_device FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.carve_device TO authenticated;

-- 5. RPC: set_security_code — كان مفقودًا، يستخدمه Flutter في setupPin
CREATE OR REPLACE FUNCTION badra_core.set_security_code(
  p_new_code TEXT,
  p_current_code TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_stored_hash TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF length(p_new_code) < 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'كود الأمان يجب أن يكون 4 أحرف على الأقل');
  END IF;

  -- Check if a security code already exists
  SELECT security_code INTO v_stored_hash
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  IF v_stored_hash IS NOT NULL AND v_stored_hash != '' THEN
    IF p_current_code = '' THEN
      RETURN jsonb_build_object('success', false, 'error', 'يجب إدخال كود الأمان الحالي لتغييره');
    END IF;

    IF v_stored_hash ~ '^\$2[ayb]\$.{56}$' THEN
      IF v_stored_hash != crypt(p_current_code, v_stored_hash) THEN
        RETURN jsonb_build_object('success', false, 'error', 'كود الأمان الحالي غير صحيح');
      END IF;
    ELSE
      IF v_stored_hash != p_current_code THEN
        RETURN jsonb_build_object('success', false, 'error', 'كود الأمان الحالي غير صحيح');
      END IF;
    END IF;
  END IF;

  UPDATE badra_core.profiles
  SET security_code = crypt(p_new_code, gen_salt('bf', 10)),
      updated_at = now()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.set_security_code FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.set_security_code TO authenticated;

-- 6. RPC: verify_device — التحقق من أن الجهاز الحالي مسجل ومحفور
CREATE OR REPLACE FUNCTION badra_core.verify_device(
  p_device_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_carved_at TIMESTAMPTZ;
  v_device_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT carved_at, device_name INTO v_carved_at, v_device_name
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND device_id = p_device_id;

  IF v_carved_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'carved', false, 'error', 'الجهاز غير مسجل');
  END IF;

  UPDATE badra_core.user_devices
  SET last_login = now()
  WHERE user_id = v_user_id AND device_id = p_device_id;

  RETURN jsonb_build_object('success', true, 'carved', true, 'carved_at', v_carved_at, 'device_name', v_device_name);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.verify_device FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.verify_device TO authenticated;

-- 7. جدول challenge_attempts لتتبع المحاولات الفاشلة (Lockout)
CREATE TABLE IF NOT EXISTS badra_core.challenge_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  attempt_type TEXT NOT NULL CHECK (attempt_type IN ('challenge_code', 'security_code')),
  attempted_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_challenge_attempts_user
  ON badra_core.challenge_attempts(user_id, attempt_type, attempted_at);

ALTER TABLE badra_core.challenge_attempts ENABLE ROW LEVEL SECURITY;
-- لا يوجد RLS policies — الوصول فقط عبر SECURITY DEFINER RPCs

-- 8. RPC: check_lockout — هل المستخدم مقفل؟
CREATE OR REPLACE FUNCTION badra_core.check_lockout(
  p_attempt_type TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_attempt_count INT;
  v_max_attempts INT := 5;
  v_lockout_minutes INT := 30;
  v_recent_attempt TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id
    AND attempt_type = p_attempt_type
    AND attempted_at > now() - (v_lockout_minutes || ' minutes')::INTERVAL;

  SELECT MAX(attempted_at) INTO v_recent_attempt
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id
    AND attempt_type = p_attempt_type;

  IF v_attempt_count >= v_max_attempts THEN
    RETURN jsonb_build_object(
      'success', false,
      'locked', true,
      'attempts', v_attempt_count,
      'max_attempts', v_max_attempts,
      'locked_until', v_recent_attempt + (v_lockout_minutes || ' minutes')::INTERVAL
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'locked', false,
    'attempts', v_attempt_count,
    'max_attempts', v_max_attempts,
    'remaining', v_max_attempts - v_attempt_count
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.check_lockout FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.check_lockout TO authenticated;

-- 9. RPC: record_failed_attempt — تسجيل محاولة فاشلة
CREATE OR REPLACE FUNCTION badra_core.record_failed_attempt(
  p_attempt_type TEXT
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

  INSERT INTO badra_core.challenge_attempts (user_id, attempt_type)
  VALUES (v_user_id, p_attempt_type);

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.record_failed_attempt FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.record_failed_attempt TO authenticated;

-- 10. RPC: clear_attempts — مسح المحاولات بعد النجاح
CREATE OR REPLACE FUNCTION badra_core.clear_attempts(
  p_attempt_type TEXT
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

  DELETE FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = p_attempt_type;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.clear_attempts FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.clear_attempts TO authenticated;

-- 11. RPC: has_carved_device — هل يوجد جهاز محفور للمستخدم؟
CREATE OR REPLACE FUNCTION badra_core.has_carved_device()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_count INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND carved_at IS NOT NULL;

  RETURN jsonb_build_object('success', true, 'has_device', v_count > 0, 'device_count', v_count);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.has_carved_device FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.has_carved_device TO authenticated;

-- 12. تحديث RPC register_fcm_token ليكون SECURITY DEFINER
--     (حتى يعمل مع إزالة UPDATE policy)
CREATE OR REPLACE FUNCTION badra_core.register_fcm_token(
  p_fcm_token TEXT
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

  IF p_fcm_token = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'FCM token فارغ');
  END IF;

  -- Update the most recently used device's FCM token
  UPDATE badra_core.user_devices
  SET fcm_token = p_fcm_token
  WHERE user_id = v_user_id
    AND id = (
      SELECT id FROM badra_core.user_devices
      WHERE user_id = v_user_id
      ORDER BY last_login DESC NULLS LAST
      LIMIT 1
    );

  IF NOT FOUND THEN
    INSERT INTO badra_core.user_devices (user_id, fcm_token)
    VALUES (v_user_id, p_fcm_token);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.register_fcm_token FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.register_fcm_token TO authenticated;
