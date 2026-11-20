-- ============================================================
-- Security & Bug Fixes — 2026-07-16
-- ============================================================
-- إصلاح المشاكل الحرجة + تحسين الأمان
-- ============================================================

-- 1. Add security_code column to profiles
ALTER TABLE badra_core.profiles
ADD COLUMN IF NOT EXISTS security_code TEXT DEFAULT '';

-- 2. Add UNIQUE index on merchants.api_key_prefix
CREATE UNIQUE INDEX IF NOT EXISTS idx_merchants_api_key_prefix
ON badra_core.merchants(api_key_prefix);

-- 3. RPC: check_payment_request_status (service_role only)
CREATE OR REPLACE FUNCTION badra_core.check_payment_request_status(
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
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_request.merchant_id != p_merchant_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب لا يخص متجرك');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', v_request.status,
    'amount', v_request.amount,
    'order_ref', v_request.order_ref,
    'created_at', v_request.created_at,
    'expires_at', v_request.expires_at,
    'approved_at', v_request.approved_at,
    'rejected_at', v_request.rejected_at,
    'tx_id', v_request.tx_id
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.check_payment_request_status FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION badra_core.check_payment_request_status TO service_role;

-- 4. RLS: user_devices — restrict to own devices
ALTER TABLE badra_core.user_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS user_devices_select_own ON badra_core.user_devices;
CREATE POLICY user_devices_select_own ON badra_core.user_devices
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS user_devices_insert_own ON badra_core.user_devices;
CREATE POLICY user_devices_insert_own ON badra_core.user_devices
  FOR INSERT WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS user_devices_update_own ON badra_core.user_devices;
CREATE POLICY user_devices_update_own ON badra_core.user_devices
  FOR UPDATE USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- 5. RLS: deposit_config — admin only read
ALTER TABLE badra_core.deposit_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS deposit_config_admin_only ON badra_core.deposit_config;
CREATE POLICY deposit_config_admin_only ON badra_core.deposit_config
  FOR ALL USING (badra_core.is_admin_uid(auth.uid()));

-- 6. RLS: balance_summary — admin only read
ALTER TABLE badra_core.balance_summary ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS balance_summary_admin_only ON badra_core.balance_summary;
CREATE POLICY balance_summary_admin_only ON badra_core.balance_summary
  FOR SELECT USING (badra_core.is_admin_uid(auth.uid()));
