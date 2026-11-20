-- SECURITY FIX: get_my_security_code leaked the bcrypt hash of any user's PIN
-- by phone number. Any authenticated user could call it with an arbitrary phone
-- and obtain the hash, enabling offline brute-force of the 6-digit PIN.
--
-- Verified 100% unused before this change:
--   - Not referenced by the Flutter wallet app
--   - Not referenced by the admin panel
--   - Not referenced by any Edge Function
--   - Not referenced by any other DB function, trigger, or view
--   - Not defined in any prior migration (created manually, outside version control)
--
-- Fix: ONLY revoke EXECUTE from the `authenticated` role. `postgres` and
-- `service_role` are kept so the function can be restored if ever needed.
-- The conditional guard prevents failure on fresh environments where the
-- manually-created (non-migrated) function may not exist.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'badra_core'
      AND p.proname = 'get_my_security_code'
  ) THEN
    REVOKE EXECUTE ON FUNCTION badra_core.get_my_security_code(p_phone text)
      FROM authenticated;
  END IF;
END $$;