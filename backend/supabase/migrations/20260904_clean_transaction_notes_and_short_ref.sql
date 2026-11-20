-- ============================================================
-- بذرة (Badra) — تنظيف الملاحظات وإلغاء حشو رقم المعاملة وتوفير short_ref فائق السرعة
-- Clean Transaction Notes & Server-side short_ref Generation
-- ============================================================

-- 1. تنظيف البيانات المكررة والملوثة في السجلات السابقة لجدول transactions_v2
-- أ) تفريغ نصوص order_ref: و order: المكررة
UPDATE badra_core.transactions_v2
SET notes = ''
WHERE notes LIKE 'order_ref:%'
   OR notes LIKE 'order:%'
   OR notes = ref;

-- ب) الإبقاء على نص الخصم المفيد فقط وحذف تكرار رقم الطلب
UPDATE badra_core.transactions_v2
SET notes = regexp_replace(notes, '\s*—\s*order:\s*.*$', '')
WHERE notes LIKE '%خصم:%' AND notes LIKE '%— order:%';

-- ج) لمعاملات الإيداع السابقة التي بقي فيها ref فارغاً:
-- تعبئة ref برقم السند البنكي من deposit_requests وتنظيف notes
UPDATE badra_core.transactions_v2 t
SET ref = dr.receipt_number,
    notes = COALESCE(NULLIF(dr.notes, ''), '')
FROM badra_core.deposit_requests dr
WHERE t.deposit_request_id = dr.id 
  AND (t.ref IS NULL OR t.ref = '');


-- 2. تحديث دالة approve_payment_request_v2 لمنع كتابة رقم المعاملة في الملاحظات
CREATE OR REPLACE FUNCTION badra_core.approve_payment_request_v2(
    p_request_id UUID,
    p_challenge_code TEXT DEFAULT '',
    p_device_id TEXT DEFAULT '',
    p_security_code TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'badra_core', 'public', 'extensions'
AS $$
DECLARE
  v_user_id UUID;
  v_request RECORD;
  v_attempt_count INT;
  v_pin_stored TEXT;
  v_device_record RECORD;
  v_balance NUMERIC;
  v_tx_id UUID;
  v_merchant_name TEXT;
  v_customer_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = 'security_code'
    AND attempted_at > now() - interval '30 minutes';
  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم قفل الرقم السري مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  SELECT * INTO v_request FROM badra_core.payment_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'طلب الدفع غير موجود'); END IF;
  IF v_request.user_id != v_user_id THEN RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بهذا الطلب'); END IF;
  IF v_request.status != 'pending' THEN RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب تم معالجته مسبقاً'); END IF;
  IF v_request.expires_at < now() THEN
    UPDATE badra_core.payment_requests SET status = 'expired' WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  IF p_device_id = '' THEN RETURN jsonb_build_object('success', false, 'error', 'معرف الجهاز مطلوب'); END IF;
  SELECT * INTO v_device_record FROM badra_core.user_devices WHERE user_id = v_user_id AND device_id = p_device_id;
  IF v_device_record IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مسجل. يرجى تسجيل الدخول من جهازك'); END IF;

  SELECT security_code INTO v_pin_stored FROM badra_core.profiles WHERE user_id = v_user_id;
  IF v_pin_stored IS NULL OR v_pin_stored = '' THEN RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين الرقم السري'); END IF;
  IF p_security_code = '' THEN RETURN jsonb_build_object('success', false, 'error', 'الرقم السري إجباري'); END IF;
  IF v_pin_stored NOT LIKE '$2%' THEN RETURN jsonb_build_object('success', false, 'error', 'يجب إعادة تعيين الرقم السري من الإعدادات'); END IF;
  IF v_pin_stored != crypt(p_security_code, v_pin_stored) THEN
    INSERT INTO badra_core.challenge_attempts (user_id, attempt_type) VALUES (v_user_id, 'security_code');
    RETURN jsonb_build_object('success', false, 'error', 'الرقم السري غير صحيح');
  END IF;
  DELETE FROM badra_core.challenge_attempts WHERE user_id = v_user_id AND attempt_type = 'security_code';

  SELECT balance INTO v_balance FROM badra_core.profiles WHERE user_id = v_user_id FOR UPDATE;
  IF v_balance < v_request.amount THEN RETURN jsonb_build_object('success', false, 'error', 'رصيد غير كافي'); END IF;

  UPDATE badra_core.profiles SET balance = balance - v_request.amount, updated_at = now() WHERE user_id = v_user_id;
  
  -- جلب اسم التاجر واسم الزبون
  SELECT name INTO v_merchant_name FROM badra_core.merchants WHERE id = v_request.merchant_id;
  SELECT name INTO v_customer_name FROM badra_core.profiles WHERE user_id = v_user_id;

  -- إدراج المعاملة: الملاحظات نظيفة تماماً ولا يتم حشو order_ref فيها
  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store,
    debtor, creditor
  ) VALUES (
    v_user_id, 0, v_request.amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed', now(),
    '',                       -- الملاحظات فارغة ونظيفة
    v_request.order_ref,      -- رقم المرجع في مكانه المخصص فقط
    COALESCE(v_merchant_name, ''),
    v_customer_name,          -- المدين: الزبون الدافع
    v_merchant_name           -- الدائن: التاجر المستلم
  )
  RETURNING id INTO v_tx_id;

  UPDATE badra_core.payment_requests SET status = 'approved', approved_at = now(), tx_id = v_tx_id WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'transaction_id', v_tx_id,
    'new_balance', v_balance - v_request.amount, 'old_balance', v_balance, 'amount', v_request.amount);
