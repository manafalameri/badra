-- ============================================================
-- بذرة (Badra) — balance_summary table + auto-update
-- Tracks total_received (deposits) and total_distributed (withdrawals)
-- ============================================================

-- 1. Create table if not exists (idempotent)
CREATE TABLE IF NOT EXISTS badra_core.balance_summary (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    total_received NUMERIC NOT NULL DEFAULT 0,
    total_distributed NUMERIC NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

-- 2. Seed current value from existing transactions
DELETE FROM badra_core.balance_summary;
INSERT INTO badra_core.balance_summary (total_received, total_distributed, updated_at)
SELECT
    COALESCE((SELECT SUM(amount) FROM badra_core.transactions_v2 WHERE is_in = 1), 0),
    COALESCE((SELECT SUM(amount) FROM badra_core.transactions_v2 WHERE is_in = 0), 0),
    now();

-- 3. Update admin_manual_deposit to maintain balance_summary
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

    -- Update balance_summary
    UPDATE badra_core.balance_summary
    SET total_received = total_received + p_amount,
        updated_at = now()
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
-- DONE! balance_summary is now defined and auto-updating.
-- ============================================================
