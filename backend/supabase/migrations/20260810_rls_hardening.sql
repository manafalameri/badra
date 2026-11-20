-- ============================================================
-- بذرة (Badra) — تحصين RLS وتصريحات (لا يمس أي منطق)
-- 1) user_devices: الكتابة حكر على دوال SECURITY DEFINER
-- 2) profiles: منع تحديث الأعمدة الحساسة عبر REST
-- 3) دوال إدارية/حساسة: سحب التنفيذ من anon/PUBLIC
-- ============================================================

-- ── 1) user_devices: إزالة سياسة INSERT + سحب امتيازات الكتابة ──
DROP POLICY IF EXISTS user_devices_insert_own ON badra_core.user_devices;
REVOKE INSERT, UPDATE, DELETE ON badra_core.user_devices FROM authenticated;

-- تبقى الكتابة فقط عبر: check_login_device / carve_device / admin_approve_pending_user
-- (كلها SECURITY DEFINER بصلاحيات مالكها — لا تتأثر)

-- ── 2) profiles: منع تعديل الأعمدة الحساسة مباشرة ──
REVOKE UPDATE (balance, security_code, is_active, failed_login_count, locked_until)
ON badra_core.profiles FROM authenticated;

-- يبقى التحديث عبر REST للاسم/الهاتف/المحفظة فقط،
-- والرصيد/الرمز/التفعيل حصرياً عبر RPC (admin_manual_deposit, activate_user, set_security_code...)

-- ── 3) سحب التنفيذ من anon/PUBLIC للدوال الحساسة ──
REVOKE EXECUTE ON FUNCTION badra_core.admin_approve_pending_user(text, uuid, text, text) FROM anon, PUBLIC;
REVOKE EXECUTE ON FUNCTION badra_core.set_security_code(text, text) FROM anon, PUBLIC;

-- create_pending_user تبقى عامة عن قصد (التسجيل قبل تسجيل الدخول)