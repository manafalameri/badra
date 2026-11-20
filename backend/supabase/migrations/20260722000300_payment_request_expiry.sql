-- Increase payment request expiration to 10 minutes for better UX
CREATE OR REPLACE FUNCTION badra_core.create_payment_request(
  p_merchant_id UUID,
  p_user_phone TEXT,
  p_amount NUMERIC,
  p_order_ref TEXT,
  p_items JSONB DEFAULT '[]'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_merchant badra_core.merchants%ROWTYPE;
  v_profile badra_core.profiles%ROWTYPE;
  v_request_id UUID;
  c_user_error CONSTANT TEXT := 'تعذر إنشاء الطلب. تحقق من بيانات المستخدم';
  c_expiry_seconds CONSTANT INT := 600;
BEGIN
  SELECT * INTO v_merchant FROM badra_core.merchants WHERE id = p_merchant_id AND is_active = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المتجر غير موجود أو غير نشط');
  END IF;

  SELECT * INTO v_profile FROM badra_core.profiles WHERE phone = p_user_phone AND is_active = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  IF v_profile.security_code IS NULL OR v_profile.security_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', c_user_error);
  END IF;

  IF v_profile.challenge_code IS NULL OR v_profile.challenge_code = '' THEN
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
  VALUES (p_merchant_id, v_profile.user_id, p_amount, p_order_ref, p_items, 'pending', now() + (c_expiry_seconds || ' seconds')::interval)
  RETURNING id INTO v_request_id;

  RETURN jsonb_build_object('success', true, 'request_id', v_request_id, 'status', 'pending', 'expires_in_seconds', c_expiry_seconds);
END;
$$;

SELECT 'payment request expiry increased to 600 seconds' AS status;
