-- ============================================================
-- بذرة (Badra) — تحصين دالة الإيداع اليدوي ومنع تكرار السندات البنكية
-- Anti-Double Deposit, Advisory Locking, and Strict Receipt Validation
-- ============================================================

-- 1. فهرس مركب سريع للتحقق الفوري من فرادة السند لكل بنك
CREATE INDEX IF NOT EXISTS idx_deposit_requests_bank_receipt 
ON badra_core.deposit_requests(bank_name, receipt_number);

-- 2. تحديث دالة admin_manual_deposit بالمعايير المصرفية الصارمة
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
    v_profile_id UUID;
    v_user_id UUID;
    v_old_balance NUMERIC;
    v_admin_name TEXT;
    v_deposit_id UUID;
    v_tx_id UUID;
    v_notes_full TEXT;
    v_clean_receipt TEXT;
BEGIN
    -- التحقق من صلاحية الأدمن
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN RAISE EXCEPTION 'غير مصرح'; END IF;
    IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN RAISE EXCEPTION 'غير مصرح: لست أدمن'; END IF;
    
    -- التحقق من حدود المبلغ المعتمدة
    IF p_amount < 500 THEN RAISE EXCEPTION 'الحد الأدنى 500 ريال';
    ELSIF p_amount > 250000 THEN RAISE EXCEPTION 'الحد الأقصى 250,000 ريال'; END IF;
    
    -- التحقق من البنك
    IF p_bank_name NOT IN ('العمقي','الكرايمي','القطيبي','البسيري') THEN RAISE EXCEPTION 'بنك غير صحيح'; END IF;

    -- 🛡️ 1. تنظيف رقم السند من أي مسافات داخلية أو خارجية أو رموز مخفية وتوحيد الأحرف
    v_clean_receipt := upper(regexp_replace(trim(COALESCE(p_receipt_number, '')), '\s+', '', 'g'));

    -- 🛡️ 2. فحص إلزامية وصلاحية رقم السند
    IF v_clean_receipt IS NULL OR v_clean_receipt = '' OR length(v_clean_receipt) < 4 OR length(v_clean_receipt) > 40 THEN
        RAISE EXCEPTION 'رقم السند / الإيصال البنكي إجباري ومطلوب (بين 4 و 40 خانة)';
    END IF;

    -- حظر القيم الوهمية والعشوائية
    IF v_clean_receipt IN ('0000','00000','000000','1111','1234','12345','TEST','NONE','NULL','N/A') THEN
        RAISE EXCEPTION 'رقم السند المدخل وهمي وغير مقبول، يرجى كتابة رقم السند البنكي الفعلي';
    END IF;

    -- 🛡️ 3. قفل استشاري فوري للمعاملة لمنع ثغرة التزامن والسباق (Anti-Race Condition)
    PERFORM pg_advisory_xact_lock(hashtext('receipt:' || p_bank_name || ':' || v_clean_receipt));

    -- 🛡️ 4. فحص عدم تكرار السند لنفس البنك نهائياً لمنع أي إيداع مزدوج (Anti-Double Deposit)
    IF EXISTS (
        SELECT 1 FROM badra_core.deposit_requests
        WHERE bank_name = p_bank_name AND upper(receipt_number) = v_clean_receipt
    ) THEN
        RAISE EXCEPTION 'رقم السند البنكي (%) مسجل مسبقاً لدى بنك (%)! تم إلغاء العملية فوراً لمنع تكرار الإيداع', v_clean_receipt, p_bank_name;
    END IF;

    -- جلب اسم الأدمن للتوثيق
    SELECT name INTO v_admin_name FROM badra_core.profiles WHERE user_id = v_admin_id LIMIT 1;
    IF v_admin_name IS NULL THEN v_admin_name := 'أدمن'; END IF;

    -- قفل صف العميل للتحقق وتحديث الرصيد
    SELECT id, user_id, balance INTO v_profile_id, v_user_id, v_old_balance
    FROM badra_core.profiles
    WHERE wallet_id = p_wallet_id AND phone = p_phone AND name = p_name
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'المستخدم غير موجود'; END IF;

    -- تحديث رصيد العميل
    UPDATE badra_core.profiles SET balance = balance + p_amount, updated_at = now()
    WHERE id = v_profile_id;

    -- بناء الملاحظات
    v_notes_full := v_clean_receipt;
    IF p_notes != '' THEN
        v_notes_full := v_notes_full || ' | ' || p_notes;
    END IF;

    -- تسجيل طلب الإيداع برقم السند المنظف
    INSERT INTO badra_core.deposit_requests(user_id, amount, bank_name, receipt_number, notes, admin_id, admin_name)
    VALUES(v_user_id, p_amount, p_bank_name, v_clean_receipt, NULLIF(p_notes, ''), v_admin_id, v_admin_name)
    RETURNING id INTO v_deposit_id;

    -- تسجيل المعاملة المالية في transactions_v2
    INSERT INTO badra_core.transactions_v2(
        user_id, is_in, amount, title, date, status, notes, 
        debtor, creditor, deposit_request_id
    )
    VALUES(
        v_user_id, 1, p_amount, 
        'إيداع عبر الأدمن - ' || p_bank_name, 
        now(), 'completed', 
        NULLIF(v_notes_full, ''),
        p_bank_name,
        p_name,
        v_deposit_id
    )
    RETURNING id INTO v_tx_id;

    -- تحديث ملخص الأرصدة للنظام
    UPDATE badra_core.balance_summary
    SET total_received = total_received + p_amount, updated_at = now()
    WHERE id = (SELECT id FROM badra_core.balance_summary LIMIT 1);

    -- تسجيل الحدث في سجل المراجعة والرقابة (Audit Log)
    INSERT INTO badra_core.audit_log(action, table_name, record_id, old_values, new_values, admin_id, admin_name)
    VALUES('deposit', 'profiles', v_profile_id,
           jsonb_build_object('balance', v_old_balance),
           jsonb_build_object('balance', v_old_balance + p_amount, 'deposit_id', v_deposit_id, 'transaction_id', v_tx_id, 'amount', p_amount, 'bank', p_bank_name, 'debtor', p_bank_name, 'creditor', p_name, 'receipt', v_clean_receipt),
           v_admin_id, v_admin_name);

    RETURN jsonb_build_object(
        'success', true, 
        'amount', p_amount, 
        'user_id', v_user_id, 
        'old_balance', v_old_balance, 
        'new_balance', v_old_balance + p_amount, 
        'deposit_id', v_deposit_id, 
        'transaction_id', v_tx_id, 
        'receipt', v_clean_receipt
    );
END;
$$;
