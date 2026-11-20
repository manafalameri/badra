-- ============================================================
-- Security, RLS & Missing Objects Fix — 2026-07-10
-- ============================================================

-- ============================================================
-- PART A: Missing Tables & Columns
-- ============================================================

-- 1. Add admin_name column to deposit_requests (if not exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'badra_core' AND table_name = 'deposit_requests' AND column_name = 'admin_name'
  ) THEN
    ALTER TABLE badra_core.deposit_requests ADD COLUMN admin_name TEXT DEFAULT '';
  END IF;
END $$;

-- 2. Add deposit_request_id column to transactions_v2 (if not exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'badra_core' AND table_name = 'transactions_v2' AND column_name = 'deposit_request_id'
  ) THEN
    ALTER TABLE badra_core.transactions_v2 ADD COLUMN deposit_request_id UUID;
  END IF;
END $$;

-- 3. Create audit_log table (if not exists)
CREATE TABLE IF NOT EXISTS badra_core.audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    action TEXT NOT NULL,
    table_name TEXT NOT NULL,
    record_id UUID,
    old_values JSONB DEFAULT '{}'::jsonb,
    new_values JSONB DEFAULT '{}'::jsonb,
    admin_id UUID,
    admin_name TEXT DEFAULT '',
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

ALTER TABLE badra_core.audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY admin_only_audit_log ON badra_core.audit_log
    FOR ALL USING (badra_core.is_admin_uid(auth.uid()));

-- ============================================================
-- PART B: New RPC Functions
-- ============================================================

