-- =============================================================================
-- Migration: Instant Direct User Activation & Removal of Activation Codes
-- Date: 2026-09-12
-- =============================================================================

-- 1. Activate all existing accounts in profiles
UPDATE badra_core.profiles SET is_active = true WHERE is_active = false;

-- 2. Ensure default value of is_active in profiles is TRUE
ALTER TABLE badra_core.profiles ALTER COLUMN is_active SET DEFAULT true;

-- 3. Update handle_new_user trigger function to always activate profiles and stop creating activation_codes
CREATE OR REPLACE FUNCTION badra_core.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
BEGIN
  INSERT INTO badra_core.profiles (user_id, name, phone, wallet_id, is_active)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', ''),
    NEW.phone,
    '101' || regexp_replace(NEW.phone, '[^0-9]', '', 'g'),
    true
  )
  ON CONFLICT (user_id) DO UPDATE
  SET is_active = true;

  RETURN NEW;
END;
$$;

-- 4. Update create_pending_user to instantly create auth.users and active profile
CREATE OR REPLACE FUNCTION badra_core.create_pending_user(
  p_name text,
  p_phone text,
  p_password text,
  p_ip text,
  p_device_name text,
  p_device_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $function$
DECLARE
  v_user_id UUID;
  v_recent_count INT;
BEGIN
  -- Normalize phone
  p_phone := regexp_replace(p_phone, '\D', '', 'g');
  IF p_phone NOT LIKE '967%' THEN
    p_phone := '967' || p_phone;
  END IF;

  -- Rate limit: max 5 signups per IP per hour
  SELECT COUNT(*) INTO v_recent_count
  FROM badra_core.security_attempts_v2
  WHERE ip = p_ip
    AND attempt_type = 'signup'
    AND attempted_at > now() - interval '1 hour';

  IF v_recent_count >= 5 THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'لقد تجاوزت الحد المسموح لمحاولات التسجيل من هذا الجهاز. حاول لاحقاً.'
    );
  END IF;

  -- Record attempt
  IF p_ip IS NOT NULL AND p_ip <> '' THEN
    INSERT INTO badra_core.security_attempts_v2 (dimension, target, attempt_type, outcome, ip, user_agent)
    VALUES ('ip', p_ip, 'signup', 'success', p_ip, p_device_name);
  END IF;

  -- Check if user already exists in profiles or auth.users
  IF EXISTS (SELECT 1 FROM badra_core.profiles WHERE phone = p_phone) OR
     EXISTS (SELECT 1 FROM auth.users WHERE phone = p_phone) THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'هذا الرقم مسجل مسبقاً. يرجى تسجيل الدخول مباشرة.'
    );
  END IF;

  -- Create real auth user directly with bcrypt encrypted password
  INSERT INTO auth.users (
    id, aud, role, email, encrypted_password,
    email_confirmed_at, phone, phone_confirmed_at,
    raw_user_meta_data, raw_app_meta_data,
    created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    p_phone || '@badra.local',
    crypt(p_password, gen_salt('bf', 10)),
    now(),
    p_phone,
    now(),
    jsonb_build_object(
      'name', p_name,
      'phone', p_phone,
      'ip', p_ip,
      'device_name', p_device_name,
      'device_id', p_device_id
    ),
    jsonb_build_object('provider', 'phone'),
    now(),
    now()
  )
  RETURNING id INTO v_user_id;

  -- Clean up any leftover pending_users for this phone
  DELETE FROM badra_core.pending_users WHERE phone = p_phone;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', v_user_id,
    'message', 'تم إنشاء الحساب بنجاح.'
  );
END;
$function$;

-- 5. Backward compatibility: update activate_user to be a graceful non-blocking function
CREATE OR REPLACE FUNCTION badra_core.activate_user(
  p_phone TEXT,
  p_code TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_user_id UUID;
  v_clean_phone TEXT;
BEGIN
  v_user_id := auth.uid();
  v_clean_phone := regexp_replace(p_phone, '\D', '', 'g');

  IF v_user_id IS NOT NULL THEN
    UPDATE badra_core.profiles
    SET is_active = true, updated_at = now()
    WHERE user_id = v_user_id;
  ELSIF v_clean_phone <> '' THEN
    UPDATE badra_core.profiles
    SET is_active = true, updated_at = now()
    WHERE phone LIKE '%' || v_clean_phone;
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'تم تفعيل الحساب بنجاح');
END;
$$;

-- Grant execute to anon and authenticated
GRANT EXECUTE ON FUNCTION badra_core.create_pending_user(text, text, text, text, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION badra_core.activate_user(text, text) TO anon, authenticated, service_role;