END;
$$;


-- 3. تحديث دالة execute_approved_payment
CREATE OR REPLACE FUNCTION badra_core.execute_approved_payment(
    p_user_id UUID,
    p_request_id UUID,
    p_amount NUMERIC,
    p_merchant_id UUID,
    p_order_ref TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'badra_core', 'public'
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_request badra_core.payment_requests%ROWTYPE;
  v_merchant_name TEXT;
  v_new_balance NUMERIC;
  v_tx_id UUID;
BEGIN
  -- Lock the payment request row
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
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

  -- Lock and check user balance
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  IF v_profile.balance < p_amount THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'الرصيد غير كاف',
      'balance', v_profile.balance, 'required', p_amount
    );
  END IF;

  v_new_balance := v_profile.balance - p_amount;

  UPDATE badra_core.profiles
  SET balance = v_new_balance, updated_at = now()
  WHERE user_id = p_user_id;

  SELECT name INTO v_merchant_name
  FROM badra_core.merchants
  WHERE id = p_merchant_id;

  -- إدراج المعاملة: بدون تلويث الملاحظات
  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store,
    debtor, creditor
  ) VALUES (
    p_user_id, 0, p_amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed', now(),
    '',                       -- الملاحظات نظيفة
    p_order_ref,              -- رقم المرجع فقط
    COALESCE(v_merchant_name, ''),
    v_profile.name,
    v_merchant_name
  ) RETURNING id INTO v_tx_id;

  UPDATE badra_core.payment_requests
  SET status = 'approved', approved_at = now(), tx_id = v_tx_id
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', v_tx_id,
    'new_balance', v_new_balance,
    'old_balance', v_profile.balance,
    'amount', p_amount
  );
END;
$$;


