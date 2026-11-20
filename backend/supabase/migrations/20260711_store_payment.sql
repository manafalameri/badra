-- ============================================================
-- Atomic Store Payment — 2026-07-11
-- ============================================================
-- Edge Function واحدة atomic: خصم الرصيد + إنشاء حركة
-- ============================================================

CREATE OR REPLACE FUNCTION badra_core.deduct_balance_and_create_transaction(
    p_customer_phone TEXT,
    p_amount NUMERIC,
    p_store_name TEXT DEFAULT 'برسم',
    p_order_ref TEXT DEFAULT '',
    p_items JSONB DEFAULT '[]'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
    v_user_id UUID;
    v_old_balance NUMERIC;
    v_new_balance NUMERIC;
    v_tx_id UUID;
BEGIN
    SELECT user_id, balance INTO v_user_id, v_old_balance
    FROM badra_core.profiles
    WHERE phone = p_customer_phone AND is_active = true
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود أو الحساب غير نشط');
    END IF;

    IF v_old_balance < p_amount THEN
        RETURN jsonb_build_object('success', false, 'error', 'الرصيد غير كاف', 'balance', v_old_balance, 'required', p_amount);
    END IF;

    v_new_balance := v_old_balance - p_amount;

    UPDATE badra_core.profiles
    SET balance = v_new_balance, updated_at = now()
    WHERE phone = p_customer_phone;

    INSERT INTO badra_core.transactions_v2 (
        user_id, is_in, amount, type, status, description, store, ref, notes, date
    ) VALUES (
        v_user_id, 0, p_amount, 'outgoing', 'completed',
        'مشتريات من ' || p_store_name,
        p_store_name, p_order_ref,
        CASE WHEN p_items != '[]'::jsonb THEN 'items: ' || p_items::text ELSE NULL END,
        now()
    ) RETURNING id INTO v_tx_id;

    RETURN jsonb_build_object(
        'success', true,
        'transaction_id', v_tx_id,
        'new_balance', v_new_balance,
        'old_balance', v_old_balance
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.deduct_balance_and_create_transaction FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.deduct_balance_and_create_transaction TO service_role;
