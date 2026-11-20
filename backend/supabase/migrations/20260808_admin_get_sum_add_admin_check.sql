-- SECURITY FIX: admin_get_sum returned the platform-wide total received /
-- distributed amounts to ANY authenticated user (no admin check).
--
-- The original definition (20260703_admin_deposit_feature.sql:144) had
-- `IF NOT badra_core.is_admin() THEN RAISE EXCEPTION`; a later out-of-band
-- edit (not in version control) rewrote it as a plain SQL function reading
-- balance_summary WITHOUT any authorization check.
--
-- Usage verified before this change:
--   - admin panel (admin_panel/lib/services/supabase_service.dart:484-485)
--     calls it with the admin session -> auth.uid() = admin -> OK.
--   - Not called by the wallet app or any Edge Function.
--
-- Fix: keep the current (working) balance_summary behavior but restore the
-- is_admin() guard. Admin behavior is unchanged (same return values).

CREATE OR REPLACE FUNCTION badra_core.admin_get_sum(p_is_in integer DEFAULT 1)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_total NUMERIC;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: أنت لست أدمن';
  END IF;

  SELECT CASE
    WHEN p_is_in = 1 THEN total_received
    WHEN p_is_in = 0 THEN total_distributed
    ELSE 0
  END
  INTO v_total
  FROM badra_core.balance_summary
  LIMIT 1;

  RETURN COALESCE(v_total, 0);
END;
$function$;

REVOKE EXECUTE ON FUNCTION badra_core.admin_get_sum(integer) FROM anon, public;