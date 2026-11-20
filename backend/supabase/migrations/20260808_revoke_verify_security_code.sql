-- SECURITY FIX: verify_security_code accepted an arbitrary p_user_id and acted
-- as an unlimited remote PIN-guessing oracle for any authenticated user.
--
-- Verified usage before this change:
--   - Only caller: Edge Function `approve-payment-signature` (index.ts:187),
--     which authenticates via the service_role client -> NOT affected.
--   - The Flutter wallet app and admin panel do NOT call it via RPC.
--   - No trigger, view, or other DB function depends on it.
--
-- No attempt-limit exists inside the function (no lockout), so leaving
-- EXECUTE open to `authenticated` allowed unbounded offline-style guessing of
-- the victim's PIN once combined with a compromised device software key.
--
-- Fix: ONLY revoke EXECUTE from the `authenticated` role. `postgres` and
-- `service_role` are kept (the Edge Function needs service_role).
-- No change to the function body or behavior.

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'badra_core'
      AND p.proname = 'verify_security_code'
  ) THEN
    REVOKE EXECUTE ON FUNCTION badra_core.verify_security_code(uuid, text)
      FROM authenticated;
  END IF;
END $$;