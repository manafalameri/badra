-- ============================================================
-- بذرة (Badra) — Reset all test data
-- Clears transactions, balances, deposit requests, audit log
-- Keeps: auth.users, admins, profiles (with balance=0), pending_users
-- ============================================================

-- 1. حذف كل العمليات
DELETE FROM badra_core.transactions_v2;

-- 2. حذف كل طلبات الإيداع
DELETE FROM badra_core.deposit_requests;

-- 3. حذف سجل المراجعة
DELETE FROM badra_core.audit_log;

-- 4. حذف أكواد التفعيل
DELETE FROM badra_core.activation_codes;

-- 5. تصفير رصيد كل المستخدمين
UPDATE badra_core.profiles SET balance = 0, updated_at = now();

-- 6. تصفير balance_summary
UPDATE badra_core.balance_summary
SET total_received = 0, total_distributed = 0, updated_at = now();

-- ============================================================
-- DONE! All test data has been reset.
-- ============================================================
