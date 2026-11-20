-- ============================================================
-- Return created_at (join date) from profile RPCs
-- so the app can display "تاريخ الانضمام".
-- Only the authenticated owner receives it (auth.uid() in WHERE).
-- ============================================================

CREATE OR REPLACE FUNCTION badra_core.get_my_profile(
  p_device_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_check JSONB;
BEGIN
  v_check := badra_core.verify_authorized_device(p_device_id);
  IF v_check->>'success' != 'true' THEN
    RETURN jsonb_build_object('error', COALESCE(v_check->>'error', 'الجهاز غير مصرح'));
  END IF;

  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profile not found');
  END IF;

  RETURN jsonb_build_object(
    'name', v_profile.name,
    'balance', v_profile.balance,
    'is_active', v_profile.is_active,
    'created_at', v_profile.created_at
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.get_my_profile(text) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.get_my_profile(text) TO authenticated;

CREATE OR REPLACE FUNCTION badra_core.sync_home_data(
  p_device_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_check JSONB;
  v_pending JSONB;
  v_has_device BOOLEAN;
  v_setup_required BOOLEAN;
  v_locked BOOLEAN;
  v_attempt_count INT;
  v_max_attempts INT := 5;
  v_lockout_minutes INT := 30;
BEGIN
  v_check := badra_core.verify_authorized_device(p_device_id);
  IF v_check->>'success' != 'true' THEN
    RETURN jsonb_build_object('error', COALESCE(v_check->>'error', 'الجهاز غير مصرح'));
  END IF;

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
    'locked', v_locked,
    'created_at', v_profile.created_at
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.sync_home_data(text) FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.sync_home_data(text) TO authenticated;