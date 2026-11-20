-- =============================================================================
-- SECURITY FIX 6: Migrate plaintext PINs to bcrypt + remove plaintext fallback (H7)
-- =============================================================================
-- Vulnerability: 24 profiles had security_code stored in PLAINTEXT. The approve
-- function had a plaintext equality fallback branch keeping them vulnerable
-- indefinitely. Any DB leak (backup, insider) would expose real PINs.
--
-- Fix:
--   1. One-time migration: hash all plaintext security_codes with bcrypt
--   2. Remove the plaintext fallback branch from approve_payment_request_v2
-- =============================================================================

-- Step 1: Migrate all plaintext PINs to bcrypt (cost 10)
-- Only touches rows where security_code is set and NOT already a bcrypt hash
UPDATE badra_core.profiles
SET security_code = crypt(security_code, gen_salt('bf', 10)),
    updated_at = now()
WHERE security_code IS NOT NULL
  AND security_code != ''
  AND security_code NOT LIKE '$2%';

-- Step 2: Recreate approve_payment_request_v2 WITHOUT the plaintext fallback
CREATE OR REPLACE FUNCTION badra_core.approve_payment_request_v2(
  p_request_id UUID,
  p_challenge_code TEXT DEFAULT '',
  p_device_id TEXT DEFAULT '',
  p_security_code TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_request RECORD;
  v_attempt_count INT;
  v_challenge_stored TEXT;
  v_pin_stored TEXT;
  v_device_record RECORD;
  v_balance NUMERIC;
  v_tx_id UUID;
  v_merchant_name TEXT;
BEGIN
  -- 1. Verify caller is authenticated
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  -- 2. Check lockout for challenge code (max 5 attempts in 30 min)
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = 'challenge_code'
    AND attempted_at > now() - interval '30 minutes';
  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم قفل كود التحدي مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  -- 3. Check lockout for security code PIN (max 5 attempts in 30 min)
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = 'security_code'
    AND attempted_at > now() - interval '30 minutes';
  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم قفل الرقم السري مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  -- 4. Fetch the payment request with row lock
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_request IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'طلب الدفع غير موجود');
  END IF;

  -- 5. Verify ownership
  IF v_request.user_id != v_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بهذا الطلب');
  END IF;

  -- 6. Verify status is pending
  IF v_request.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب تم معالجته مسبقاً');
  END IF;

  -- 7. Verify not expired
  IF v_request.expires_at < now() THEN
    UPDATE badra_core.payment_requests SET status = 'expired' WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  -- 8. MANDATORY: Device verification
  IF p_device_id = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'معرف الجهاز مطلوب');
  END IF;

  SELECT * INTO v_device_record
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND device_id = p_device_id;

  IF v_device_record IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مسجل. يرجى تسجيل الدخول من جهازك');
  END IF;

  -- 9. MANDATORY: Challenge code verification
  SELECT challenge_code INTO v_challenge_stored
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  IF v_challenge_stored IS NULL OR v_challenge_stored = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين كود التحدي. يرجى إعداده أولاً من الإعدادات');
  END IF;

  IF p_challenge_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'كود التحدي إجباري');
  END IF;

  IF v_challenge_stored != crypt(p_challenge_code, v_challenge_stored) THEN
    INSERT INTO badra_core.challenge_attempts (user_id, attempt_type)
    VALUES (v_user_id, 'challenge_code');
    RETURN jsonb_build_object('success', false, 'error', 'كود التحدي غير صحيح');
  END IF;

  DELETE FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = 'challenge_code';

  -- 10. MANDATORY: Security code (PIN) verification — bcrypt ONLY (no plaintext fallback)
  SELECT security_code INTO v_pin_stored
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  IF v_pin_stored IS NULL OR v_pin_stored = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين الرقم السري');
  END IF;

  IF p_security_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الرقم السري إجباري');
  END IF;

  -- All PINs are now bcrypt (migrated above). If somehow not bcrypt, reject.
  IF v_pin_stored NOT LIKE '$2%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'يجب إعادة تعيين الرقم السري من الإعدادات');
  END IF;

  IF v_pin_stored != crypt(p_security_code, v_pin_stored) THEN
    INSERT INTO badra_core.challenge_attempts (user_id, attempt_type)
    VALUES (v_user_id, 'security_code');
    RETURN jsonb_build_object('success', false, 'error', 'الرقم السري غير صحيح');
  END IF;

  DELETE FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = 'security_code';

  -- 11. Verify sufficient balance (with row lock)
  SELECT balance INTO v_balance
  FROM badra_core.profiles
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_balance < v_request.amount THEN
    RETURN jsonb_build_object('success', false, 'error', 'رصيد غير كافي');
  END IF;

  -- 12. Deduct balance
  UPDATE badra_core.profiles
  SET balance = balance - v_request.amount,
      updated_at = now()
  WHERE user_id = v_user_id;

  -- 13. Get merchant name for transaction description
  SELECT name INTO v_merchant_name
  FROM badra_core.merchants
  WHERE id = v_request.merchant_id;

  -- 14. Create transaction record
  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store
  ) VALUES (
    v_user_id,
    0,
    v_request.amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed',
    now(),
    'order_ref: ' || v_request.order_ref,
    v_request.order_ref,
    COALESCE(v_merchant_name, '')
  )
  RETURNING id INTO v_tx_id;

  -- 15. Update payment request status
  UPDATE badra_core.payment_requests
  SET status = 'approved',
      approved_at = now(),
      tx_id = v_tx_id
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', v_tx_id,
    'new_balance', v_balance - v_request.amount,
    'old_balance', v_balance,
    'amount', v_request.amount
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.approve_payment_request_v2(UUID, TEXT, TEXT, TEXT) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.approve_payment_request_v2(UUID, TEXT, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION badra_core.approve_payment_request_v2 IS
  'SECURITY: bcrypt-only PIN verification. Plaintext fallback removed.';
