-- ============================================================
-- Fix user_id mismatch between admin_manual_deposit and get_my_transactions
-- 
-- BUG: admin_manual_deposit stored profiles.id in transactions_v2.user_id,
--      but get_my_transactions filters by auth.uid() (= profiles.user_id).
--      So transactions never appeared in the user's history.
--
-- Fix: Change FK to profiles.user_id and fix the function.
-- ============================================================

-- 1. Drop old FK constraints (referenced profiles.id)
ALTER TABLE IF EXISTS badra_core.transactions_v2 DROP CONSTRAINT IF EXISTS transactions_v2_user_id_fkey;
ALTER TABLE IF EXISTS badra_core.deposit_requests DROP CONSTRAINT IF EXISTS deposit_requests_user_id_fkey;

-- 2. Fix existing transactions: update user_id from profiles.id to profiles.user_id
UPDATE badra_core.transactions_v2 t
SET user_id = p.user_id
FROM badra_core.profiles p
WHERE p.id = t.user_id AND p.user_id != p.id;

-- 3. Fix existing deposit_requests: update user_id from profiles.id to profiles.user_id
UPDATE badra_core.deposit_requests d
SET user_id = p.user_id
FROM badra_core.profiles p
WHERE p.id = d.user_id AND p.user_id != p.id;

-- 4. Add new FK constraints referencing profiles.user_id (matches auth.users.id)
ALTER TABLE badra_core.transactions_v2
ADD CONSTRAINT transactions_v2_user_id_fkey
FOREIGN KEY (user_id) REFERENCES badra_core.profiles(user_id) ON DELETE CASCADE;

ALTER TABLE badra_core.deposit_requests
ADD CONSTRAINT deposit_requests_user_id_fkey
FOREIGN KEY (user_id) REFERENCES badra_core.profiles(user_id) ON DELETE CASCADE;

-- 5. Fix admin_get_deposit_records JOIN: use p.user_id instead of p.id
CREATE OR REPLACE FUNCTION badra_core.admin_get_deposit_records()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
    v_admin_id UUID;
    v_result JSONB;
BEGIN
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN RAISE EXCEPTION 'غير مصرح'; END IF;
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
    JOIN badra_core.profiles p ON p.user_id = dr.user_id
    JOIN badra_core.profiles a ON a.user_id = dr.admin_id;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

-- 6. Rewrite admin_manual_deposit with correct user_id handling
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

    -- Select profiles.id (for UPDATE) AND profiles.user_id (for FK columns)
    SELECT id, user_id, balance INTO v_profile_id, v_user_id, v_old_balance
    FROM badra_core.profiles
    WHERE wallet_id = p_wallet_id AND phone = p_phone AND name = p_name
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'المستخدم غير موجود'; END IF;

    -- Update balance using profiles.id (primary key)
    UPDATE badra_core.profiles SET balance = balance + p_amount, updated_at = now()
    WHERE id = v_profile_id;

    -- Insert deposit_request using profiles.user_id (matches auth.users.id)
    INSERT INTO badra_core.deposit_requests(user_id,amount,bank_name,receipt_number,notes,admin_id,admin_name)
    VALUES(v_user_id,p_amount,p_bank_name,NULLIF(p_receipt_number,''),NULLIF(p_notes,''),v_admin_id,v_admin_name)
    RETURNING id INTO v_deposit_id;

    -- Insert transaction using profiles.user_id (matches auth.users.id for get_my_transactions)
    INSERT INTO badra_core.transactions_v2(user_id,is_in,amount,title,date,status,notes,deposit_request_id)
    VALUES(v_user_id,1,p_amount,'إيداع عبر الأدمن - '||p_bank_name,now(),'completed',NULLIF(p_notes,''),v_deposit_id)
    RETURNING id INTO v_tx_id;

    -- Audit log
    INSERT INTO badra_core.audit_log(action,table_name,record_id,old_values,new_values,admin_id,admin_name)
    VALUES('deposit','profiles',v_profile_id,
           jsonb_build_object('balance',v_old_balance),
           jsonb_build_object('balance',v_old_balance+p_amount,'deposit_id',v_deposit_id,'transaction_id',v_tx_id,'amount',p_amount,'bank',p_bank_name),
           v_admin_id,v_admin_name);

    RETURN jsonb_build_object('success',true,'amount',p_amount,'user_id',v_user_id,'old_balance',v_old_balance,'new_balance',v_old_balance+p_amount,'deposit_id',v_deposit_id,'transaction_id',v_tx_id);
END;
$$;

-- ============================================================
-- DONE! user_id mismatch is fixed.
-- ============================================================
