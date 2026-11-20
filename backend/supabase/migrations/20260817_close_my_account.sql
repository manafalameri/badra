-- ============================================================
-- بذرة (Badra) — إغلاق الحساب (Account Closure)
-- 2026-08-17
--
-- الأمان والتصميم:
--   1. لا يمكن إغلاق الحساب إلا إذا كان الرصيد صفراً (حماية أموال المستخدم).
--   2. التحقق من كود الأمان (bcrypt) قبل التنفيذ.
--   3. تُحذف البيانات الشخصية والقابلة للتعريف (الأجهزة، الحسابات البنكية،
--      أكواد التفعيل، الجلسات).
--   4. تُحفظ سجلات المعاملات المالية (transactions_v2) كما يقتضي الالتزام
--      القانوني بمكافحة غسل الأموال — مسموح به وفق سياسة Google Play
--      للإفصاح المالي.
-- ============================================================

-- ============================================================
-- 1. جدول طلبات إغلاق الحساب (سجل التدقيق)
-- ============================================================
CREATE TABLE IF NOT EXISTS badra_core.account_closure_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id),
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'closed', 'cancelled')),
  security_code_verified BOOLEAN DEFAULT false,
  balance_at_request NUMERIC DEFAULT 0,
  closed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now() NOT NULL
);
ALTER TABLE badra_core.account_closure_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS admin_only_closure_requests ON badra_core.account_closure_requests;
CREATE POLICY admin_only_closure_requests ON badra_core.account_closure_requests
  FOR ALL USING (badra_core.is_admin_uid(auth.uid()));

CREATE INDEX IF NOT EXISTS idx_closure_requests_user_id
  ON badra_core.account_closure_requests(user_id);

-- ============================================================
-- 2. RPC: close_my_account — إغلاق الحساب (يتطلب مصادقة + كود أمان)
-- ============================================================
CREATE OR REPLACE FUNCTION badra_core.close_my_account(
  p_security_code TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_profile badra_core.profiles%ROWTYPE;
  v_stored_hash TEXT;
  v_balance NUMERIC;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الحساب غير موجود');
  END IF;

  v_balance := COALESCE(v_profile.balance, 0);

  -- شرط حماية الأموال: الرصيد يجب أن يكون صفراً
  IF v_balance <> 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'لا يمكن إغلاق الحساب والرصيد غير صفر. الرصيد الحالي: ' || v_balance || ' ريال.',
      'balance', v_balance,
      'reason', 'balance_not_zero'
    );
  END IF;

  -- التحقق من كود الأمان
  SELECT security_code INTO v_stored_hash
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  IF v_stored_hash IS NULL OR v_stored_hash = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين كود الأمان');
  END IF;

  IF v_stored_hash NOT LIKE '$2%' THEN
    RETURN jsonb_build_object('success', false, 'error', 'تنسيق كود الأمان غير صالح');
  END IF;

  IF v_stored_hash != crypt(p_security_code, v_stored_hash) THEN
    RETURN jsonb_build_object('success', false, 'error', 'كود الأمان غير صحيح', 'reason', 'bad_security_code');
  END IF;

  -- تسجيل طلب الإغلاق
  INSERT INTO badra_core.account_closure_requests (
    user_id, status, security_code_verified, balance_at_request
  ) VALUES (
    v_user_id, 'closed', true, v_balance
  );

  -- حذف البيانات الشخصية / القابلة للتعريف
  DELETE FROM badra_core.user_devices WHERE user_id = v_user_id;
  DELETE FROM badra_core.bank_accounts WHERE user_id = v_user_id;
  DELETE FROM badra_core.activation_codes WHERE user_id = v_user_id;
  DELETE FROM badra_core.pending_users WHERE phone = v_profile.phone;

  -- إلغاء طلبات الدفع المعلقة
  UPDATE badra_core.payment_requests
  SET status = 'expired'
  WHERE user_id = v_user_id AND status = 'pending';

  -- تجريد البيانات الشخصية من البروفايل (حذف PII)
  UPDATE badra_core.profiles
  SET name = 'حساب محذوف',
      phone = 'deleted_' || replace(v_user_id::text, '-', ''),
      is_active = false,
      security_code = NULL,
      updated_at = now()
  WHERE user_id = v_user_id;

  -- ملاحظة: سجلات المعاملات (transactions_v2) تُحفظ كما يقتضي القانون المالي.
  -- لا يتم حذفها هنا.

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم إغلاق الحساب وحذف البيانات الشخصية. تم الاحتفاظ بالسجلات المالية وفقاً للالتزامات القانونية.',
    'closed_at', now()
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.close_my_account FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.close_my_account TO authenticated;

-- ============================================================
-- 3. RPC: cancel_my_closure — إلغاء طلب الإغلاق المعلق (دعم)
-- ============================================================
CREATE OR REPLACE FUNCTION badra_core.cancel_my_closure()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_updated INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  UPDATE badra_core.account_closure_requests
  SET status = 'cancelled'
  WHERE user_id = v_user_id AND status = 'pending';

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يوجد طلب إغلاق معلق');
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'تم إلغاء طلب الإغلاق');
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.cancel_my_closure FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.cancel_my_closure TO authenticated;

-- ============================================================
-- DONE
-- ============================================================