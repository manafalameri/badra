-- =============================================================================
-- بذرة (Badra) — سكربت التطهير الشامل لحسابات وتجارب التطوير قبل الإطلاق الرسمي
-- Production Launch Clean Wipe: Removes all 12 test users and all test data
-- Preserves Admin: 74170cdd-4ee4-43f6-bc8e-44e9e3bc2ee3 (967730975496)
-- Preserves Merchants (Taleed) and Bank Configuration (deposit_config)
-- =============================================================================

BEGIN;

-- 🛡️ 1. تثبيت وتأكيد درع الحماية لحساب الأدمن الحقيقي
CREATE TEMP TABLE keep_admin AS
SELECT '74170cdd-4ee4-43f6-bc8e-44e9e3bc2ee3'::UUID AS user_id;

-- التحقق الأمني الإلزامي قبل المساس بأي بيانات
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM keep_admin) THEN
    RAISE EXCEPTION 'خطأ أمني فادح: لم يتم العثور على حساب الأدمن! تم إيقاف العملية فوراً.';
  END IF;
END $$;

-- 2. حذف المعاملات المالية التجريبية بالكامل
DELETE FROM badra_core.transactions_v2;

-- 3. حذف طلبات الدفع التجريبية الواردة من المتاجر
DELETE FROM badra_core.payment_requests;

-- 4. حذف طلبات الإيداع البنكية التجريبية
DELETE FROM badra_core.deposit_requests;

-- 5. حذف طلبات التسجيل المعلقة ومحاولات التحقق
DELETE FROM badra_core.pending_users;
DELETE FROM badra_core.identity_verify_attempts;

-- 6. حذف أكواد التفعيل لغير الأدمن
DELETE FROM badra_core.activation_codes
WHERE user_id NOT IN (SELECT user_id FROM keep_admin);

-- 7. تصفير سجل محاولات تسجيل الدخول والأكواد الفاشلة
TRUNCATE TABLE badra_core.security_attempts_v2;
DELETE FROM badra_core.coupon_attempts;

-- 8. حذف الأجهزة المسجلة لغير الأدمن (الإبقاء على جهاز الأدمن لتجنب القفل)
DELETE FROM badra_core.user_devices
WHERE user_id NOT IN (SELECT user_id FROM keep_admin);

-- 9. 🔥 الحذف الجذري من auth.users لجميع المستخدمين التجريبيين عدا الأدمن
-- يتساقط تلقائياً بالـ CASCADE: profiles, auth.identities, auth.sessions, auth.refresh_tokens
DELETE FROM auth.users
WHERE id NOT IN (SELECT user_id FROM keep_admin);

-- 10. تصفير وإعادة بناء ملخص الرصيد الإجمالي
DELETE FROM badra_core.balance_summary;
INSERT INTO badra_core.balance_summary (total_received, total_distributed, updated_at)
VALUES (0, 0, now());

-- 11. تصفير رصيد محفظة الأدمن للبدء من الصفر
UPDATE badra_core.profiles
SET balance = 0
WHERE user_id IN (SELECT user_id FROM keep_admin);

COMMIT;
