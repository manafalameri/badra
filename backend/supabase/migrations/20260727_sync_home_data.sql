-- ============================================================
-- Sync home data RPC + reduce profile payload
-- ============================================================

-- 1. Reduce get_my_profile payload to only essential fields.
--    Never expose wallet_id, created_at, or security hashes to the client.
CREATE OR REPLACE FUNCTION badra_core.get_my_profile()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
BEGIN
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profile not found');
  END IF;

  RETURN jsonb_build_object(
    'name', v_profile.name,
    'balance', v_profile.balance,
    'is_active', v_profile.is_active
  );
END;
$$;

-- 2. Single combined RPC for the home screen.
--    Returns profile, pending requests, device/lockout/security state in one round-trip.
CREATE OR REPLACE FUNCTION badra_core.sync_home_data()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_pending JSONB;
  v_has_device BOOLEAN;
  v_setup_required BOOLEAN;
  v_locked BOOLEAN;
  v_attempt_count INT;
  v_max_attempts INT := 5;
  v_lockout_minutes INT := 30;
BEGIN
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profile not found');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', pr.id,
      'merchant_name', m.name,
      'amount', pr.amount,
      'order_ref', pr.order_ref,
      'items', pr.items,
      'expires_at', pr.expires_at,
      'created_at', pr.created_at,
      'expires_in_seconds', extract(epoch from (pr.expires_at - now()))
    ) ORDER BY pr.created_at DESC
  ), '[]'::jsonb) INTO v_pending
  FROM badra_core.payment_requests pr
  JOIN badra_core.merchants m ON m.id = pr.merchant_id
  WHERE pr.user_id = auth.uid()
    AND pr.status = 'pending'
    AND pr.expires_at > now();

  SELECT EXISTS(
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = auth.uid() AND carved_at IS NOT NULL
  ) INTO v_has_device;

  SELECT security_code IS NULL OR security_code = '' INTO v_setup_required
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = auth.uid()
    AND attempt_type = 'security_code'
    AND attempted_at > now() - (v_lockout_minutes || ' minutes')::INTERVAL;

  v_locked := v_attempt_count >= v_max_attempts;

  RETURN jsonb_build_object(
    'profile', jsonb_build_object(
      'name', v_profile.name,
      'balance', v_profile.balance
    ),
    'pending_requests', v_pending,
    'has_device', v_has_device,
    'setup_required', v_setup_required,
    'locked', v_locked
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.sync_home_data FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.sync_home_data TO authenticated;
