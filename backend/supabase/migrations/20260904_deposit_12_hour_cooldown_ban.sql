-- ============================================================
-- بذرة (Badra) — الحظر الأمني المطلق لفترة التهدئة (12 ساعة كاملة)
-- 12-Hour Cooldown Absolute Ban on Manual Deposits with Dual Advisory Lock
-- ============================================================

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
    v_last_deposit TIMESTAMPTZ;
    v_remaining_seconds INT;
    v_remaining_hours INT;
    v_remaining_minutes INT;
BEGIN
    -- 1. التحقق من صلاحية الأدمن
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN RAISE EXCEPTION 'غير مصرح'; END IF;
    IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN RAISE EXCEPTION 'غير مصرح: لست أدمن'; END IF;
    
    -- 2. التحقق من حدود المبلغ المعتمدة
    IF p_amount < 500 THEN RAISE EXCEPTION 'الحد الأدنى 500 ريال';
    ELSIF p_amount > 250000 THEN RAISE EXCEPTION 'الحد الأقصى 250,000 ريال'; END IF;
    
    -- 3. التحقق من البنك
    IF p_bank_name NOT IN ('العمقي','الكرايمي','القطيبي','البسيري') THEN RAISE EXCEPTION 'بنك غير صحيح'; END IF;

    -- 🛡️ 4. تنظيف رقم السند وتوحيده
    v_clean_receipt := upper(regexp_replace(trim(COALESCE(p_receipt_number, '')), '\s+', '', 'g'));

    -- 🛡️ 5. فحص إلزامية وصلاحية رقم السند وحظر القيم الوهمية
    IF v_clean_receipt IS NULL OR v_clean_receipt = '' OR length(v_clean_receipt) < 4 OR length(v_clean_receipt) > 40 THEN
        RAISE EXCEPTION 'رقم السند / الإيصال البنكي إجباري ومطلوب (بين 4 و 40 خانة)';
    END IF;

    IF v_clean_receipt IN ('0000','00000','000000','1111','1234','12345','TEST','NONE','NULL','N/A') THEN
        RAISE EXCEPTION 'رقم السند المدخل وهمي وغير مقبول، يرجى كتابة رقم السند البنكي الفعلي';
    END IF;

    -- 🛡️ 6. القفل الذري الأول: قفل المعاملة على مستوى السند والبنك لمنع تكرار السند
    PERFORM pg_advisory_xact_lock(hashtext('receipt:' || p_bank_name || ':' || v_clean_receipt));

    -- 🛡️ 7. فحص عدم تكرار السند لنفس البنك نهائياً (Anti-Double Deposit)
    IF EXISTS (
        SELECT 1 FROM badra_core.deposit_requests
        WHERE bank_name = p_bank_name AND upper(receipt_number) = v_clean_receipt
    ) THEN
        RAISE EXCEPTION 'رقم السند البنكي (%) مسجل مسبقاً لدى بنك (%)! تم إلغاء العملية فوراً لمنع تكرار الإيداع', v_clean_receipt, p_bank_name;
    END IF;

    -- 8. جلب اسم الأدمن للتوثيق
    SELECT name INTO v_admin_name FROM badra_core.profiles WHERE user_id = v_admin_id LIMIT 1;
    IF v_admin_name IS NULL THEN v_admin_name := 'أدمن'; END IF;

    -- 9. قفل صف العميل للتحقق
    SELECT id, user_id, balance INTO v_profile_id, v_user_id, v_old_balance
    FROM badra_core.profiles
    WHERE wallet_id = p_wallet_id AND phone = p_phone AND name = p_name
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'المستخدم غير موجود'; END IF;

    -- 🛡️ 10. القفل الذري الثاني: قفل ذري لمعاملات العميل لمنع سباق التهدئة (Anti-Race Condition on Cooldown)
    PERFORM pg_advisory_xact_lock(hashtext('user_cooldown:' || v_user_id::text));

    -- 🛡️ 11. فحص فترة التهدئة الإلزامية (12 ساعة كاملة - حظر مطلق بدون استثناء)
    SELECT created_at INTO v_last_deposit
    FROM badra_core.deposit_requests
    WHERE user_id = v_user_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_last_deposit IS NOT NULL AND (now() - v_last_deposit) < INTERVAL '12 hours' THEN
        v_remaining_seconds := EXTRACT(EPOCH FROM ((v_last_deposit + INTERVAL '12 hours') - now()))::INT;
        v_remaining_hours := v_remaining_seconds / 3600;
        v_remaining_minutes := (v_remaining_seconds % 3600) / 60;
        
        RAISE EXCEPTION 'حظر أمني مطلق: تم إيداع رصيد لهذا الحساب مؤخراً! بموجب سياسة الأمان الصارمة، لا يمكن الإيداع لنفس الحساب إلا بعد مرور 12 ساعة كاملة (المتبقي: % ساعة و % دقيقة)',
            v_remaining_hours, v_remaining_minutes;
    END IF;

    -- 12. تحديث رصيد العميل
    UPDATE badra_core.profiles SET balance = balance + p_amount, updated_at = now()
    WHERE id = v_profile_id;

    -- 13. بناء الملاحظات
    v_notes_full := v_clean_receipt;
    IF p_notes != '' THEN
        v_notes_full := v_notes_full || ' | ' || p_notes;
    END IF;

    -- 14. تسجيل طلب الإيداع
    INSERT INTO badra_core.deposit_requests(user_id, amount, bank_name, receipt_number, notes, admin_id, admin_name)
    VALUES(v_user_id, p_amount, p_bank_name, v_clean_receipt, NULLIF(p_notes, ''), v_admin_id, v_admin_name)
    RETURNING id INTO v_deposit_id;

    -- 15. تسجيل المعاملة المالية في transactions_v2
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

    -- 16. تحديث ملخص الأرصدة للنظام
    UPDATE badra_core.balance_summary
    SET total_received = total_received + p_amount, updated_at = now()
    WHERE id = (SELECT id FROM badra_core.balance_summary LIMIT 1);

    -- 17. تسجيل الحدث في سجل المراجعة والرقابة (Audit Log)
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
