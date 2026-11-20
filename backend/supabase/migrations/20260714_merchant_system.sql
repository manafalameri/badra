-- ============================================================
-- Merchant System + Payment Requests — 2026-07-14
-- ============================================================
-- المرحلة 1: إنشاء نظام المتاجر وطلبات الدفع
-- ============================================================

-- 1. Merchants table
CREATE TABLE IF NOT EXISTS badra_core.merchants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  api_key_hash TEXT NOT NULL,
  api_key_prefix TEXT NOT NULL,
  webhook_url TEXT DEFAULT '',
  webhook_secret TEXT DEFAULT '',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE badra_core.merchants ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_only_merchants ON badra_core.merchants;
CREATE POLICY admin_only_merchants ON badra_core.merchants
  FOR ALL USING (badra_core.is_admin_uid(auth.uid()));

-- 2. Payment requests table
CREATE TABLE IF NOT EXISTS badra_core.payment_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  merchant_id UUID NOT NULL REFERENCES badra_core.merchants(id),
  user_id UUID NOT NULL REFERENCES badra_core.profiles(user_id),
  amount NUMERIC NOT NULL CHECK (amount > 0),
  order_ref TEXT NOT NULL,
  items JSONB DEFAULT '[]'::jsonb,
  status TEXT DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected','expired')),
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  approved_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  tx_id UUID,
  UNIQUE(merchant_id, order_ref)
);
ALTER TABLE badra_core.payment_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS select_own_payment_requests ON badra_core.payment_requests;
CREATE POLICY select_own_payment_requests ON badra_core.payment_requests
  FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS update_own_pending_requests ON badra_core.payment_requests;
CREATE POLICY update_own_pending_requests ON badra_core.payment_requests
  FOR UPDATE USING (user_id = auth.uid() AND status = 'pending')
  WITH CHECK (user_id = auth.uid() AND status IN ('approved','rejected'));

-- Indexes
CREATE INDEX IF NOT EXISTS idx_payment_requests_user_id ON badra_core.payment_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_payment_requests_merchant_id ON badra_core.payment_requests(merchant_id);
CREATE INDEX IF NOT EXISTS idx_payment_requests_status ON badra_core.payment_requests(status);
CREATE INDEX IF NOT EXISTS idx_payment_requests_expires ON badra_core.payment_requests(expires_at);

-- 3. Add fcm_token to user_devices
ALTER TABLE badra_core.user_devices
ADD COLUMN IF NOT EXISTS fcm_token TEXT DEFAULT '';

-- ============================================================
-- RPC: create_payment_request  (service_role only via Edge Function)
-- ============================================================
CREATE OR REPLACE FUNCTION badra_core.create_payment_request(
  p_merchant_id UUID,
  p_user_phone TEXT,
  p_security_code TEXT,
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
BEGIN
  SELECT * INTO v_merchant
  FROM badra_core.merchants
  WHERE id = p_merchant_id AND is_active = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المتجر غير موجود أو غير نشط');
  END IF;

  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE phone = p_user_phone AND is_active = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود أو الحساب غير نشط');
  END IF;

  IF v_profile.security_code IS NULL OR v_profile.security_code = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين كود الأمان');
  END IF;

  IF NOT (
    v_profile.security_code = p_security_code
    OR
    v_profile.security_code = crypt(p_security_code, v_profile.security_code)
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'كود الأمان غير صحيح');
  END IF;

  IF v_profile.balance < p_amount THEN
    RETURN jsonb_build_object('success', false, 'error', 'الرصيد غير كاف', 'balance', v_profile.balance, 'required', p_amount);
  END IF;

  IF EXISTS (
    SELECT 1 FROM badra_core.payment_requests
    WHERE merchant_id = p_merchant_id AND order_ref = p_order_ref
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب موجود مسبقاً');
  END IF;

  IF (
    SELECT COUNT(*) FROM badra_core.payment_requests
    WHERE user_id = v_profile.user_id AND status = 'pending' AND expires_at > now()
  ) >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'لديك طلبات معلقة كثيرة');
  END IF;

  INSERT INTO badra_core.payment_requests (
    merchant_id, user_id, amount, order_ref, items, status, expires_at
  ) VALUES (
    p_merchant_id, v_profile.user_id, p_amount, p_order_ref, p_items,
    'pending', now() + interval '2 minutes'
  ) RETURNING id INTO v_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_request_id,
    'status', 'pending',
    'expires_in_seconds', 120
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.create_payment_request FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION badra_core.create_payment_request TO service_role;

-- ============================================================
-- RPC: approve_payment_request  (authenticated user)
-- ============================================================
CREATE OR REPLACE FUNCTION badra_core.approve_payment_request(
  p_request_id UUID
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_request badra_core.payment_requests%ROWTYPE;
  v_balance NUMERIC;
  v_new_balance NUMERIC;
  v_tx_id UUID;
BEGIN
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_request.user_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب لا يخصك');
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

  v_new_balance := v_balance - v_request.amount;

  UPDATE badra_core.profiles
  SET balance = v_new_balance, updated_at = now()
  WHERE user_id = v_request.user_id;

  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, date, status, notes
  ) VALUES (
    v_request.user_id, 0, v_request.amount,
    'مشتريات من ' || (SELECT name FROM badra_core.merchants WHERE id = v_request.merchant_id),
    now(), 'completed',
    'order_ref: ' || v_request.order_ref
  ) RETURNING id INTO v_tx_id;

  UPDATE badra_core.payment_requests
  SET status = 'approved', approved_at = now(), tx_id = v_tx_id
  WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'transaction_id', v_tx_id, 'new_balance', v_new_balance, 'old_balance', v_balance, 'amount', v_request.amount);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.approve_payment_request FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.approve_payment_request TO authenticated;

