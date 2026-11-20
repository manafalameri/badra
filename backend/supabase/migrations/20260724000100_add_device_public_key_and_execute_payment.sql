-- ============================================================
-- Add public key columns + missing RPCs for payment approval
-- ============================================================

-- 1. Add public key columns to user_devices
ALTER TABLE badra_core.user_devices
ADD COLUMN IF NOT EXISTS public_key_n TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS public_key_e TEXT DEFAULT '',
ADD COLUMN IF NOT EXISTS key_created_at TIMESTAMPTZ;

-- 2. RPC: get_device_public_key — returns RSA public key components for a device
CREATE OR REPLACE FUNCTION badra_core.get_device_public_key(
  p_user_id UUID,
  p_device_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_device badra_core.user_devices%ROWTYPE;
BEGIN
  SELECT * INTO v_device
  FROM badra_core.user_devices
  WHERE user_id = p_user_id AND device_id = p_device_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير موجود');
  END IF;

  IF v_device.public_key_n IS NULL OR v_device.public_key_n = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'المفتاح العام غير موجود لهذا الجهاز');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'n', v_device.public_key_n,
    'e', v_device.public_key_e
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.get_device_public_key FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.get_device_public_key TO service_role;

-- 3. RPC: execute_approved_payment — atomic balance deduct + tx + status update
CREATE OR REPLACE FUNCTION badra_core.execute_approved_payment(
  p_user_id UUID,
  p_request_id UUID,
  p_amount NUMERIC,
  p_merchant_id UUID,
  p_order_ref TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_request badra_core.payment_requests%ROWTYPE;
  v_merchant_name TEXT;
  v_new_balance NUMERIC;
  v_tx_id UUID;
BEGIN
  -- Lock the payment request row
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_request.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب لم يعد معلقاً');
  END IF;

  IF v_request.expires_at <= now() THEN
    UPDATE badra_core.payment_requests
    SET status = 'expired'
    WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  -- Lock and check user balance
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  IF v_profile.balance < p_amount THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'الرصيد غير كاف',
      'balance', v_profile.balance, 'required', p_amount
    );
  END IF;

  -- Deduct balance
  v_new_balance := v_profile.balance - p_amount;

  UPDATE badra_core.profiles
  SET balance = v_new_balance, updated_at = now()
  WHERE user_id = p_user_id;

  -- Get merchant name
  SELECT name INTO v_merchant_name
  FROM badra_core.merchants
  WHERE id = p_merchant_id;

  -- Create transaction record
  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store
  ) VALUES (
    p_user_id, 0, p_amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed', now(),
    'order_ref: ' || p_order_ref,
    p_order_ref,
    COALESCE(v_merchant_name, '')
  ) RETURNING id INTO v_tx_id;

  -- Update payment request
  UPDATE badra_core.payment_requests
  SET status = 'approved', approved_at = now(), tx_id = v_tx_id
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', v_tx_id,
    'new_balance', v_new_balance,
    'old_balance', v_profile.balance,
    'amount', p_amount
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.execute_approved_payment FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION badra_core.execute_approved_payment TO service_role;