-- 1. admin_get_pending_user_by_phone: Fetch single pending user (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_get_pending_user_by_phone(
  p_phone TEXT
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '{"success":false,"message":"غير مصرح"}';
  END IF;

  SELECT jsonb_build_object(
    'success', true,
    'name', pu.name,
    'phone', pu.phone,
    'password_hash', pu.password_hash,
    'ip', pu.ip,
    'device_name', pu.device_name,
    'device_id', pu.device_id,
    'status', pu.status,
    'created_at', pu.created_at
  )
  INTO v_result
  FROM badra_core.pending_users pu
  WHERE pu.phone = p_phone
    AND pu.status = 'pending'
  LIMIT 1;

  IF v_result IS NULL THEN
    RETURN '{"success":false,"message":"المستخدم المعلق غير موجود"}';
  END IF;

  RETURN v_result::TEXT;
END;
$$;

-- 2. admin_approve_pending_user: Update status to approved (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_approve_pending_user(
  p_phone TEXT
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_updated INT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '{"success":false,"message":"غير مصرح"}';
  END IF;

  UPDATE badra_core.pending_users
  SET status = 'approved', updated_at = now()
  WHERE phone = p_phone
    AND status = 'pending';

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RETURN '{"success":false,"message":"لم يتم العثور على طلب معلق بهذا الرقم"}';
  END IF;

  RETURN '{"success":true,"message":"تمت الموافقة بنجاح"}';
END;
$$;

-- 3. admin_verify_device: Verify and store admin device (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_verify_device(
  p_device_id TEXT,
  p_device_name TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_admin_id UUID;
  v_exists BOOLEAN;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح: أنت لست أدمن');
  END IF;

  -- Check if device already registered for this admin
  SELECT EXISTS (
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = v_admin_id AND device_id = p_device_id
  ) INTO v_exists;

  IF v_exists THEN
    -- Update last_login
    UPDATE badra_core.user_devices
    SET last_login = now(), device_name = p_device_name
    WHERE user_id = v_admin_id AND device_id = p_device_id;
    RETURN jsonb_build_object('success', true, 'message', 'تم التحقق من الجهاز');
  END IF;

  -- First device for this admin — register it
  INSERT INTO badra_core.user_devices (user_id, device_id, device_name, last_login)
  VALUES (v_admin_id, p_device_id, p_device_name, now());

  RETURN jsonb_build_object('success', true, 'message', 'تم تسجيل الجهاز بنجاح');
END;
$$;

-- 4. admin_count_active_users: Count active users (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_count_active_users()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN 0;
  END IF;
  SELECT COUNT(*) INTO v_count
  FROM badra_core.profiles
  WHERE is_active = true;
  RETURN v_count;
END;
$$;

-- 5. admin_get_total_balance: Sum of all wallet balances (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_get_total_balance()
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN 0;
  END IF;
  RETURN COALESCE((SELECT SUM(balance) FROM badra_core.profiles), 0);
END;
$$;

-- 6. admin_get_last_transactions: Last N transactions (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_get_last_transactions(
  p_limit INTEGER DEFAULT 5
) RETURNS JSONB
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

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'user_id', t.user_id,
      'debtor', t.debtor,
      'creditor', t.creditor,
      'amount', t.amount,
      'date', t.date,
      'status', t.status,
      'title', t.title,
      'notes', t.notes
    ) ORDER BY t.date DESC
  ) INTO v_result
  FROM badra_core.transactions_v2 t
  LIMIT p_limit;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 7. admin_get_trading_volume: Total trading volume (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_get_trading_volume()
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN 0;
  END IF;
  RETURN COALESCE((SELECT SUM(amount) FROM badra_core.transactions_v2), 0);
END;
$$;

-- 8. Rewrite admin_manual_deposit with correct columns
CREATE OR REPLACE FUNCTION badra_core.admin_manual_deposit(
    p_wallet_id TEXT,
    p_phone TEXT,
    p_name TEXT,
    p_amount NUMERIC,
    p_bank_name TEXT,
    p_receipt_number TEXT DEFAULT '',
    p_notes TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_admin_id UUID;
    v_profile_id UUID;
    v_user_id UUID;
    v_old_balance NUMERIC;
    v_admin_name TEXT;
    v_deposit_id UUID;
    v_tx_id UUID;
BEGIN
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN RAISE EXCEPTION 'غير مصرح'; END IF;
    IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN RAISE EXCEPTION 'غير مصرح: لست أدمن'; END IF;
    IF p_amount < 500 THEN RAISE EXCEPTION 'الحد الأدنى 500 ريال';
    ELSIF p_amount > 250000 THEN RAISE EXCEPTION 'الحد الأقصى 250,000 ريال'; END IF;
    IF p_bank_name NOT IN ('العمقي','الكرايمي','القطيبي','البسيري') THEN RAISE EXCEPTION 'بنك غير صحيح'; END IF;

    SELECT name INTO v_admin_name FROM badra_core.profiles WHERE user_id = v_admin_id LIMIT 1;
    IF v_admin_name IS NULL THEN v_admin_name := 'أدمن'; END IF;

    SELECT id, user_id, balance INTO v_profile_id, v_user_id, v_old_balance
    FROM badra_core.profiles
    WHERE wallet_id = p_wallet_id AND phone = p_phone AND name = p_name
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'المستخدم غير موجود'; END IF;

    UPDATE badra_core.profiles SET balance = balance + p_amount, updated_at = now()
    WHERE id = v_profile_id;

    INSERT INTO badra_core.deposit_requests(user_id,amount,bank_name,receipt_number,notes,admin_id,admin_name)
    VALUES(v_user_id,p_amount,p_bank_name,NULLIF(p_receipt_number,''),NULLIF(p_notes,''),v_admin_id,v_admin_name)
    RETURNING id INTO v_deposit_id;

    INSERT INTO badra_core.transactions_v2(user_id,is_in,amount,title,date,status,notes,deposit_request_id)
    VALUES(v_user_id,1,p_amount,'إيداع عبر الأدمن - '||p_bank_name,now(),'completed',NULLIF(p_notes,''),v_deposit_id)
    RETURNING id INTO v_tx_id;

    UPDATE badra_core.balance_summary
    SET total_received = total_received + p_amount, updated_at = now()
    WHERE id = (SELECT id FROM badra_core.balance_summary LIMIT 1);

    INSERT INTO badra_core.audit_log(action,table_name,record_id,old_values,new_values,admin_id,admin_name)
    VALUES('deposit','profiles',v_profile_id,
           jsonb_build_object('balance',v_old_balance),
           jsonb_build_object('balance',v_old_balance+p_amount,'deposit_id',v_deposit_id,'transaction_id',v_tx_id,'amount',p_amount,'bank',p_bank_name),
           v_admin_id,v_admin_name);

    RETURN jsonb_build_object('success',true,'amount',p_amount,'user_id',v_user_id,'old_balance',v_old_balance,'new_balance',v_old_balance+p_amount,'deposit_id',v_deposit_id,'transaction_id',v_tx_id);
END;
$$;

-- ============================================================
-- PART C: RLS Helper Function
-- ============================================================

CREATE OR REPLACE FUNCTION badra_core.is_admin_uid(uid UUID)
RETURNS BOOLEAN AS $$
  SELECT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = uid);
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================================
-- PART D: RLS Policies
-- ============================================================

-- Remove overly permissive policies
DROP POLICY IF EXISTS service_pending_users ON badra_core.pending_users;
DROP POLICY IF EXISTS service_activation_codes ON badra_core.activation_codes;

-- Admin-only policies (defense in depth — RPCs already enforce admin check)
CREATE POLICY admin_only_pending_users ON badra_core.pending_users
  FOR ALL USING (badra_core.is_admin_uid(auth.uid()));

CREATE POLICY admin_only_activation_codes ON badra_core.activation_codes
  FOR ALL USING (badra_core.is_admin_uid(auth.uid()));

-- ============================================================
-- PART E: REVOKE from anon/public for security
-- ============================================================

REVOKE EXECUTE ON FUNCTION badra_core.admin_verify_device(text,text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION badra_core.admin_count_active_users() FROM anon, public;
REVOKE EXECUTE ON FUNCTION badra_core.admin_get_total_balance() FROM anon, public;
REVOKE EXECUTE ON FUNCTION badra_core.admin_get_last_transactions(integer) FROM anon, public;
REVOKE EXECUTE ON FUNCTION badra_core.admin_get_trading_volume() FROM anon, public;
REVOKE EXECUTE ON FUNCTION badra_core.admin_get_pending_user_by_phone(text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION badra_core.admin_approve_pending_user(text) FROM anon, public;
