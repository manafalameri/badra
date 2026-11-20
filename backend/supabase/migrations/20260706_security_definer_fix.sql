-- ============================================================
-- بذرة (Badra) — SECURITY DEFINER hardening
-- Revoke EXECUTE from anon/public for admin-only functions
-- Also fixes parameter mismatch in admin_manual_deposit REVOKE
-- ============================================================

-- 1. Ensure RLS is enabled on admins table (advisor reported it as disabled)
ALTER TABLE IF EXISTS badra_core.admins ENABLE ROW LEVEL SECURITY;

-- 2. Fix admin_manual_deposit: REVOKE using correct parameter order
--    (previous REVOKE targeted (numeric,text,text,text,text,text,text)
--     but actual function signature is (text,text,text,numeric,text,text,text))
REVOKE EXECUTE ON FUNCTION badra_core.admin_manual_deposit(
    p_wallet_id text, p_phone text, p_name text,
    p_amount numeric, p_bank_name text,
    p_receipt_number text, p_notes text
) FROM anon, public;

-- 3. Revoke anon/public from admin_cleanup_expired_codes
REVOKE EXECUTE ON FUNCTION badra_core.admin_cleanup_expired_codes(
    p_older_than_hours integer
) FROM anon, public;

-- 4. Revoke anon/public from get_my_profile (authenticated-only function)
REVOKE EXECUTE ON FUNCTION badra_core.get_my_profile() FROM anon, public;

-- 5. Revoke anon/public from reject_pending_user (admin-only function)
REVOKE EXECUTE ON FUNCTION badra_core.reject_pending_user(
    p_phone text, p_reason text
) FROM anon, public;

-- ============================================================
-- DONE! SECURITY DEFINER functions are now properly restricted.
-- ============================================================
