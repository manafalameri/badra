-- ============================================================
-- بذرة (Badra) — Full Database Recreation Script
-- Run this in your NEW Supabase project SQL Editor
-- ============================================================

-- 1. Create schema
CREATE SCHEMA IF NOT EXISTS badra_core;

-- 2. Profiles table (used by get_my_profile RPC)
CREATE TABLE IF NOT EXISTS badra_core.profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  phone TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  wallet_id TEXT UNIQUE NOT NULL DEFAULT '',
  balance NUMERIC DEFAULT 0 NOT NULL,
  is_active BOOLEAN DEFAULT false NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 3. Pending users (used by create_pending_user RPC)
CREATE TABLE IF NOT EXISTS badra_core.pending_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  phone TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL,
  ip TEXT DEFAULT '',
  device_name TEXT DEFAULT '',
  device_id TEXT DEFAULT '',
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  activation_code TEXT,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 3b. Activation codes (for user account activation)
CREATE TABLE IF NOT EXISTS badra_core.activation_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT NOT NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  used BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT now() + interval '90 minutes',
  failed_attempts INTEGER DEFAULT 0
);

-- 4. Bank accounts for deposits
CREATE TABLE IF NOT EXISTS badra_core.bank_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  bank_name TEXT NOT NULL,
  account_number_encrypted TEXT NOT NULL,
  account_holder_name TEXT DEFAULT '',
  is_default BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 5. Transactions (legacy)
CREATE TABLE IF NOT EXISTS badra_core.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  description TEXT DEFAULT '',
  amount NUMERIC NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('incoming', 'outgoing', 'service')),
  status TEXT DEFAULT 'completed' CHECK (status IN ('completed', 'pending', 'failed')),
  sender_phone TEXT DEFAULT '',
  recipient_phone TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 6. Transactions v2 (newer format with date field)
