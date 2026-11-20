-- ============================================================
-- Fix Store Payment RPC — v2
-- wallet_id (unique) بدل phone (غير موجود)
-- id بدل user_id (العمود الفعلي id مو user_id)
-- إزالة is_active و updated_at (غير موجودة)
-- إضافة duplicate order_ref check (منع الخصم المزدوج)
-- ============================================================

DROP FUNCTION IF EXISTS badra_core.deduct_balance_and_create_transaction;

CREATE OR REPLACE FUNCTION badra_core.deduct_balance_and_create_transaction(
    p_wallet_id TEXT,
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
    -- منع الخصم المزدوج: إذا order_ref موجود مسبقاً، نرفض
    IF p_order_ref != '' THEN
        PERFORM 1 FROM badra_core.transactions_v2 WHERE ref = p_order_ref;
        IF FOUND THEN
            RETURN jsonb_build_object('success', false, 'error', 'تم معالجة هذا الطلب مسبقاً');
        END IF;
    END IF;

    -- قفل الصف + جلب id (العمود الموجود) و balance
    SELECT id, balance INTO v_user_id, v_old_balance
    FROM badra_core.profiles
    WHERE wallet_id = p_wallet_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'المحفظة غير موجودة');
    END IF;

    IF v_old_balance < p_amount THEN
        RETURN jsonb_build_object('success', false, 'error', 'الرصيد غير كاف', 'balance', v_old_balance, 'required', p_amount);
    END IF;

    v_new_balance := v_old_balance - p_amount;

    UPDATE badra_core.profiles
    SET balance = v_new_balance
    WHERE wallet_id = p_wallet_id;

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
