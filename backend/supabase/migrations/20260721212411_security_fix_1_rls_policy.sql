-- =============================================================================
-- SECURITY FIX 1: Remove dangerous self-approval RLS policy
-- =============================================================================
-- Vulnerability: update_own_pending_requests allowed users to PATCH their own
-- payment_requests status to 'approved' without PIN, challenge code, device check,
-- or balance deduction. This allowed theft: merchant ships goods, user never charged.
-- =============================================================================

-- Drop the dangerous policy that allowed self-approval
DROP POLICY IF EXISTS update_own_pending_requests ON badra_core.payment_requests;

-- Create a safer policy: users can only REJECT their own pending requests
-- (approval must go through the secure RPC with PIN + challenge + device checks)
CREATE POLICY reject_own_pending_requests ON badra_core.payment_requests
  FOR UPDATE USING (
    user_id = auth.uid()
    AND status = 'pending'
  )
  WITH CHECK (
    user_id = auth.uid()
    AND status = 'rejected'
  );

-- Verify: no policy should allow UPDATE to 'approved' via PostgREST
COMMENT ON POLICY reject_own_pending_requests ON badra_core.payment_requests IS
  'SECURITY: Users can only reject pending requests. Approval requires secure RPC with PIN + challenge + device verification.';