CREATE TABLE IF NOT EXISTS badra_core.transactions_v2 (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES badra_core.profiles(user_id) ON DELETE CASCADE,
  is_in INTEGER DEFAULT 0 CHECK (is_in IN (0, 1)),
  ref TEXT DEFAULT '',
  store TEXT DEFAULT '',
  title TEXT DEFAULT '',
  amount NUMERIC NOT NULL,
  date TIMESTAMPTZ NOT NULL,
  status TEXT DEFAULT 'completed',
  debtor TEXT DEFAULT '',
  creditor TEXT DEFAULT '',
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 7. Deposit configuration (bank details for users to deposit into)
CREATE TABLE IF NOT EXISTS badra_core.deposit_config (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  bank1 TEXT DEFAULT '',
  bank2 TEXT DEFAULT '',
  bank3 TEXT DEFAULT '',
  bank4 TEXT DEFAULT '',
  account_holder_name TEXT DEFAULT '',
  is_active BOOLEAN DEFAULT true,
  updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 8. User devices/sessions tracking (optional metadata)
CREATE TABLE IF NOT EXISTS badra_core.user_devices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_name TEXT DEFAULT '',
  device_id TEXT DEFAULT '',
  ip TEXT DEFAULT '',
  last_login TIMESTAMPTZ DEFAULT now() NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- ============================================================
-- INDEXES
-- ============================================================
CREATE INDEX IF NOT EXISTS idx_profiles_user_id ON badra_core.profiles(user_id);
CREATE INDEX IF NOT EXISTS idx_profiles_phone ON badra_core.profiles(phone);
CREATE INDEX IF NOT EXISTS idx_pending_users_phone ON badra_core.pending_users(phone);
CREATE INDEX IF NOT EXISTS idx_pending_users_status ON badra_core.pending_users(status);
CREATE INDEX IF NOT EXISTS idx_bank_accounts_user_id ON badra_core.bank_accounts(user_id);
CREATE INDEX IF NOT EXISTS idx_bank_accounts_is_default ON badra_core.bank_accounts(is_default);
CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON badra_core.transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_created_at ON badra_core.transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_transactions_v2_user_id ON badra_core.transactions_v2(user_id);
CREATE INDEX IF NOT EXISTS idx_transactions_v2_date ON badra_core.transactions_v2(date);
CREATE INDEX IF NOT EXISTS idx_activation_codes_phone ON badra_core.activation_codes(phone);
CREATE INDEX IF NOT EXISTS idx_activation_codes_user_id ON badra_core.activation_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_activation_codes_expires ON badra_core.activation_codes(expires_at);

-- ============================================================
-- RPC FUNCTIONS
-- ============================================================

-- 1. create_pending_user: Register a new user in pending queue
CREATE OR REPLACE FUNCTION badra_core.create_pending_user(
  p_name TEXT,
  p_phone TEXT,
  p_password TEXT,
  p_ip TEXT DEFAULT '',
  p_device_name TEXT DEFAULT '',
  p_device_id TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_existing_user_id UUID;
  v_pending_id UUID;
  v_activation_code TEXT;
BEGIN
  -- Check if phone already exists in auth.users
  SELECT id INTO v_existing_user_id
  FROM auth.users
  WHERE phone = p_phone
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'رقم الهاتف مستخدم بالفعل'
    );
  END IF;

  -- Generate activation code
  v_activation_code := upper(substr(md5(random()::text), 1, 6));

  -- Insert into pending_users
  INSERT INTO badra_core.pending_users (
    name, phone, password_hash, ip, device_name, device_id, status, activation_code
  ) VALUES (
    p_name, p_phone, p_password, p_ip, p_device_name, p_device_id, 'pending', v_activation_code
  )
  RETURNING id INTO v_pending_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم إرسال طلبك. انتظر موافقة الأدمن.',
    'pending_id', v_pending_id
  );
END;
$$;

-- 2. activate_user: Activate user account using activation_codes table
CREATE OR REPLACE FUNCTION badra_core.activate_user(
  p_phone TEXT,
  p_code TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_code_record badra_core.activation_codes%ROWTYPE;
  v_user_id UUID;
  v_phone_clean TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'يجب تسجيل الدخول أولاً');
  END IF;

  v_phone_clean := replace(p_phone, '+', '');

  -- Find valid unused code
  SELECT * INTO v_code_record
  FROM badra_core.activation_codes
  WHERE phone = v_phone_clean
    AND used = false
    AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'كود التفعيل غير صحيح أو منتهي الصلاحية');
  END IF;

  -- Code belongs to this user?
  IF v_code_record.user_id != v_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'هذا الكود لا يخص حسابك');
  END IF;

  -- Already active?
  IF EXISTS (SELECT 1 FROM badra_core.profiles WHERE user_id = v_user_id AND is_active = true) THEN
    RETURN jsonb_build_object('success', false, 'message', 'الحساب مفعل بالفعل');
  END IF;

  -- Wrong code? increment failed attempts
  IF v_code_record.code != p_code THEN
    UPDATE badra_core.activation_codes
    SET failed_attempts = failed_attempts + 1
    WHERE id = v_code_record.id;

    UPDATE badra_core.activation_codes
    SET expires_at = now()
    WHERE id = v_code_record.id AND failed_attempts >= 5;

    RETURN jsonb_build_object('success', false, 'message', 'كود التفعيل غير صحيح');
  END IF;

  -- Activate profile first
  UPDATE badra_core.profiles
  SET is_active = true, updated_at = now()
  WHERE user_id = v_user_id;

  -- Then delete the code (no traces, no reuse)
  DELETE FROM badra_core.activation_codes
  WHERE id = v_code_record.id;

  RETURN jsonb_build_object('success', true, 'message', 'تم تفعيل الحساب بنجاح');
END;
$$;

-- 2b. is_admin: Check if current user has admin role
CREATE OR REPLACE FUNCTION badra_core.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM badra_core.admins
    WHERE user_id = auth.uid()
  );
END;
$$;

-- 2c. get_my_activation_code: Get current user's pending activation code
CREATE OR REPLACE FUNCTION badra_core.get_my_activation_code()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_code TEXT;
  v_expires_at TIMESTAMPTZ;
  v_phone TEXT;
BEGIN
  SELECT ac.code, ac.expires_at, ac.phone
    INTO v_code, v_expires_at, v_phone
  FROM badra_core.activation_codes ac
  WHERE ac.user_id = auth.uid()
    AND ac.used = false
    AND ac.expires_at > now()
  ORDER BY ac.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يوجد كود تفعيل صالح');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'code', v_code,
    'phone', v_phone,
    'expires_in_minutes', extract(epoch from (v_expires_at - now())) / 60
  );
END;
$$;

-- 3. get_my_profile: Get current user's profile
CREATE OR REPLACE FUNCTION badra_core.get_my_profile()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
BEGIN
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profile not found');
  END IF;

  RETURN jsonb_build_object(
    'name', v_profile.name,
    'wallet_id', v_profile.wallet_id,
    'balance', v_profile.balance,
    'created_at', v_profile.created_at,
    'is_active', v_profile.is_active
  );
END;
$$;

