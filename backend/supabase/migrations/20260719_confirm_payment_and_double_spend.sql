-- ============================================================
-- Confirm Payment + Double-Spend Protection — 2026-07-19
-- ============================================================
-- 1. Add `used` column to payment_requests
-- 2. Create confirm_payment_request RPC (idempotent, row-locked)
-- 3. Grant service_role only
-- ============================================================

-- 1. Add `used` column
ALTER TABLE badra_core.payment_requests
ADD COLUMN IF NOT EXISTS used BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_payment_requests_used
ON badra_core.payment_requests(used) WHERE used = false;

-- 2. confirm_payment_request RPC
CREATE OR REPLACE FUNCTION badra_core.confirm_payment_request(
  p_request_id UUID,
  p_merchant_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_request badra_core.payment_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
    AND merchant_id = p_merchant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'طلب الدفع غير موجود أو لا يخص هذا المتجر'
    );
  END IF;

  IF v_request.used THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'تم تأكيد هذا الطلب مسبقاً'
    );
  END IF;

  IF v_request.status != 'approved' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'الطلبلم يتم الموافقة عليه بعد',
      'status', v_request.status
    );
  END IF;

  UPDATE badra_core.payment_requests
  SET used = true
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_request.id,
    'amount', v_request.amount,
    'order_ref', v_request.order_ref,
    'status', 'approved',
    'tx_id', v_request.tx_id,
    'approved_at', v_request.approved_at
  );
END;
$$;

-- 3. Security: only service_role (edge functions) can call this
REVOKE ALL ON FUNCTION badra_core.confirm_payment_request(UUID, UUID) FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION badra_core.confirm_payment_request(UUID, UUID) TO service_role;