-- 4. تحديث دالة redeem_coupon_and_pay
CREATE OR REPLACE FUNCTION badra_core.redeem_coupon_and_pay(
    p_user_id       UUID,
    p_request_id    UUID,
    p_merchant_id   UUID,
    p_amount        NUMERIC,
    p_order_ref     TEXT,
    p_coupon_code   TEXT DEFAULT '',
    p_device_id     TEXT DEFAULT ''
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'badra_core', 'public'
AS $$
DECLARE
  v_profile       badra_core.profiles%ROWTYPE;
  v_request       badra_core.payment_requests%ROWTYPE;
  v_merchant_name TEXT;
  v_coupon        badra_core.discount_codes%ROWTYPE;
  v_discount      NUMERIC := 0;
  v_final_amount  NUMERIC;
  v_tx_id         UUID;
  v_updated       INT;
  v_notes         TEXT := '';
BEGIN
  -- A. قفل وفحص طلب الدفع
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;
  IF v_request.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب تمت معالجته مسبقاً');
  END IF;
  IF v_request.expires_at <= now() THEN
    UPDATE badra_core.payment_requests SET status = 'expired' WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  -- B. معالجة كود الخصم الذري إن وُجد
  IF p_coupon_code != '' THEN
    SELECT * INTO v_coupon
    FROM badra_core.discount_codes
    WHERE code = UPPER(TRIM(p_coupon_code))
      AND is_active = true
      AND (expires_at IS NULL OR expires_at > now())
    FOR UPDATE;

    IF NOT FOUND THEN
      RETURN jsonb_build_object('success', false, 'error', 'كود الخصم غير صحيح أو منتهي');
    END IF;

    IF v_coupon.used_at IS NOT NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'كود الخصم مستخدم مسبقاً');
    END IF;

    IF p_amount < v_coupon.min_order_amount THEN
      RETURN jsonb_build_object('success', false, 'error',
        'الحد الأدنى لاستخدام هذا الكود هو ' || v_coupon.min_order_amount::TEXT || ' ر.ي');
    END IF;

    IF v_coupon.discount_percent > 0 THEN
      v_discount := ROUND((p_amount * v_coupon.discount_percent / 100.0), 0);
      IF v_coupon.max_discount > 0 AND v_discount > v_coupon.max_discount THEN
        v_discount := v_coupon.max_discount;
      END IF;
    ELSIF v_coupon.discount_amount > 0 THEN
      v_discount := v_coupon.discount_amount;
    END IF;

    IF v_discount >= p_amount THEN
      v_discount := p_amount - 1;
    END IF;

    UPDATE badra_core.discount_codes
    SET used_at        = now(),
        used_by        = p_user_id,
        used_device_id = p_device_id,
        used_order_ref = p_order_ref
    WHERE id = v_coupon.id AND used_at IS NULL;

    GET DIAGNOSTICS v_updated = ROW_COUNT;
    IF v_updated = 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'تم استخدام كود الخصم في عملية أخرى');
    END IF;

    v_notes := 'خصم: ' || v_discount::TEXT || ' ر.ي 🔥';
  END IF;

  -- C. حساب المبلغ النهائي
  v_final_amount := p_amount - v_discount;

  -- D. قفل وفحص رصيد المستخدم
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  IF v_profile.balance < v_final_amount THEN
    IF v_updated = 1 THEN
      UPDATE badra_core.discount_codes
      SET used_at = NULL, used_by = NULL, used_device_id = NULL, used_order_ref = NULL
      WHERE id = v_coupon.id;
    END IF;
    RETURN jsonb_build_object(
      'success', false, 'error', 'الرصيد غير كاف',
      'balance', v_profile.balance, 'required', v_final_amount
    );
  END IF;

  -- E. خصم الرصيد + تسجيل المعاملة
  UPDATE badra_core.profiles
  SET balance = balance - v_final_amount, updated_at = now()
  WHERE user_id = p_user_id;

  SELECT name INTO v_merchant_name FROM badra_core.merchants WHERE id = p_merchant_id;

  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store,
    debtor, creditor
  ) VALUES (
    p_user_id, 0, v_final_amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed', now(),
    v_notes,                  -- يحوي فقط تفاصيل الخصم إن وجد بدون تكرار رقم الطلب
    p_order_ref,
    COALESCE(v_merchant_name, ''),
    v_profile.name,
    v_merchant_name
  ) RETURNING id INTO v_tx_id;

  UPDATE badra_core.payment_requests
  SET status = 'approved', approved_at = now(), tx_id = v_tx_id
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success',         true,
    'transaction_id',  v_tx_id,
    'new_balance',     v_profile.balance - v_final_amount,
    'original_amount', p_amount,
    'discount',        v_discount,
    'final_amount',    v_final_amount,
    'coupon_applied',  v_discount > 0
  );
END;
$$;


