-- ============================================================
-- بذرة (Badra) — حذف الحسابات الوهمية/التجريبية بالكامل (43 حساباً)
-- ============================================================
-- ✅ يُبقى: حساب الأدمن (967730975496) + سجل إيداعاته + audit_log
--           + المتاجر (merchants) + إعدادات البنوك (deposit_config)
-- ⚠️ يُحذف: 40 حساباً ذا ملف profile + 3 حسابات يتيمة في auth.users
--           (مناف003 ×2 / مناف444 — بلا ملفات، نفس نمط الاختبار)
-- الآثار الجانبية التلقائية (CASCADE): جلسات، توكنات، أجهزة، عمليات،
-- أكواد تفعيل، محاولات تحدي، هويات
-- ============================================================

BEGIN;

-- ── الحماية المزدوجة: لا يُحذف الأدمن أبداً ──
CREATE TEMP TABLE keep_admin AS
SELECT user_id FROM badra_core.admins;

-- 1) العمليات المالية أولاً (ترتبط بـ deposit_requests عبر FK
--    transactions_v2_deposit_request_id_fkey — فلا تُحذف عمليات الأدمن)
DELETE FROM badra_core.transactions_v2 tv
USING auth.users u
WHERE tv.user_id = u.id
  AND u.id NOT IN (SELECT user_id FROM keep_admin);

-- 2) طلبات الدفع (لا يوجد ON DELETE CASCADE من profiles)
DELETE FROM badra_core.payment_requests pr
USING auth.users u
WHERE pr.user_id = u.id
  AND u.id NOT IN (SELECT user_id FROM keep_admin);

-- 3) طلبات الإيداع الخاصة بالمستخدمين المحذوفين فقط
--    (إيداعات الأدمن لمستخدميها المحذوفين تُحذف لأنها تخص الحسابات الوهمية)
DELETE FROM badra_core.deposit_requests dr
USING auth.users u
WHERE dr.user_id = u.id
  AND u.id NOT IN (SELECT user_id FROM keep_admin);

-- 4) الطلبات المعلقة pending_users (مطابقة بالهاتف، لا FK)
DELETE FROM badra_core.pending_users pu
USING badra_core.profiles p, auth.users u
WHERE replace(pu.phone, '+', '') = replace(p.phone, '+', '')
  AND p.user_id = u.id
  AND u.id NOT IN (SELECT user_id FROM keep_admin);

-- 5) محاولات التحقق من الهوية (مطابقة بالهاتف)
DELETE FROM badra_core.identity_verify_attempts iv
USING badra_core.profiles p, auth.users u
WHERE replace(iv.phone, '+', '') = replace(p.phone, '+', '')
  AND p.user_id = u.id
  AND u.id NOT IN (SELECT user_id FROM keep_admin);

-- 6) أكواد التفعيل (صراحةً — لها CASCADE لكن الحذف المباشر أوضح)
DELETE FROM badra_core.activation_codes ac
USING auth.users u
WHERE ac.user_id = u.id
  AND u.id NOT IN (SELECT user_id FROM keep_admin);

-- 7) الحذف الأساسي: auth.users الكل ما عدا الأدمن
--    يتساقط تلقائياً: profiles، user_devices، challenge_attempts،
--    auth.identities، auth.sessions، auth.refresh_tokens
DELETE FROM auth.users
WHERE id NOT IN (SELECT user_id FROM keep_admin);

-- 8) إعادة بناء إجماليات balance_summary بعد الحذف
DELETE FROM badra_core.balance_summary;
INSERT INTO badra_core.balance_summary (total_received, total_distributed, updated_at)
SELECT
    COALESCE(SUM(amount) FILTER (WHERE is_in = 1), 0),
    COALESCE(SUM(amount) FILTER (WHERE is_in = 0), 0),
    now()
FROM badra_core.transactions_v2;

COMMIT;