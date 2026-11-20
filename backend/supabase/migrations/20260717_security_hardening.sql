-- ============================================================
-- Security Hardening — 2026-07-18
-- ============================================================
-- 1. Drop legacy RPCs (deduct_balance_and_create_transaction, approve_payment_request v1)
-- 2. Remove security_code from verify_store_identity (merchant never sees PIN)
-- 3. Remove security_code from create_payment_request (verified during approval)
-- 4. Upgrade approve_payment_request_v2: add PIN check + lockout
-- 5. Drop old overloads
-- ============================================================

-- 1. Drop dangerous legacy RPCs
DROP FUNCTION IF EXISTS badra_core.deduct_balance_and_create_transaction(
  text, numeric, text, text, jsonb
);

-- Drop approve_payment_request v1 (all overloads)
DO $$
DECLARE v_rec RECORD;
BEGIN
  FOR v_rec IN
    SELECT oid, pg_get_function_identity_arguments(oid) as args
    FROM pg_proc
    WHERE proname = 'approve_payment_request'
      AND pronamespace = 'badra_core'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION badra_core.approve_payment_request(' || v_rec.args || ')';
    RAISE NOTICE 'Dropped approve_payment_request(%)', v_rec.args;
  END LOOP;
END $$;

-- 2. verify_store_identity WITHOUT security_code (3 params only)
CREATE OR REPLACE FUNCTION badra_core.verify_store_identity(
  p_phone TEXT, p_name TEXT, p_created_at TEXT
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'badra_core', 'public', 'extensions'
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_auth_created TIMESTAMPTZ;
  v_ddmm TEXT;
BEGIN
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE phone = p_phone AND is_active = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  IF v_profile.name != p_name THEN
    RETURN jsonb_build_object('success', false, 'error', 'الاسم غير صحيح');
  END IF;

  SELECT created_at INTO v_auth_created
  FROM auth.users WHERE id = v_profile.user_id;

  IF v_auth_created IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'بيانات غير مكتملة');
  END IF;

  v_ddmm := to_char(v_auth_created, 'DD/MM');
  IF v_ddmm != p_created_at THEN
    RETURN jsonb_build_object('success', false, 'error', 'تاريخ الإنشاء غير صحيح');
  END IF;

  RETURN jsonb_build_object('success', true, 'user_id', v_profile.user_id);
END;
$$;

-- Drop old 4-param overload if it exists
DROP FUNCTION IF EXISTS badra_core.verify_store_identity(text, text, text, text);

REVOKE ALL ON FUNCTION badra_core.verify_store_identity(text, text, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.verify_store_identity(text, text, text) TO service_role;

-- 3. create_payment_request WITHOUT security_code param
CREATE OR REPLACE FUNCTION badra_core.create_payment_request(
  p_merchant_id UUID, p_user_phone TEXT, p_amount NUMERIC,
  p_order_ref TEXT, p_items JSONB DEFAULT '[]'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_merchant badra_core.merchants%ROWTYPE;
  v_profile badra_core.profiles%ROWTYPE;
  v_request_id UUID;
BEGIN
  SELECT * INTO v_merchant FROM badra_core.merchants WHERE id = p_merchant_id AND is_active = true;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'المتجر غير موجود أو غير نشط'); END IF;

  SELECT * INTO v_profile FROM badra_core.profiles WHERE phone = p_user_phone AND is_active = true;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود أو الحساب غير نشط'); END IF;

  IF v_profile.security_code IS NULL OR v_profile.security_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين كود الأمان. يرجى تعيينه من الإعدادات');
  END IF;

  IF v_profile.balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'error', 'الرصيد غير كاف', 'balance', v_profile.balance, 'required', p_amount);
  END IF;

  IF EXISTS (SELECT 1 FROM badra_core.payment_requests WHERE merchant_id = p_merchant_id AND order_ref = p_order_ref) THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب موجود مسبقاً');
  END IF;

  IF (SELECT COUNT(*) FROM badra_core.payment_requests WHERE user_id = v_profile.user_id AND status = 'pending' AND expires_at > now()) >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'لديك طلبات معلقة كثيرة');
  END IF;

  INSERT INTO badra_core.payment_requests (merchant_id, user_id, amount, order_ref, items, status, expires_at)
  VALUES (p_merchant_id, v_profile.user_id, p_amount, p_order_ref, p_items, 'pending', now() + interval '2 minutes')
  RETURNING id INTO v_request_id;

  RETURN jsonb_build_object('success', true, 'request_id', v_request_id, 'status', 'pending', 'expires_in_seconds', 120);
END;
$$;

-- Drop old 6-param overload if it exists
DROP FUNCTION IF EXISTS badra_core.create_payment_request(uuid, text, text, numeric, text, jsonb);

REVOKE ALL ON FUNCTION badra_core.create_payment_request(uuid, text, numeric, text, jsonb) FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION badra_core.create_payment_request(uuid, text, numeric, text, jsonb) TO service_role;