-- 5. تحديث دالة admin_manual_deposit: وضع رقم السند في ref والملاحظات نظيفة
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
SET search_path = badra_core, public, extensions
AS $$
DECLARE
    v_admin_id UUID;
    v_profile_id UUID;
    v_user_id UUID;
    v_old_balance NUMERIC;
    v_admin_name TEXT;
    v_deposit_id UUID;
    v_tx_id UUID;
    v_clean_receipt TEXT;
    v_clean_phone TEXT;
    v_clean_wallet TEXT;
    v_clean_notes TEXT;
    v_last_deposit TIMESTAMPTZ;
    v_remaining_seconds INT;
    v_remaining_hours INT;
    v_remaining_minutes INT;
BEGIN
    -- 1. التحقق الصارم من هوية الأدمن
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN RAISE EXCEPTION 'غير مصرح'; END IF;
    IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN 
        RAISE EXCEPTION 'غير مصرح: لست أدمن'; 
    END IF;

    -- 2. تنظيف المدخلات وتوحيد الأرقام
    v_clean_receipt := upper(trim(COALESCE(p_receipt_number, '')));
    v_clean_phone   := trim(COALESCE(p_phone, ''));
    v_clean_wallet  := trim(COALESCE(p_wallet_id, ''));
    v_clean_notes   := trim(COALESCE(p_notes, ''));

    -- 3. التحقق المالي
    IF p_amount IS NULL OR p_amount < 500 THEN RAISE EXCEPTION 'الحد الأدنى 500 ريال';
    ELSIF p_amount > 250000 THEN RAISE EXCEPTION 'الحد الأقصى 250,000 ريال'; END IF;

    -- 4. فحص قائمة البنوك المعتمدة
    IF p_bank_name NOT IN ('العمقي','الكرايمي','القطيبي','البسيري') THEN 
        RAISE EXCEPTION 'بنك غير صحيح'; 
    END IF;

    -- 5. فحص إلزامية وصلاحية رقم السند وحظر القيم الوهمية
    IF v_clean_receipt IS NULL OR v_clean_receipt = '' OR length(v_clean_receipt) < 4 OR length(v_clean_receipt) > 40 THEN
        RAISE EXCEPTION 'رقم السند / الإيصال البنكي إجباري ومطلوب (بين 4 و 40 خانة)';
    END IF;

    IF v_clean_receipt IN ('0000','00000','000000','1111','1234','12345','TEST','NONE','NULL','N/A') THEN
        RAISE EXCEPTION 'رقم السند المدخل وهمي وغير مقبول، يرجى كتابة رقم السند البنكي الفعلي';
    END IF;

    -- 6. القفل الذري على السند لمنع التكرار
    PERFORM pg_advisory_xact_lock(hashtext('receipt:' || p_bank_name || ':' || v_clean_receipt));

    -- 7. فحص عدم تكرار السند لنفس البنك
    IF EXISTS (
        SELECT 1 FROM badra_core.deposit_requests
        WHERE bank_name = p_bank_name AND upper(receipt_number) = v_clean_receipt
    ) THEN
        RAISE EXCEPTION 'رقم السند البنكي (%) مسجل مسبقاً لدى بنك (%)! تم إلغاء العملية فوراً لمنع تكرار الإيداع', v_clean_receipt, p_bank_name;
    END IF;

    -- 8. جلب اسم الأدمن
    SELECT name INTO v_admin_name FROM badra_core.profiles WHERE user_id = v_admin_id LIMIT 1;
    IF v_admin_name IS NULL THEN v_admin_name := 'أدمن'; END IF;

    -- 9. قفل صف العميل للتحقق
    SELECT id, user_id, balance INTO v_profile_id, v_user_id, v_old_balance
    FROM badra_core.profiles
    WHERE wallet_id = v_clean_wallet AND phone = v_clean_phone AND name = p_name
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'المستخدم غير موجود'; END IF;

    -- 10. قفل فترة التهدئة (12 ساعة)
    PERFORM pg_advisory_xact_lock(hashtext('user_cooldown:' || v_user_id::text));

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

    -- 11. تحديث رصيد العميل
    UPDATE badra_core.profiles SET balance = balance + p_amount, updated_at = now()
    WHERE id = v_profile_id;

    -- 12. تسجيل طلب الإيداع
    INSERT INTO badra_core.deposit_requests(user_id, amount, bank_name, receipt_number, notes, admin_id, admin_name)
    VALUES(v_user_id, p_amount, p_bank_name, v_clean_receipt, NULLIF(v_clean_notes, ''), v_admin_id, v_admin_name)
    RETURNING id INTO v_deposit_id;

    -- 13. تسجيل المعاملة في transactions_v2:
    -- رقم السند يوضع في ref، والملاحظات تحتوي فقط على ملاحظات الأدمن إن وجدت
    INSERT INTO badra_core.transactions_v2(
        user_id, is_in, amount, title, date, status, notes, 
        debtor, creditor, deposit_request_id, ref
    )
    VALUES(
        v_user_id, 1, p_amount, 
        'إيداع عبر الأدمن - ' || p_bank_name, 
        now(), 'completed', 
        NULLIF(v_clean_notes, ''),
        p_bank_name,
        p_name,
        v_deposit_id,
        v_clean_receipt        -- السند البنكي هو المرجع الأساسي للإيداع
    )
    RETURNING id INTO v_tx_id;

    -- 14. تحديث ملخص الأرصدة للنظام
    UPDATE badra_core.balance_summary
    SET total_received = total_received + p_amount, updated_at = now()
    WHERE id = (SELECT id FROM badra_core.balance_summary LIMIT 1);

    -- 15. تسجيل التدقيق
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
        'transaction_id', v_tx_id
    );