-- ============================================================
-- RPC: reject_payment_request  (authenticated user)
-- ============================================================
CREATE OR REPLACE FUNCTION badra_core.reject_payment_request(
  p_request_id UUID
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
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_request.user_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب لا يخصك');
  END IF;

  IF v_request.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب لم يعد معلقاً');
  END IF;

  UPDATE badra_core.payment_requests
  SET status = 'rejected', rejected_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'message', 'تم رفض الطلب');
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.reject_payment_request FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.reject_payment_request TO authenticated;

-- ============================================================
-- RPC: get_my_pending_requests  (authenticated user)
-- ============================================================
CREATE OR REPLACE FUNCTION badra_core.get_my_pending_requests()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', pr.id,
      'merchant_name', m.name,
      'amount', pr.amount,
      'order_ref', pr.order_ref,
      'items', pr.items,
      'expires_at', pr.expires_at,
      'created_at', pr.created_at,
      'expires_in_seconds', extract(epoch from (pr.expires_at - now()))
    ) ORDER BY pr.created_at DESC
  ), '[]'::jsonb) INTO v_result
  FROM badra_core.payment_requests pr
  JOIN badra_core.merchants m ON m.id = pr.merchant_id
  WHERE pr.user_id = auth.uid()
    AND pr.status = 'pending'
    AND pr.expires_at > now();

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.get_my_pending_requests FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.get_my_pending_requests TO authenticated;

-- ============================================================
-- Admin RPCs
-- ============================================================

CREATE OR REPLACE FUNCTION badra_core.admin_create_merchant(
  p_name TEXT,
  p_webhook_url TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_merchant_id UUID;
  v_raw_key TEXT;
  v_hashed TEXT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  v_raw_key := 'bd_mch_' || encode(gen_random_bytes(16), 'hex');
  v_hashed := crypt(v_raw_key, gen_salt('bf', 10));

  INSERT INTO badra_core.merchants (name, api_key_hash, api_key_prefix, webhook_url)
  VALUES (p_name, v_hashed, left(v_raw_key, 16), p_webhook_url)
  RETURNING id INTO v_merchant_id;

  RETURN jsonb_build_object('success', true, 'merchant_id', v_merchant_id, 'name', p_name, 'api_key', v_raw_key, 'warning', 'احتفظ بهذا المفتاح. لن يظهر مرة أخرى.');
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.admin_create_merchant FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION badra_core.admin_create_merchant TO authenticated;

CREATE OR REPLACE FUNCTION badra_core.admin_list_merchants()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id,
      'name', m.name,
      'api_key_prefix', m.api_key_prefix,
      'webhook_url', m.webhook_url,
      'is_active', m.is_active,
      'created_at', m.created_at
    ) ORDER BY m.created_at DESC
  ), '[]'::jsonb) INTO v_result
  FROM badra_core.merchants m;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.admin_list_merchants FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.admin_list_merchants TO authenticated;

CREATE OR REPLACE FUNCTION badra_core.admin_toggle_merchant(
  p_merchant_id UUID,
  p_is_active BOOLEAN
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  UPDATE badra_core.merchants
  SET is_active = p_is_active
  WHERE id = p_merchant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المتجر غير موجود');
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'تم تحديث الحالة');
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.admin_toggle_merchant FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.admin_toggle_merchant TO authenticated;
