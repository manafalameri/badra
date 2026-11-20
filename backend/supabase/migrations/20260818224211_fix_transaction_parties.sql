-- ============================================================
-- بذرة (Badra) — Fix Transaction Parties (debtor/creditor)
-- إصلاح حقلي المدين والدائن في المعاملات
-- ============================================================

-- 1. تحديث دالة admin_manual_deposit لإضافة debtor و creditor
-- الإيداع: المدين = اسم البنك (العمقي/الكرايمي/القطيبي/البسيري)، الدائن = اسم الزبون
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

    -- بناء ملاحظات كاملة تتضمن رقم الإيصال
    v_notes_full := COALESCE(NULLIF(p_receipt_number, ''), '');
    IF p_notes != '' THEN
        v_notes_full := v_notes_full || COALESCE(NULLIF(v_notes_full, ''), '') || ' | ' || p_notes;
    END IF;

    INSERT INTO badra_core.deposit_requests(user_id, amount, bank_name, receipt_number, notes, admin_id, admin_name)
    VALUES(v_user_id, p_amount, p_bank_name, NULLIF(p_receipt_number, ''), NULLIF(p_notes, ''), v_admin_id, v_admin_name)
    RETURNING id INTO v_deposit_id;

    -- إدراج المعاملة مع debtor (البنك) و creditor (الزبون)
    INSERT INTO badra_core.transactions_v2(
        user_id, is_in, amount, title, date, status, notes, 
        debtor, creditor, deposit_request_id
    )
    VALUES(
        v_user_id, 1, p_amount, 
        'إيداع عبر الأدمن - ' || p_bank_name, 
        now(), 'completed', 
        NULLIF(v_notes_full, ''),
        p_bank_name,          -- المدين: البنك/الطرف المرسل
        p_name,               -- الدائن: الزبون المستفيد
        v_deposit_id
    )
    RETURNING id INTO v_tx_id;

    UPDATE badra_core.balance_summary
    SET total_received = total_received + p_amount, updated_at = now()
    WHERE id = (SELECT id FROM badra_core.balance_summary LIMIT 1);

    INSERT INTO badra_core.audit_log(action, table_name, record_id, old_values, new_values, admin_id, admin_name)
    VALUES('deposit', 'profiles', v_profile_id,
           jsonb_build_object('balance', v_old_balance),
           jsonb_build_object('balance', v_old_balance + p_amount, 'deposit_id', v_deposit_id, 'transaction_id', v_tx_id, 'amount', p_amount, 'bank', p_bank_name, 'debtor', p_bank_name, 'creditor', p_name),
           v_admin_id, v_admin_name);

    RETURN jsonb_build_object('success', true, 'amount', p_amount, 'user_id', v_user_id, 'old_balance', v_old_balance, 'new_balance', v_old_balance + p_amount, 'deposit_id', v_deposit_id, 'transaction_id', v_tx_id);
END;
$$;

-- 2. تحديث دالة approve_payment_request_v2 لإضافة debtor و creditor
-- السحب/الدفع: المدين = اسم الزبون، الدائن = اسم المتجر/التاجر
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

  -- إدراج المعاملة مع debtor (الزبون) و creditor (التاجر)
  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store,
    debtor, creditor
  ) VALUES (
    v_user_id, 0, v_request.amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed', now(),
    'order_ref: ' || v_request.order_ref,
    v_request.order_ref,
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

-- 3. تحديث دالة execute_approved_payment (المستخدمة من Edge Function approve-payment-signature)
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

  -- Deduct balance
  v_new_balance := v_profile.balance - p_amount;

  UPDATE badra_core.profiles
  SET balance = v_new_balance, updated_at = now()
  WHERE user_id = p_user_id;

  -- Get merchant name
  SELECT name INTO v_merchant_name
  FROM badra_core.merchants
  WHERE id = p_merchant_id;

  -- إدراج المعاملة مع debtor (الزبون) و creditor (التاجر)
  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store,
    debtor, creditor
  ) VALUES (
    p_user_id, 0, p_amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed', now(),
    'order_ref: ' || p_order_ref,
    p_order_ref,
    COALESCE(v_merchant_name, ''),
    v_profile.name,           -- المدين: الزبون الدافع
    v_merchant_name           -- الدائن: التاجر المستلم
  ) RETURNING id INTO v_tx_id;

  -- Update payment request
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

-- 4. Backfill البيانات الموجودة - تعبئة debtor/creditor للمعاملات القديمة
DO $$
DECLARE
    v_tx RECORD;
BEGIN
    -- للإيداعات: creditor = اسم الزبون، debtor = اسم البنك من deposit_requests
    UPDATE badra_core.transactions_v2 t
    SET 
        creditor = p.name,
        debtor = COALESCE(dr.bank_name, 'بنك')
    FROM badra_core.profiles p
    LEFT JOIN badra_core.deposit_requests dr ON dr.id = t.deposit_request_id
    WHERE t.is_in = 1
      AND t.user_id = p.user_id
      AND (t.debtor = '' OR t.creditor = '')
      AND t.deposit_request_id IS NOT NULL;

    -- للإيداعات بدون deposit_request_id: creditor = اسم الزبون، debtor = 'إيداع'
    UPDATE badra_core.transactions_v2 t
    SET 
        creditor = p.name,
        debtor = 'إيداع'
    FROM badra_core.profiles p
    WHERE t.is_in = 1
      AND t.user_id = p.user_id
      AND (t.debtor = '' OR t.creditor = '')
      AND t.deposit_request_id IS NULL;

    -- للسحوبات/المدفوعات: debtor = اسم الزبون، creditor = store (اسم المتجر)
    UPDATE badra_core.transactions_v2 t
    SET 
        debtor = p.name,
        creditor = COALESCE(NULLIF(t.store, ''), 'متجر')
    FROM badra_core.profiles p
    WHERE t.is_in = 0
      AND t.user_id = p.user_id
      AND (t.debtor = '' OR t.creditor = '');
END;
$$;

-- ============================================================
-- DONE! Transaction parties are now properly recorded.
-- ============================================================