-- 4. get_my_transactions_fast: Get all transactions for current user
CREATE OR REPLACE FUNCTION badra_core.get_my_transactions_fast()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'is_in', t.is_in,
      'ref', t.ref,
      'store', t.store,
      'title', t.title,
      'amount', t.amount,
      'date', t.date,
      'status', t.status,
      'debtor', t.debtor,
      'creditor', t.creditor,
      'notes', t.notes
    ) ORDER BY t.date DESC
  ) INTO v_result
  FROM badra_core.transactions_v2 t
  WHERE t.user_id = auth.uid();

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 5. get_my_transactions_paginated: Get paginated transactions
CREATE OR REPLACE FUNCTION badra_core.get_my_transactions_paginated(
  p_limit INTEGER DEFAULT 10,
  p_offset INTEGER DEFAULT 0
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_total INTEGER;
  v_transactions JSONB;
BEGIN
  SELECT COUNT(*) INTO v_total
  FROM badra_core.transactions_v2
  WHERE user_id = auth.uid();

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'is_in', t.is_in,
      'ref', t.ref,
      'store', t.store,
      'title', t.title,
      'amount', t.amount,
      'date', t.date,
      'status', t.status,
      'debtor', t.debtor,
      'creditor', t.creditor,
      'notes', t.notes
    ) ORDER BY t.date DESC
  ), '[]'::jsonb) INTO v_transactions
  FROM badra_core.transactions_v2 t
  WHERE t.user_id = auth.uid()
  ORDER BY t.date DESC
  LIMIT p_limit
  OFFSET p_offset;

  RETURN jsonb_build_object(
    'total_count', v_total,
    'transactions', v_transactions
  );
END;
$$;

-- 6. get_deposit_data: Get bank account numbers for deposits
CREATE OR REPLACE FUNCTION badra_core.get_deposit_data()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_config badra_core.deposit_config%ROWTYPE;
BEGIN
  SELECT * INTO v_config
  FROM badra_core.deposit_config
  WHERE is_active = true
  ORDER BY updated_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN '0#0#0#0#Unknown';
  END IF;

  RETURN v_config.bank1 || '#' ||
         v_config.bank2 || '#' ||
         v_config.bank3 || '#' ||
         v_config.bank4 || '#' ||
         v_config.account_holder_name;
END;
$$;

-- 7. get_pending_users: List pending users (admin only)
CREATE OR REPLACE FUNCTION badra_core.get_pending_users()
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
    jsonb_build_object('id', pu.id, 'name', pu.name, 'phone', pu.phone, 'password_hash', pu.password_hash, 'ip', pu.ip, 'device_name', pu.device_name, 'device_id', pu.device_id, 'status', pu.status, 'created_at', pu.created_at)
    ORDER BY pu.created_at DESC
  ), '[]'::jsonb) INTO v_result
  FROM badra_core.pending_users pu
  WHERE pu.status = 'pending';
  RETURN v_result;
END;
$$;

