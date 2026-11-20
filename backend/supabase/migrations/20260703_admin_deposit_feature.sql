-- ============================================================
-- بذرة (Badra) — Admin Deposit Feature
-- Tables: admins, deposit_requests
-- RPCs: admin_manual_deposit, admin_get_deposit_records
-- ============================================================

-- 1. Admins table (for RPC-level authorization)
CREATE TABLE IF NOT EXISTS badra_core.admins (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 2. Deposit requests table
CREATE TABLE IF NOT EXISTS badra_core.deposit_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES badra_core.profiles(user_id),
    amount NUMERIC NOT NULL CHECK (amount > 0),
    bank_name TEXT NOT NULL CHECK (bank_name IN ('العمقي', 'الكرايمي', 'القطيبي', 'البسيري')),
    type TEXT NOT NULL DEFAULT 'manual' CHECK (type IN ('manual')),
    status TEXT NOT NULL DEFAULT 'approved' CHECK (status IN ('approved')),
    receipt_number TEXT UNIQUE,
    notes TEXT DEFAULT '',
    admin_id UUID NOT NULL REFERENCES auth.users(id),
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_deposit_requests_user_id ON badra_core.deposit_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_deposit_requests_admin_id ON badra_core.deposit_requests(admin_id);
CREATE INDEX IF NOT EXISTS idx_deposit_requests_created_at ON badra_core.deposit_requests(created_at DESC);

-- RLS
ALTER TABLE badra_core.admins ENABLE ROW LEVEL SECURITY;
ALTER TABLE badra_core.deposit_requests ENABLE ROW LEVEL SECURITY;

-- Admins: only admins can see the admins table
CREATE POLICY select_admins ON badra_core.admins
    FOR SELECT USING (auth.uid() IN (SELECT user_id FROM badra_core.admins));

-- Deposit requests: only admins can see deposit_requests
CREATE POLICY select_deposit_requests ON badra_core.deposit_requests
    FOR SELECT USING (auth.uid() IN (SELECT user_id FROM badra_core.admins));

-- 3. RPC: admin_manual_deposit (المحفظة + الجوال + الاسم كلها إجبارية)
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
SET search_path = badra_core
AS $$
DECLARE
    v_admin_id UUID;
    v_user_id UUID;
    v_old_balance NUMERIC;
    v_found BOOLEAN;
BEGIN
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN RAISE EXCEPTION 'غير مصرح: يجب تسجيل الدخول'; END IF;
    IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN RAISE EXCEPTION 'غير مصرح: أنت لست أدمن'; END IF;
    IF p_amount <= 0 THEN RAISE EXCEPTION 'المبلغ يجب أن يكون أكبر من صفر'; END IF;
    IF p_bank_name NOT IN ('العمقي', 'الكرايمي', 'القطيبي', 'البسيري') THEN RAISE EXCEPTION 'اسم البنك غير صحيح'; END IF;
    IF NULLIF(p_wallet_id, '') IS NULL THEN RAISE EXCEPTION 'رقم المحفظة مطلوب'; END IF;
    IF NULLIF(p_phone, '') IS NULL THEN RAISE EXCEPTION 'رقم الجوال مطلوب'; END IF;
    IF NULLIF(p_name, '') IS NULL THEN RAISE EXCEPTION 'الاسم مطلوب'; END IF;

    SELECT EXISTS (
        SELECT 1 FROM badra_core.profiles
        WHERE wallet_id = p_wallet_id AND phone = p_phone AND name = p_name
    ) INTO v_found;

    IF NOT v_found THEN RAISE EXCEPTION 'المستخدم غير موجود (تأكد من صحة البيانات)'; END IF;

    SELECT id INTO v_user_id FROM badra_core.profiles
    WHERE wallet_id = p_wallet_id AND phone = p_phone AND name = p_name
    LIMIT 1;

    SELECT balance INTO v_old_balance FROM badra_core.profiles WHERE id = v_user_id FOR UPDATE;
    UPDATE badra_core.profiles SET balance = balance + p_amount, updated_at = now() WHERE id = v_user_id;

    INSERT INTO badra_core.transactions_v2 (user_id, is_in, amount, title, date, status, notes)
    VALUES (v_user_id, 1, p_amount, 'إيداع عبر الأدمن - ' || p_bank_name, now(), 'completed',
            CASE WHEN p_notes != '' THEN p_notes ELSE NULL END);

    INSERT INTO badra_core.deposit_requests (user_id, amount, bank_name, receipt_number, notes, admin_id)
    VALUES (v_user_id, p_amount, p_bank_name,
            CASE WHEN p_receipt_number != '' THEN p_receipt_number ELSE NULL END,
            CASE WHEN p_notes != '' THEN p_notes ELSE NULL END,
            v_admin_id);

    RETURN jsonb_build_object('success', true, 'user_id', v_user_id, 'amount', p_amount, 'old_balance', v_old_balance, 'new_balance', v_old_balance + p_amount);
END;
$$;

-- 4. RPC: admin_get_deposit_records
CREATE OR REPLACE FUNCTION badra_core.admin_get_deposit_records()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core
AS $$
DECLARE
    v_admin_id UUID;
    v_result JSONB;
BEGIN
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN
        RAISE EXCEPTION 'غير مصرح';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN
        RAISE EXCEPTION 'غير مصرح: أنت لست أدمن';
    END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'id', dr.id,
            'user_name', p.name,
            'user_phone', p.phone,
            'user_wallet_id', p.wallet_id,
            'amount', dr.amount,
            'bank_name', dr.bank_name,
            'receipt_number', dr.receipt_number,
            'notes', dr.notes,
            'admin_name', a.name,
            'created_at', dr.created_at
        ) ORDER BY dr.created_at DESC
    ) INTO v_result
    FROM badra_core.deposit_requests dr
    JOIN badra_core.profiles p ON p.id = dr.user_id
    JOIN badra_core.profiles a ON a.user_id = dr.admin_id;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 5. RPC: admin_get_sum (حساب الإجمالي من transactions_v2)
CREATE OR REPLACE FUNCTION badra_core.admin_get_sum(p_is_in INT DEFAULT 1)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core
AS $$
BEGIN
    IF NOT badra_core.is_admin() THEN
        RAISE EXCEPTION 'غير مصرح: أنت لست أدمن';
    END IF;
    RETURN COALESCE((SELECT SUM(amount) FROM badra_core.transactions_v2 WHERE is_in = p_is_in), 0);
END;
$$;

-- 6. إلغاء صلاحية الاستدعاء من anon و public للأمان
REVOKE EXECUTE ON FUNCTION badra_core.admin_manual_deposit(text,text,text,numeric,text,text,text) FROM anon, public;
REVOKE EXECUTE ON FUNCTION badra_core.admin_get_sum(integer) FROM anon, public;
REVOKE EXECUTE ON FUNCTION badra_core.admin_get_deposit_records() FROM anon, public;

-- ============================================================
-- DONE! Admin deposit feature schema is ready.
-- ============================================================