-- 4. approve_payment_request_v2 WITH security_code + lockout
CREATE OR REPLACE FUNCTION badra_core.approve_payment_request_v2(
  p_request_id UUID,
  p_challenge_code TEXT DEFAULT '',
  p_device_id TEXT DEFAULT '',
  p_security_code TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'badra_core', 'public', 'extensions'
AS $$
DECLARE
  v_request badra_core.payment_requests%ROWTYPE;
  v_balance NUMERIC;
  v_new_balance NUMERIC;
  v_tx_id UUID;
  v_challenge_stored TEXT;
  v_carved_at TIMESTAMPTZ;
  v_user_id UUID;
  v_attempt_count INT;
  v_profile badra_core.profiles%ROWTYPE;
  v_code_ok BOOLEAN;
  v_pin_attempt_type TEXT := 'security_code';
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  -- Lockout check for challenge code
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = 'challenge_code'
    AND attempted_at > now() - interval '30 minutes';
  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم قفل كود التحدي مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  -- Lockout check for security code (PIN)
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = v_pin_attempt_type
    AND attempted_at > now() - interval '30 minutes';
  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم قفل الرمز السري مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  -- Fetch request with row lock
  SELECT * INTO v_request FROM badra_core.payment_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود'); END IF;
  IF v_request.user_id != v_user_id THEN RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب لا يخصك'); END IF;
  IF v_request.status != 'pending' THEN RETURN jsonb_build_object('success', false, 'error', 'الطلب لم يعد معلقاً'); END IF;
  IF v_request.expires_at <= now() THEN
    UPDATE badra_core.payment_requests SET status = 'expired' WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  -- Device verification
  IF p_device_id != '' THEN
    SELECT carved_at INTO v_carved_at
    FROM badra_core.user_devices WHERE user_id = v_user_id AND device_id = p_device_id;
    IF v_carved_at IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مسجل. الرجاء تسجيل الدخول من الجهاز المسجل أولاً.');
    END IF;
    UPDATE badra_core.user_devices SET last_login = now() WHERE user_id = v_user_id AND device_id = p_device_id;
  END IF;

  -- Challenge code verification (only if set)
  SELECT challenge_code INTO v_challenge_stored FROM badra_core.profiles WHERE user_id = v_user_id;
  IF v_challenge_stored IS NOT NULL AND v_challenge_stored != '' THEN
    IF p_challenge_code = '' THEN
      RETURN jsonb_build_object('success', false, 'error', 'يجب إدخال كود التحدي');
    END IF;
    IF v_challenge_stored != crypt(p_challenge_code, v_challenge_stored) THEN
      INSERT INTO badra_core.challenge_attempts (user_id, attempt_type) VALUES (v_user_id, 'challenge_code');
      RETURN jsonb_build_object('success', false, 'error', 'كود التحدي غير صحيح');
    END IF;
    DELETE FROM badra_core.challenge_attempts WHERE user_id = v_user_id AND attempt_type = 'challenge_code';
  END IF;

  -- Security code (PIN) verification
  SELECT * INTO v_profile FROM badra_core.profiles WHERE user_id = v_user_id;
  IF v_profile.security_code IS NULL OR v_profile.security_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين الرمز السري');
  END IF;
  IF p_security_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'يجب إدخال الرمز السري');
  END IF;

  v_code_ok := false;
  IF v_profile.security_code ~ '^\$2[ayb]\$.{56}$' THEN
    v_code_ok := (v_profile.security_code = crypt(p_security_code, v_profile.security_code));
  ELSE
    v_code_ok := (v_profile.security_code = p_security_code);
  END IF;

  IF NOT v_code_ok THEN
    INSERT INTO badra_core.challenge_attempts (user_id, attempt_type) VALUES (v_user_id, v_pin_attempt_type);
    RETURN jsonb_build_object('success', false, 'error', 'الرمز السري غير صحيح');
  END IF;

  -- Clear PIN lockout on success
  DELETE FROM badra_core.challenge_attempts WHERE user_id = v_user_id AND attempt_type = v_pin_attempt_type;

  -- Upgrade plaintext PIN to bcrypt if needed
  IF NOT (v_profile.security_code ~ '^\$2[ayb]\$.{56}$') THEN
    UPDATE badra_core.profiles SET security_code = crypt(p_security_code, gen_salt('bf', 10)), updated_at = now()
    WHERE user_id = v_user_id;
  END IF;

  -- Balance deduction
  SELECT balance INTO v_balance FROM badra_core.profiles WHERE user_id = v_request.user_id FOR UPDATE;
  IF v_balance < v_request.amount THEN
    UPDATE badra_core.payment_requests SET status = 'rejected', rejected_at = now() WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'الرصيد غير كاف', 'balance', v_balance, 'required', v_request.amount);
  END IF;

  v_new_balance := v_balance - v_request.amount;
  UPDATE badra_core.profiles SET balance = v_new_balance, updated_at = now() WHERE user_id = v_request.user_id;

  INSERT INTO badra_core.transactions_v2 (user_id, is_in, amount, title, date, status, notes)
  VALUES (v_request.user_id, 0, v_request.amount,
    'مشتريات من ' || (SELECT name FROM badra_core.merchants WHERE id = v_request.merchant_id),
    now(), 'completed', 'order_ref: ' || v_request.order_ref
  ) RETURNING id INTO v_tx_id;

  UPDATE badra_core.payment_requests SET status = 'approved', approved_at = now(), tx_id = v_tx_id WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'transaction_id', v_tx_id,
    'new_balance', v_new_balance, 'old_balance', v_balance, 'amount', v_request.amount);
END;
$$;

-- Drop old 3-param overload if it exists
DROP FUNCTION IF EXISTS badra_core.approve_payment_request_v2(uuid, text, text);

REVOKE ALL ON FUNCTION badra_core.approve_payment_request_v2(uuid, text, text, text) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.approve_payment_request_v2(uuid, text, text, text) TO authenticated;
