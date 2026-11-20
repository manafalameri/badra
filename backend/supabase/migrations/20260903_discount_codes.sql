-- ============================================================
-- Discount Codes System — badra_core
-- Zero-Trust: no client can read/modify this table directly.
-- All operations go through SECURITY DEFINER RPCs.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. جدول الأكواد الرئيسي
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS badra_core.discount_codes (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- الكود مخزن كـ SHA-256 hex فقط — لا نص صريح أبداً
  code_hash      TEXT NOT NULL UNIQUE,

  -- نوع الخصم وقيمته
  discount_type  TEXT NOT NULL CHECK (discount_type IN ('percent', 'fixed')),
  discount_value NUMERIC(10,2) NOT NULL CHECK (discount_value > 0),
  max_discount   NUMERIC(10,2),
  min_order      NUMERIC(10,2) NOT NULL DEFAULT 0,

  -- صلاحية الكود
  expires_at     TIMESTAMPTZ NOT NULL,
  is_active      BOOLEAN NOT NULL DEFAULT true,

  -- تتبع الاستهلاك (يُعبأ ذرياً وقت الاستخدام)
  used_at        TIMESTAMPTZ,
  used_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  used_device_id TEXT,
  used_order_ref TEXT,

  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_discount_codes_hash
  ON badra_core.discount_codes (code_hash);

CREATE INDEX IF NOT EXISTS idx_discount_codes_active
  ON badra_core.discount_codes (is_active, expires_at)
  WHERE is_active = true AND used_at IS NULL;

ALTER TABLE badra_core.discount_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON badra_core.discount_codes FROM anon, authenticated, public;

-- ────────────────────────────────────────────────────────────
-- 2. جدول محاولات الكوبون الفاشلة
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS badra_core.coupon_attempts (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  device_id    TEXT NOT NULL DEFAULT '',
  attempts     INT NOT NULL DEFAULT 1,
  locked_until TIMESTAMPTZ,
  failed_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_coupon_attempts_user_device
  ON badra_core.coupon_attempts (user_id, device_id);

ALTER TABLE badra_core.coupon_attempts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON badra_core.coupon_attempts FROM anon, authenticated, public;

-- ────────────────────────────────────────────────────────────
-- 3. الدالة الوحيدة للاستهلاك: redeem_coupon_and_pay
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION badra_core.redeem_coupon_and_pay(
  p_user_id     UUID,
  p_request_id  UUID,
  p_amount      NUMERIC,
  p_merchant_id UUID,
  p_order_ref   TEXT,
  p_coupon_code TEXT    DEFAULT NULL,
  p_device_id   TEXT    DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_profile       badra_core.profiles%ROWTYPE;
  v_request       badra_core.payment_requests%ROWTYPE;
  v_coupon        badra_core.discount_codes%ROWTYPE;
  v_merchant_name TEXT;
  v_final_amount  NUMERIC;
  v_discount      NUMERIC := 0;
  v_code_hash     TEXT;
  v_tx_id         UUID;
  v_updated       INT;
  v_attempts_row  badra_core.coupon_attempts%ROWTYPE;
BEGIN
  -- A. قفل وتحقق من طلب الدفع
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_request.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب تم معالجته مسبقاً');
  END IF;

  IF v_request.expires_at <= now() THEN
    UPDATE badra_core.payment_requests SET status = 'expired' WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  IF v_request.user_id != p_user_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب لا يخصك');
  END IF;

  -- B. معالجة الكوبون (إذا أُدخل)
  IF p_coupon_code IS NOT NULL AND length(trim(p_coupon_code)) > 0 THEN

    -- B1. تحقق من حظر المحاولات
    SELECT * INTO v_attempts_row
    FROM badra_core.coupon_attempts
    WHERE user_id = p_user_id AND device_id = p_device_id;

    IF v_attempts_row.locked_until IS NOT NULL AND v_attempts_row.locked_until > now() THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'الكود غير صالح أو غير متاح',
        'coupon_locked', true,
        'retry_after', v_attempts_row.locked_until
      );
    END IF;

    -- B2. Hash الكود
    v_code_hash := encode(extensions.digest(trim(p_coupon_code), 'sha256'), 'hex');

    -- B3. الاستهلاك الذري
    UPDATE badra_core.discount_codes
    SET
      used_at        = now(),
      used_by        = p_user_id,
      used_device_id = p_device_id,
      used_order_ref = p_order_ref
    WHERE
      code_hash  = v_code_hash
      AND is_active  = true
      AND used_at    IS NULL
      AND expires_at > now()
      AND (min_order = 0 OR p_amount >= min_order)
    RETURNING * INTO v_coupon;

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    IF v_updated = 0 THEN
      -- B4. سجّل محاولة فاشلة
      INSERT INTO badra_core.coupon_attempts (user_id, device_id, attempts, locked_until, failed_at)
      VALUES (p_user_id, p_device_id, 1, NULL, now())
      ON CONFLICT (user_id, device_id) DO UPDATE
        SET
          attempts     = coupon_attempts.attempts + 1,
          failed_at    = now(),
          locked_until = CASE
            WHEN coupon_attempts.attempts + 1 >= 3 THEN now() + interval '30 minutes'
            ELSE NULL
          END;

      RETURN jsonb_build_object('success', false, 'error', 'الكود غير صالح أو غير متاح');
    END IF;

    -- B5. حساب الخصم في السيرفر
    IF v_coupon.discount_type = 'percent' THEN
      v_discount := ROUND(p_amount * v_coupon.discount_value / 100.0, 2);
      IF v_coupon.max_discount IS NOT NULL THEN
        v_discount := LEAST(v_discount, v_coupon.max_discount);
      END IF;
    ELSE
      v_discount := LEAST(v_coupon.discount_value, p_amount);
    END IF;

    -- مسح المحاولات الفاشلة عند نجاح الكود
    DELETE FROM badra_core.coupon_attempts
    WHERE user_id = p_user_id AND device_id = p_device_id;

  END IF;

  -- C. المبلغ النهائي
  v_final_amount := GREATEST(p_amount - v_discount, 0);

  -- D. قفل وتحقق من رصيد المستخدم
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  IF v_profile.balance < v_final_amount THEN
    -- تراجع عن استهلاك الكوبون إذا الرصيد غير كافٍ
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

  -- E. خصم الرصيد + سجل المعاملة + تحديث الطلب
  UPDATE badra_core.profiles
  SET balance = balance - v_final_amount, updated_at = now()
  WHERE user_id = p_user_id;

  SELECT name INTO v_merchant_name FROM badra_core.merchants WHERE id = p_merchant_id;

  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store
  ) VALUES (
    p_user_id, 0, v_final_amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed', now(),
    CASE
      WHEN v_discount > 0 THEN 'خصم: ' || v_discount::TEXT || ' ر — order: ' || p_order_ref
      ELSE 'order: ' || p_order_ref
    END,
    p_order_ref,
    COALESCE(v_merchant_name, '')
  ) RETURNING id INTO v_tx_id;

  UPDATE badra_core.payment_requests
  SET status = 'approved', approved_at = now(), tx_id = v_tx_id
  WHERE id = p_request_id;

  -- F. الإرجاع
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

REVOKE EXECUTE ON FUNCTION badra_core.redeem_coupon_and_pay FROM anon, authenticated, public;
GRANT EXECUTE ON FUNCTION badra_core.redeem_coupon_and_pay TO service_role;

-- ────────────────────────────────────────────────────────────
-- 4. دالة إنشاء الأكواد — للإدارة فقط
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION badra_core.admin_create_discount_code(
  p_code         TEXT,
  p_type         TEXT,
  p_value        NUMERIC,
  p_max_discount NUMERIC      DEFAULT NULL,
  p_min_order    NUMERIC      DEFAULT 0,
  p_expires_at   TIMESTAMPTZ  DEFAULT now() + interval '30 days'
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_type NOT IN ('percent', 'fixed') THEN
    RETURN jsonb_build_object('success', false, 'error', 'نوع الخصم غير صالح');
  END IF;

  IF p_value <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'قيمة الخصم يجب أن تكون أكبر من صفر');
  END IF;

  IF p_type = 'percent' AND p_value > 100 THEN
    RETURN jsonb_build_object('success', false, 'error', 'نسبة الخصم لا يمكن أن تتجاوز 100%');
  END IF;

  INSERT INTO badra_core.discount_codes (
    code_hash, discount_type, discount_value, max_discount, min_order, expires_at
  ) VALUES (
    encode(extensions.digest(trim(p_code), 'sha256'), 'hex'),
    p_type, p_value, p_max_discount, COALESCE(p_min_order, 0), p_expires_at
  );

  RETURN jsonb_build_object('success', true, 'message', 'تم إنشاء الكود بنجاح');
EXCEPTION
  WHEN unique_violation THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الكود موجود مسبقاً');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', 'خطأ داخلي: ' || SQLERRM);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.admin_create_discount_code FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.admin_create_discount_code TO authenticated;

-- ────────────────────────────────────────────────────────────
-- 5. دالة تعطيل الكود — للإدارة فقط
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION badra_core.admin_disable_discount_code(
  p_code TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE v_updated INT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  UPDATE badra_core.discount_codes
  SET is_active = false
  WHERE code_hash = encode(extensions.digest(trim(p_code), 'sha256'), 'hex')
    AND used_at IS NULL;

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'الكود غير موجود أو تم استخدامه مسبقاً');
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'تم تعطيل الكود');
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.admin_disable_discount_code FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.admin_disable_discount_code TO authenticated;
