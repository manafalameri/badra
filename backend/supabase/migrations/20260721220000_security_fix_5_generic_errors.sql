-- =============================================================================
-- SECURITY FIX 5: Hide sensitive error details in create_payment_request (H3)
-- =============================================================================
-- Vulnerability: create_payment_request returned distinct error messages that
-- allowed user enumeration (phone exists?), setup probing (PIN set?), and
-- EXACT BALANCE disclosure ('balance', v_profile.balance, 'required', p_amount).
-- With a leaked merchant key, anyone could enumerate phones and read balances.
--
-- Fix: All user-related failures return ONE generic error message.
-- Merchant-specific errors (merchant inactive, duplicate order_ref) are kept
-- since the merchant already knows their own data.
-- =============================================================================

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
SET search_path TO 'badra_core', 'public'
AS $function$
DECLARE
  v_merchant badra_core.merchants%ROWTYPE;
  v_profile badra_core.profiles%ROWTYPE;
  v_request_id UUID;
  -- Generic error for all user-related failures (no enumeration/oracle)
  c_user_error CONSTANT TEXT := 'تعذر إنشاء الطلب. تحقق من بيانات المستخدم';
BEGIN
  -- Merchant check: merchant knows their own ID, safe to be specific
  SELECT * INTO v_merchant FROM badra_core.merchants WHERE id = p_merchant_id AND is_active = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المتجر غير موجود أو غير نشط');
  END IF;

  -- User check: GENERIC error (was: 'المستخدم غير موجود أو الحساب غير نشط')
  SELECT * INTO v_profile FROM badra_core.profiles WHERE phone = p_user_phone AND is_active = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  -- Security code check: GENERIC error (was: revealed PIN setup status)
  IF v_profile.security_code IS NULL OR v_profile.security_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  -- Challenge code check: GENERIC error (mandatory now, must be set)
  IF v_profile.challenge_code IS NULL OR v_profile.challenge_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  -- Balance check: GENERIC error (was: leaked EXACT balance + required amount)
  IF v_profile.balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  -- Duplicate order_ref: merchant's own data, safe to be specific
  IF EXISTS (SELECT 1 FROM badra_core.payment_requests WHERE merchant_id = p_merchant_id AND order_ref = p_order_ref) THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب موجود مسبقاً');
  END IF;

  -- Pending limit: generic (doesn't leak balance, but merchant can retry later)
  IF (SELECT COUNT(*) FROM badra_core.payment_requests WHERE user_id = v_profile.user_id AND status = 'pending' AND expires_at > now()) >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  INSERT INTO badra_core.payment_requests (merchant_id, user_id, amount, order_ref, items, status, expires_at)
  VALUES (p_merchant_id, v_profile.user_id, p_amount, p_order_ref, p_items, 'pending', now() + interval '2 minutes')
  RETURNING id INTO v_request_id;

  RETURN jsonb_build_object('success', true, 'request_id', v_request_id, 'status', 'pending', 'expires_in_seconds', 120);
END;
$function$;

COMMENT ON FUNCTION badra_core.create_payment_request IS
  'SECURITY: Generic error messages prevent user enumeration and balance disclosure.';
