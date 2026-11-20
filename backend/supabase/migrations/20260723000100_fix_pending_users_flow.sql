-- =====================================================
-- Fix: pending_users registration flow + security fixes
-- =====================================================

-- 1. Rewrite create_pending_user to ONLY insert into pending_users
-- (No auth.users, no profiles, no activation_codes)
CREATE OR REPLACE FUNCTION badra_core.create_pending_user(
  p_name TEXT,
  p_phone TEXT,
  p_password TEXT,
  p_ip TEXT,
  p_device_name TEXT,
  p_device_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO badra_core, public
AS $$
DECLARE
  v_existing_id UUID;
BEGIN
  -- Normalize phone
  p_phone := regexp_replace(p_phone, '\D', '', 'g');
  IF p_phone NOT LIKE '967%' THEN
    p_phone := '967' || p_phone;
  END IF;

  -- Check if there is already a pending request for this phone
  SELECT id INTO v_existing_id
  FROM badra_core.pending_users
  WHERE phone = p_phone
    AND status = 'pending'
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'pending_user_id', v_existing_id,
      'message', 'exists'
    );
  END IF;

  -- Insert into pending_users only
  INSERT INTO badra_core.pending_users (
    name, phone, password_hash, ip, device_name, device_id, status
  ) VALUES (
    p_name, p_phone, p_password, p_ip, p_device_name, p_device_id, 'pending'
  )
  RETURNING id INTO v_existing_id;

  RETURN jsonb_build_object(
    'success', true,
    'pending_user_id', v_existing_id,
    'message', 'created'
  );
END;
$$;

-- 2. Fix admin_fetch_activation_code (single param) - add is_admin() check
CREATE OR REPLACE FUNCTION badra_core.admin_fetch_activation_code(
  p_phone TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO badra_core, public
AS $$
DECLARE
  v_user_id UUID;
  v_code TEXT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح');
  END IF;

  p_phone := regexp_replace(p_phone, '\D', '', 'g');

  SELECT user_id INTO v_user_id
  FROM badra_core.profiles
  WHERE phone = p_phone
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');

  DELETE FROM badra_core.activation_codes
  WHERE phone = p_phone;

  INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
  VALUES (p_phone, v_user_id, v_code, now() + interval '24 hours');

  RETURN jsonb_build_object('success', true, 'code', v_code);
END;
$$;

-- REVOKE admin_fetch_activation_code from anon/public
REVOKE EXECUTE ON FUNCTION badra_core.admin_fetch_activation_code(text) FROM anon, public;

-- 3. Remove password_hash from get_pending_users
CREATE OR REPLACE FUNCTION badra_core.get_pending_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO badra_core, public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '[]'::jsonb;
  END IF;
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', pu.id,
      'name', pu.name,
      'phone', pu.phone,
      'ip', pu.ip,
      'device_name', pu.device_name,
      'device_id', pu.device_id,
      'status', pu.status,
      'created_at', pu.created_at
    )
    ORDER BY pu.created_at DESC
  ), '[]'::jsonb) INTO v_result
  FROM badra_core.pending_users pu
  WHERE pu.status = 'pending';
  RETURN v_result;
END;
$$;

-- 4. Remove password_hash from admin_get_pending_user_by_phone
CREATE OR REPLACE FUNCTION badra_core.admin_get_pending_user_by_phone(
  p_phone TEXT
) RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO badra_core, public
AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '{"success":false,"message":"غير مصرح"}';
  END IF;

  SELECT jsonb_build_object(
    'success', true,
    'name', pu.name,
    'phone', pu.phone,
    'ip', pu.ip,
    'device_name', pu.device_name,
    'device_id', pu.device_id,
    'status', pu.status,
    'created_at', pu.created_at
  )
  INTO v_result
  FROM badra_core.pending_users pu
  WHERE pu.phone = p_phone
    AND pu.status = 'pending'
  LIMIT 1;

  IF v_result IS NULL THEN
    RETURN '{"success":false,"message":"المستخدم المعلق غير موجود"}';
  END IF;

  RETURN v_result::TEXT;
END;
$$;
