-- =============================================================================
-- SECURITY: security_attempts_v2 — multi-dimensional attempt ledger
-- =============================================================================
-- Replaces the unenforced login lockout (check_login_allowed read only,
-- nothing ever INSERTed attempt_type='login' rows).
--
-- Dimensions:
--   user   -> target = phone          (who is being attacked)
--   device -> target = device hash    (device being abused)
--   ip     -> target = /24 subnet     (network being abused, cf-connecting-ip)
--   global -> target = 'all'          (distributed attack tripwire)
--
-- SECURITY: RLS enabled with ZERO policies. All access goes through
-- SECURITY DEFINER functions (check_lockout_v2 / record_attempt_v2 /
-- clear_attempts_v2) which are granted ONLY to service_role (the login
-- Edge Function). Clients (anon/authenticated) can never read, write or
-- reset these counters.
-- =============================================================================

CREATE TABLE IF NOT EXISTS badra_core.security_attempts_v2 (
  id BIGSERIAL PRIMARY KEY,
  dimension TEXT NOT NULL CHECK (dimension IN ('user', 'device', 'ip', 'global')),
  target TEXT NOT NULL,
  attempt_type TEXT NOT NULL DEFAULT 'login',
  outcome TEXT NOT NULL CHECK (outcome IN ('fail', 'success', 'locked')),
  ip TEXT NOT NULL DEFAULT '',
  user_agent TEXT NOT NULL DEFAULT '',
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_security_attempts_v2_user
  ON badra_core.security_attempts_v2 (dimension, target, attempt_type, outcome, attempted_at);

CREATE INDEX IF NOT EXISTS idx_security_attempts_v2_time
  ON badra_core.security_attempts_v2 (attempted_at DESC);

ALTER TABLE badra_core.security_attempts_v2 ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE badra_core.security_attempts_v2 IS
  'SECURITY: multi-dimensional failed-attempt ledger. Write-only via SECURITY DEFINER RPCs, service_role only.';
