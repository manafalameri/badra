-- 20260725_unify_security_flow.sql
-- توحيد تدفق الأمان: PIN واحد + Device Binding (إلغاء Challenge Code)

BEGIN;

-- 1. إزالة challenge_code من profiles
ALTER TABLE badra_core.profiles 
  DROP COLUMN IF EXISTS challenge_code;

-- 2. حذف RPCs الخاصة بـ challenge_code
DROP FUNCTION IF EXISTS badra_core.set_challenge_code(TEXT);
DROP FUNCTION IF EXISTS badra_core.verify_challenge_code(TEXT);

-- 3. تعديل challenge_attempts — الاحتفاظ بـ security_code فقط
ALTER TABLE badra_core.challenge_attempts
  DROP CONSTRAINT IF EXISTS challenge_attempts_attempt_type_check,
  ADD CONSTRAINT challenge_attempts_attempt_type_check 
    CHECK (attempt_type IN ('security_code'));

-- 4. إنشاء check_security_setup RPC المفقود (مستدعى من Dart)
CREATE OR REPLACE FUNCTION badra_core.check_security_setup()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_has_pin BOOLEAN;
  v_has_device BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'setup_required', true);
  END IF;

  SELECT security_code IS NOT NULL AND security_code != '' INTO v_has_pin
  FROM badra_core.profiles WHERE user_id = v_user_id;

  SELECT COUNT(*) > 0 INTO v_has_device
  FROM badra_core.user_devices WHERE user_id = v_user_id AND carved_at IS NOT NULL;

  RETURN jsonb_build_object(
    'success', true,
    'has_pin', v_has_pin,
    'has_device', v_has_device,
    'setup_required', NOT v_has_pin
  );
END;
$$;

-- 5. تحديث create_payment_request — يتطلب security_code فقط
CREATE OR REPLACE FUNCTION badra_core.create_payment_request(
  p_merchant_id UUID,
  p_user_phone TEXT,
  p_amount NUMERIC,
  p_order_ref TEXT,
  p_items JSONB DEFAULT '[]'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_merchant badra_core.merchants%ROWTYPE;
  v_profile badra_core.profiles%ROWTYPE;
  v_request_id UUID;
  c_user_error CONSTANT TEXT := 'تعذر إنشاء الطلب. تحقق من بيانات المستخدم';
BEGIN
  SELECT * INTO v_merchant FROM badra_core.merchants WHERE id = p_merchant_id AND is_active = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المتجر غير موجود أو غير نشط');
  END IF;

  SELECT * INTO v_profile FROM badra_core.profiles WHERE phone = p_user_phone AND is_active = true;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', c_user_error); END IF;

  -- ONLY security_code check (challenge_code removed)
  IF v_profile.security_code IS NULL OR v_profile.security_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  IF v_profile.balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  IF EXISTS (SELECT 1 FROM badra_core.payment_requests WHERE merchant_id = p_merchant_id AND order_ref = p_order_ref) THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب موجود مسبقاً');
  END IF;

  IF (SELECT COUNT(*) FROM badra_core.payment_requests WHERE user_id = v_profile.user_id AND status = 'pending' AND expires_at > now()) >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  INSERT INTO badra_core.payment_requests (merchant_id, user_id, amount, order_ref, items, status, expires_at)
  VALUES (p_merchant_id, v_profile.user_id, p_amount, p_order_ref, p_items, 'pending', now() + interval '10 minutes')
  RETURNING id INTO v_request_id;

  RETURN jsonb_build_object('success', true, 'request_id', v_request_id, 'status', 'pending', 'expires_in_seconds', 600);
END;
$$;

-- 6. تحديث approve_payment_request_v2 — يتطلب security_code فقط (للتوافق العكسي)
CREATE OR REPLACE FUNCTION badra_core.approve_payment_request_v2(
  p_request_id UUID,
  p_challenge_code TEXT DEFAULT '',
  p_device_id TEXT DEFAULT '',
  p_security_code TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_request RECORD;
  v_attempt_count INT;
  v_pin_stored TEXT;
  v_device_record RECORD;
  v_balance NUMERIC;
  v_tx_id UUID;
  v_merchant_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  -- Lockout for security_code only
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = 'security_code'
    AND attempted_at > now() - interval '30 minutes';
  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم قفل الرقم السري مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  SELECT * INTO v_request FROM badra_core.payment_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'طلب الدفع غير موجود'); END IF;
  IF v_request.user_id != v_user_id THEN RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بهذا الطلب'); END IF;
  IF v_request.status != 'pending' THEN RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب تم معالجته مسبقاً'); END IF;
  IF v_request.expires_at < now() THEN
    UPDATE badra_core.payment_requests SET status = 'expired' WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  IF p_device_id = '' THEN RETURN jsonb_build_object('success', false, 'error', 'معرف الجهاز مطلوب'); END IF;
  SELECT * INTO v_device_record FROM badra_core.user_devices WHERE user_id = v_user_id AND device_id = p_device_id;
  IF v_device_record IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مسجل. يرجى تسجيل الدخول من جهازك'); END IF;

  -- ONLY security_code verification (challenge_code ignored)
  SELECT security_code INTO v_pin_stored FROM badra_core.profiles WHERE user_id = v_user_id;
  IF v_pin_stored IS NULL OR v_pin_stored = '' THEN RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين الرقم السري'); END IF;
  IF p_security_code = '' THEN RETURN jsonb_build_object('success', false, 'error', 'الرقم السري إجباري'); END IF;
  IF v_pin_stored NOT LIKE '$2%' THEN RETURN jsonb_build_object('success', false, 'error', 'يجب إعادة تعيين الرقم السري من الإعدادات'); END IF;
  IF v_pin_stored != crypt(p_security_code, v_pin_stored) THEN
    INSERT INTO badra_core.challenge_attempts (user_id, attempt_type) VALUES (v_user_id, 'security_code');
    RETURN jsonb_build_object('success', false, 'error', 'الرقم السري غير صحيح');
  END IF;
  DELETE FROM badra_core.challenge_attempts WHERE user_id = v_user_id AND attempt_type = 'security_code';

  SELECT balance INTO v_balance FROM badra_core.profiles WHERE user_id = v_user_id FOR UPDATE;
  IF v_balance < v_request.amount THEN RETURN jsonb_build_object('success', false, 'error', 'رصيد غير كافي'); END IF;

  UPDATE badra_core.profiles SET balance = balance - v_request.amount, updated_at = now() WHERE user_id = v_user_id;
  SELECT name INTO v_merchant_name FROM badra_core.merchants WHERE id = v_request.merchant_id;
  INSERT INTO badra_core.transactions_v2 (user_id, is_in, amount, title, status, date, notes, ref, store)
  VALUES (v_user_id, 0, v_request.amount, 'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'), 'completed', now(), 'order_ref: ' || v_request.order_ref, v_request.order_ref, COALESCE(v_merchant_name, ''))
  RETURNING id INTO v_tx_id;
  UPDATE badra_core.payment_requests SET status = 'approved', approved_at = now(), tx_id = v_tx_id WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'transaction_id', v_tx_id,
    'new_balance', v_balance - v_request.amount, 'old_balance', v_balance, 'amount', v_request.amount);
END;
$$;

-- 7. منح الصلاحيات
GRANT EXECUTE ON FUNCTION badra_core.check_security_setup() TO authenticated;
GRANT EXECUTE ON FUNCTION badra_core.create_payment_request(UUID, TEXT, NUMERIC, TEXT, JSONB) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION badra_core.approve_payment_request_v2(UUID, TEXT, TEXT, TEXT) TO authenticated;

COMMIT;