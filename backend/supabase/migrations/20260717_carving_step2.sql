-- ============================================================
-- Security Step 2: Challenge Code + Approve v2
-- ============================================================
-- يضيف:
--   1. challenge_code TEXT إلى profiles (bcrypt)
--   2. RPC set_challenge_code — تعيين كود التحدي
--   3. RPC verify_challenge_code — التحقق من كود التحدي
--   4. RPC approve_payment_request_v2 — النسخة الجديدة مع تحقق متعدد العوامل
-- ============================================================

-- 1. Add challenge_code to profiles
ALTER TABLE badra_core.profiles
  ADD COLUMN IF NOT EXISTS challenge_code TEXT DEFAULT '';

-- 2. RPC: set_challenge_code — تعيين كود التحدي
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

  IF length(p_new_code) < 4 THEN
    RETURN jsonb_build_object('success', false, 'error', 'كود التحدي يجب أن يكون 4 أحرف على الأقل');
  END IF;

  UPDATE badra_core.profiles
  SET challenge_code = crypt(p_new_code, gen_salt('bf', 10)),
      updated_at = now()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('success', true);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.set_challenge_code FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.set_challenge_code TO authenticated;

-- 3. RPC: verify_challenge_code — التحقق من كود التحدي
CREATE OR REPLACE FUNCTION badra_core.verify_challenge_code(
  p_code TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_stored TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT challenge_code INTO v_stored
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  IF v_stored IS NULL OR v_stored = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين كود التحدي');
  END IF;

  IF v_stored = crypt(p_code, v_stored) THEN
    RETURN jsonb_build_object('success', true);
  END IF;

  -- Failed attempt — record it for lockout
  INSERT INTO badra_core.challenge_attempts (user_id, attempt_type)
  VALUES (v_user_id, 'challenge_code');

  RETURN jsonb_build_object('success', false, 'error', 'كود التحدي غير صحيح');
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.verify_challenge_code FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.verify_challenge_code TO authenticated;

-- 4. RPC: approve_payment_request_v2 — النسخة الجديدة مع تحكم متعدد العوامل
CREATE OR REPLACE FUNCTION badra_core.approve_payment_request_v2(
  p_request_id UUID,
  p_challenge_code TEXT DEFAULT '',
  p_device_id TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
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
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  -- Check lockout for challenge_code attempts
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id
    AND attempt_type = 'challenge_code'
    AND attempted_at > now() - interval '30 minutes';

  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم قفل كود التحدي مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  -- Fetch request with row lock
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  -- Ownership check
  IF v_request.user_id != v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب لا يخصك');
  END IF;

  -- Status check
  IF v_request.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب لم يعد معلقاً');
  END IF;

  -- Expiration check
  IF v_request.expires_at <= now() THEN
    UPDATE badra_core.payment_requests
    SET status = 'expired'
    WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  -- Device verification: if device_id is provided, check it's carved
  IF p_device_id != '' THEN
    SELECT carved_at INTO v_carved_at
    FROM badra_core.user_devices
    WHERE user_id = v_user_id AND device_id = p_device_id;

    IF v_carved_at IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مسجل. الرجاء تسجيل الدخول من الجهاز المسجل أولاً.');
    END IF;

    -- Update last_login for recognized device
    UPDATE badra_core.user_devices
    SET last_login = now()
    WHERE user_id = v_user_id AND device_id = p_device_id;
  END IF;

  -- Challenge code verification (optional: only if set)
  SELECT challenge_code INTO v_challenge_stored
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  IF v_challenge_stored IS NOT NULL AND v_challenge_stored != '' THEN
    IF p_challenge_code = '' THEN
      RETURN jsonb_build_object('success', false, 'error', 'يجب إدخال كود التحدي');
    END IF;

    IF v_challenge_stored != crypt(p_challenge_code, v_challenge_stored) THEN
      INSERT INTO badra_core.challenge_attempts (user_id, attempt_type)
      VALUES (v_user_id, 'challenge_code');
      RETURN jsonb_build_object('success', false, 'error', 'كود التحدي غير صحيح');
    END IF;

    -- Success — clear attempts
    DELETE FROM badra_core.challenge_attempts
    WHERE user_id = v_user_id AND attempt_type = 'challenge_code';
  END IF;

  -- Lock user's profile and check balance
  SELECT balance INTO v_balance
  FROM badra_core.profiles
  WHERE user_id = v_request.user_id
  FOR UPDATE;

  IF v_balance < v_request.amount THEN
    UPDATE badra_core.payment_requests
    SET status = 'rejected', rejected_at = now()
    WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'الرصيد غير كاف', 'balance', v_balance, 'required', v_request.amount);
  END IF;

  -- Deduct balance
  v_new_balance := v_balance - v_request.amount;
  UPDATE badra_core.profiles
  SET balance = v_new_balance, updated_at = now()
  WHERE user_id = v_request.user_id;

  -- Record transaction
  INSERT INTO badra_core.transactions_v2 (user_id, is_in, amount, title, date, status, notes)
  VALUES (
    v_request.user_id, 0, v_request.amount,
    'مشتريات من ' || (SELECT name FROM badra_core.merchants WHERE id = v_request.merchant_id),
    now(), 'completed',
    'order_ref: ' || v_request.order_ref
  ) RETURNING id INTO v_tx_id;

  -- Mark as approved
  UPDATE badra_core.payment_requests
  SET status = 'approved', approved_at = now(), tx_id = v_tx_id
  WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'transaction_id', v_tx_id,
    'new_balance', v_new_balance, 'old_balance', v_balance,
    'amount', v_request.amount);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.approve_payment_request_v2 FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.approve_payment_request_v2 TO authenticated;
