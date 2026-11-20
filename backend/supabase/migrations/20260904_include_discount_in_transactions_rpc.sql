-- ============================================================
-- بذرة (Badra) — إرجاع تفاصيل الخصم والتوفير في دوال السجل
-- Include original_amount and discount_amount in transactions RPCs
-- ============================================================

-- 1. ترقية دالة get_my_transactions_fast لإرجاع original_amount و discount_amount
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
      'original_amount', t.original_amount,
      'discount_amount', t.discount_amount,
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

-- 2. ترقية دالة get_my_transactions_paginated لإرجاع original_amount و discount_amount
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
      'original_amount', t.original_amount,
      'discount_amount', t.discount_amount,
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

-- 3. تحديث دالة redeem_coupon_and_pay لتخزين original_amount و discount_amount دائماً
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

  -- E. خصم الرصيد + تسجيل المعاملة مع حفظ original_amount و discount_amount
  UPDATE badra_core.profiles
  SET balance = balance - v_final_amount, updated_at = now()
  WHERE user_id = p_user_id;

  SELECT name INTO v_merchant_name FROM badra_core.merchants WHERE id = p_merchant_id;

  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store,
    debtor, creditor, original_amount, discount_amount
  ) VALUES (
    p_user_id, 0, v_final_amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed', now(),
    v_notes,
    p_order_ref,
    COALESCE(v_merchant_name, ''),
    v_profile.name,
    v_merchant_name,
    p_amount,
    v_discount
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

-- منح الصلاحيات
GRANT EXECUTE ON FUNCTION badra_core.get_my_transactions_fast() TO anon, authenticated, service_role, supabase_read_only_user;
GRANT EXECUTE ON FUNCTION badra_core.get_my_transactions_paginated(integer, integer) TO anon, authenticated, service_role, supabase_read_only_user;