-- 8. admin_fetch_activation_code: Generate new activation code (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_fetch_activation_code(
  p_phone TEXT,
  p_user_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_code TEXT;
  v_phone_clean TEXT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;
  v_phone_clean := replace(p_phone, '+', '');
  v_code := upper(substr(md5(gen_random_uuid()::text), 1, 6));
  DELETE FROM badra_core.activation_codes
  WHERE replace(phone, '+', '') = v_phone_clean AND used = false;
  INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
  VALUES (v_phone_clean, p_user_id::uuid, v_code, now() + interval '90 minutes');
  RETURN jsonb_build_object('success', true, 'code', v_code, 'expires_in_minutes', 90);
END;
$$;

-- 9. admin_delete_pending_user: Delete a pending user by ID (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_delete_pending_user(
  p_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;
  DELETE FROM badra_core.pending_users
  WHERE id = p_id::uuid;
  RETURN jsonb_build_object('success', true, 'message', 'تم الحذف');
END;
$$;

-- 10. admin_count_pending_users: Count pending users (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_count_pending_users()
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
  FROM badra_core.pending_users
  WHERE status = 'pending';
  RETURN v_count;
END;
$$;

-- 11. reject_pending_user: Reject a pending user (admin only)
CREATE OR REPLACE FUNCTION badra_core.reject_pending_user(
  p_phone TEXT,
  p_reason TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_updated INT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;
  UPDATE badra_core.pending_users
  SET status = 'rejected', updated_at = now()
  WHERE replace(phone, '+', '') = replace(p_phone, '+', '') AND status = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'لم يتم العثور على طلب معلق بهذا الرقم');
  END IF;
  RETURN jsonb_build_object('success', true, 'message', 'تم رفض الطلب');
END;
$$;

-- 12. admin_approve_finish: Clean up pending_user after approval (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_approve_finish(
  p_phone TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_deleted INT;
  v_phone_clean TEXT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;
  v_phone_clean := replace(p_phone, '+', '');
  DELETE FROM badra_core.pending_users
  WHERE replace(phone, '+', '') = v_phone_clean;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'message', 'تمت الموافقة وحذف ' || v_deleted || ' سجل', 'deleted', v_deleted);
END;
$$;

-- 13. admin_cleanup_expired_codes: Clean expired/used activation codes (admin only)
CREATE OR REPLACE FUNCTION badra_core.admin_cleanup_expired_codes(
  p_older_than_hours INTEGER DEFAULT 24
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_deleted INT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;
  DELETE FROM badra_core.activation_codes
  WHERE (used = true OR expires_at < now())
    AND created_at < now() - (p_older_than_hours || ' hours')::interval;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'message', 'تم حذف ' || v_deleted || ' سجل', 'deleted', v_deleted);
END;
$$;

-- ============================================================
-- TRIGGERS
-- ============================================================

-- Trigger 1: Auto-create profile + activation code on user signup
CREATE OR REPLACE FUNCTION badra_core.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_code TEXT;
  v_is_admin BOOLEAN;
BEGIN
  INSERT INTO badra_core.profiles (user_id, phone, name, is_active, wallet_id)
  VALUES (
    NEW.id,
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.phone),
    false,
    '101' || regexp_replace(NEW.phone, '[^0-9]', '', 'g')
  )
  ON CONFLICT (user_id) DO NOTHING;

  SELECT EXISTS (
    SELECT 1 FROM badra_core.admins WHERE user_id = NEW.id
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    v_code := COALESCE(
      NEW.raw_user_meta_data->>'activation_code',
      upper(substr(md5(gen_random_uuid()::text), 1, 6))
    );

    INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
    VALUES (NEW.phone, NEW.id, v_code, now() + interval '90 minutes')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION badra_core.handle_new_user();

-- Trigger 2: Clean up pending_users when auth user is created (admin approval)
CREATE OR REPLACE FUNCTION badra_core.cleanup_pending_on_auth_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  DELETE FROM badra_core.pending_users
  WHERE replace(phone, '+', '') = replace(NEW.phone, '+', '');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_cleanup_pending ON auth.users;
CREATE TRIGGER on_auth_user_cleanup_pending
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION badra_core.cleanup_pending_on_auth_insert();

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================
ALTER TABLE badra_core.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE badra_core.bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE badra_core.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE badra_core.transactions_v2 ENABLE ROW LEVEL SECURITY;
ALTER TABLE badra_core.pending_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE badra_core.user_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE badra_core.activation_codes ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile
CREATE POLICY select_own_profile ON badra_core.profiles
  FOR SELECT USING (user_id = auth.uid());

-- Users can read their own bank accounts
CREATE POLICY select_own_bank_accounts ON badra_core.bank_accounts
  FOR SELECT USING (user_id = auth.uid());

-- Users can read their own transactions
CREATE POLICY select_own_transactions ON badra_core.transactions
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY select_own_transactions_v2 ON badra_core.transactions_v2
  FOR SELECT USING (user_id = auth.uid());

-- Service role can manage pending_users
CREATE POLICY service_pending_users ON badra_core.pending_users
  FOR ALL USING (true);

-- Service role can manage activation_codes
CREATE POLICY service_activation_codes ON badra_core.activation_codes
  FOR ALL USING (true);

-- ============================================================
-- SEED DATA (optional - configure as needed)
-- ============================================================
-- Insert a default deposit config (UPDATE with your real bank accounts)
INSERT INTO badra_core.deposit_config (bank1, bank2, bank3, bank4, account_holder_name)
VALUES ('0000', '0000', '0000', '0000', 'اسم المستخدم')
ON CONFLICT DO NOTHING;

-- ============================================================
-- DONE! Your database is ready.
-- Next steps:
-- 1. Update .env file with new Supabase URL and anon key
-- 2. Update SSL fingerprint in security_service.dart
-- 3. Admin authorization uses badra_core.admins table (not JWT app_metadata.role)
-- 4. Add admins manually: INSERT INTO badra_core.admins (user_id) VALUES ('<auth_user_id>');
-- 5. Admin can manage activation via: admin_fetch_activation_code,
--    admin_cleanup_expired_codes, admin_approve_finish
-- ============================================================
