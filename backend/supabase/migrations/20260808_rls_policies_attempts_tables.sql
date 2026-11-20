-- SECURITY FIX: challenge_attempts and identity_verify_attempts had RLS
-- enabled but ZERO policies (security advisor: rls_enabled_no_policy).
-- Default-with-no-policy = all direct client access denied, which was safe,
-- but the missing policies also meant nothing documented what was allowed.
--
-- Usage verified before this change:
--   challenge_attempts: written/read ONLY inside SECURITY DEFINER functions
--     (set_security_code, lockout RPCs) and the approve-payment-signature
--     Edge Function (service_role) -> both bypass RLS -> NOT affected.
--   identity_verify_attempts: written/read ONLY inside SECURITY DEFINER
--     functions (identity verify flow) -> NOT affected.
--   Neither table is queried directly by the Flutter app or admin panel.
--
-- Fix: add minimal self-only SELECT policies (owner can read their own
-- attempts). NO INSERT/UPDATE/DELETE policies: direct client writes stay
-- forbidden — writes remain exclusive to SECURITY DEFINER functions and
-- service_role. This keeps attacker-controlled clients read-only for their
-- own rows and unable to see/delete anyone else's attempts.

-- challenge_attempts: users can read their own failed-attempt history
CREATE POLICY "challenge_attempts_select_own"
  ON badra_core.challenge_attempts
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- identity_verify_attempts: users can read their own phone's attempt history
CREATE POLICY "identity_verify_attempts_select_own_phone"
  ON badra_core.identity_verify_attempts
  FOR SELECT
  TO authenticated
  USING (phone = auth.jwt() ->> 'phone');