END;
$$;


-- 6. ترقية دالتي get_my_transactions_fast و get_my_transactions_paginated
-- لتوليد short_ref فائق السرعة من السيرفر مباشرة وتقليل حجم الـ Payload

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
      'ref', COALESCE(t.ref, ''),
      'short_ref', CASE 
        WHEN length(regexp_replace(COALESCE(NULLIF(t.ref, ''), t.id::text), '\D', '', 'g')) >= 4 THEN
          RIGHT(regexp_replace(COALESCE(NULLIF(t.ref, ''), t.id::text), '\D', '', 'g'), 4)
        WHEN t.ref IS NOT NULL AND t.ref != '' THEN
          t.ref
        ELSE
          RIGHT(t.id::text, 4)
      END,
      'store', COALESCE(t.store, ''),
      'title', COALESCE(t.title, ''),
      'amount', t.amount,
      'date', t.date,
      'status', COALESCE(t.status, 'completed'),
      'debtor', COALESCE(t.debtor, ''),
      'creditor', COALESCE(t.creditor, ''),
      'notes', COALESCE(t.notes, '')
    ) ORDER BY t.date DESC
  ) INTO v_result
  FROM badra_core.transactions_v2 t
  WHERE t.user_id = auth.uid();

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;

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
      'ref', COALESCE(t.ref, ''),
      'short_ref', CASE 
        WHEN length(regexp_replace(COALESCE(NULLIF(t.ref, ''), t.id::text), '\D', '', 'g')) >= 4 THEN
          RIGHT(regexp_replace(COALESCE(NULLIF(t.ref, ''), t.id::text), '\D', '', 'g'), 4)
        WHEN t.ref IS NOT NULL AND t.ref != '' THEN
          t.ref
        ELSE
          RIGHT(t.id::text, 4)
      END,
      'store', COALESCE(t.store, ''),
      'title', COALESCE(t.title, ''),
      'amount', t.amount,
      'date', t.date,
      'status', COALESCE(t.status, 'completed'),
      'debtor', COALESCE(t.debtor, ''),
      'creditor', COALESCE(t.creditor, ''),
      'notes', COALESCE(t.notes, '')
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

-- منح الصلاحيات
GRANT EXECUTE ON FUNCTION badra_core.get_my_transactions_fast() TO authenticated;
GRANT EXECUTE ON FUNCTION badra_core.get_my_transactions_paginated(integer, integer) TO authenticated;
