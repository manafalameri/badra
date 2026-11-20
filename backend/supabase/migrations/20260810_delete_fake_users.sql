-- ============================================================
-- بذرة (Badra) — حذف الحسابات الوهمية فقط (تجارب فاشلة)
-- ============================================================
-- ⚠️ تعليمات الأمان قبل التنفيذ:
--   1. افتح هذا الملف في Supabase → SQL Editor (أو supabase db push)
--   2. عدّل قائمة الأرقام في الأسفل (قسم ✏️)
--   3. شغّل "المعاينة" أولاً (القسم 0) واقرأ الصفوف المعروضة — هي فقط ما سيُحذف
--   4. ثم شغّل باقي الأقسام
-- ملاحظات:
--   - الأدمن محمي برمجياً: لا يمكن حذفه من هذا السكربت نهائياً
--   - الباقي (المتاجر merchants, إعدادات البنوك deposit_config, سجل المراجعة
--     audit_log) لن يُمسّ — ليس لها علاقة بالحسابات
-- ============================================================

-- ============================================================
-- ✏️✏️✏️ قائمة الحسابات الوهمية المطلوب حذفها (رقم الهاتف) ✏️✏️✏️
-- اكتب الأرقام كما تظهر في لوحة الأدمن، مع أو بدون +967 — يطابق الاثنين:
CREATE TEMP TABLE fake_accounts (phone TEXT PRIMARY KEY);
INSERT INTO fake_accounts (phone) VALUES
  ('000000000'),          -- ← ضع هنا رقم الحساب الوهمي الأول
  ('+967000000000');      -- ← ضع هنا رقم الحساب الوهمي الثاني (احذف السطر الزائد)
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 0) معاينة: شغّل هذا القسم أولاً واقرأ الناتج — هذه هي الصفوف
--    الوحيدة التي ستُحذف (الاسم + الرقم + المحفظة + الرصيد)
-- ────────────────────────────────────────────────────────────
SELECT p.phone, p.name, p.wallet_id, p.balance, p.is_active,
       (SELECT count(*) FROM badra_core.transactions_v2 t WHERE t.user_id = p.user_id) AS tx_count
FROM badra_core.profiles p
JOIN fake_accounts f ON replace(p.phone, '+', '') = replace(f.phone, '+', '');

-- ────────────────────────────────────────────────────────────
-- 1) حذف طلبات الدفع المعلقة (الجدول ليس فيه ON DELETE CASCADE)
-- ────────────────────────────────────────────────────────────
DELETE FROM badra_core.payment_requests pr
USING badra_core.profiles p, fake_accounts f
WHERE pr.user_id = p.user_id
  AND replace(p.phone, '+', '') = replace(f.phone, '+', '');

-- ────────────────────────────────────────────────────────────
-- 2) حذف طلبات الإيداع (الجدول ليس فيه ON DELETE CASCADE)
-- ────────────────────────────────────────────────────────────
DELETE FROM badra_core.deposit_requests dr
USING badra_core.profiles p, fake_accounts f
WHERE dr.user_id = p.user_id
  AND replace(p.phone, '+', '') = replace(f.phone, '+', '');

-- ────────────────────────────────────────────────────────────
-- 3) حذف الطلبات المعلقة pending_users لهذه الأرقام (لا FK)
-- ────────────────────────────────────────────────────────────
DELETE FROM badra_core.pending_users pu
USING fake_accounts f
WHERE replace(pu.phone, '+', '') = replace(f.phone, '+', '');

-- ────────────────────────────────────────────────────────────
-- 4) الحذف الأساسي: الحساب من auth.users
--    (الحراسة: الأدمن محمي — لن يُحذف حتى لو وُضع رقمه بالخطأ)
--    يتساقط تلقائياً (CASCADE): profiles, transactions, transactions_v2,
--    user_devices, bank_accounts, activation_codes, challenge_attempts,
--    security_events
-- ────────────────────────────────────────────────────────────
DELETE FROM auth.users u
USING badra_core.profiles p, fake_accounts f
WHERE u.id = p.user_id
  AND replace(p.phone, '+', '') = replace(f.phone, '+', '')
  AND NOT EXISTS (SELECT 1 FROM badra_core.admins a WHERE a.user_id = u.id);

-- ────────────────────────────────────────────────────────────
-- 5) تنظيف محاولات التحقق من الهوية للأرقام المحذوفة
-- ────────────────────────────────────────────────────────────
DELETE FROM badra_core.identity_verify_attempts iv
USING fake_accounts f
WHERE replace(iv.phone, '+', '') = replace(f.phone, '+', '');

-- ────────────────────────────────────────────────────────────
-- 6) إعادة حساب إجماليات balance_summary بعد الحذف
--    (حتى لا تبقى أرقام الإيداعات الوهمية داخل المجموع)
-- ────────────────────────────────────────────────────────────
DELETE FROM badra_core.balance_summary;
INSERT INTO badra_core.balance_summary (total_received, total_distributed, updated_at)
SELECT
    COALESCE(SUM(amount) FILTER (WHERE is_in = 1), 0),
    COALESCE(SUM(amount) FILTER (WHERE is_in = 0), 0),
    now()
FROM badra_core.transactions_v2;

-- ────────────────────────────────────────────────────────────
-- 7) تقرير نهائي: أرقام الحسابات التي حُذفت فعلاً
-- ────────────────────────────────────────────────────────────
SELECT f.phone,
       CASE WHEN EXISTS (
         SELECT 1 FROM badra_core.profiles p
         WHERE replace(p.phone, '+', '') = replace(f.phone, '+', '')
       ) THEN 'لم يُحذف — تحقق من الرقم' ELSE 'تم الحذف ✔' END AS status
FROM fake_accounts f;
