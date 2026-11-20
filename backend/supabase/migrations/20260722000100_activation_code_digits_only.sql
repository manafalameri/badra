-- Change activation codes to digits-only (6 digits)

-- 1. Drop and recreate create_pending_user (needed because parameter defaults changed)
DROP FUNCTION IF EXISTS badra_core.create_pending_user(text,text,text,text,text,text);

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
SET search_path = badra_core, public
AS $$
DECLARE
  v_user_id UUID;
  v_activation_code TEXT;
  v_existing_user_id UUID;
BEGIN
  -- Normalize phone
  p_phone := regexp_replace(p_phone, '\D', '', 'g');
  IF p_phone NOT LIKE '967%' THEN
    p_phone := '967' || p_phone;
  END IF;

  -- Check existing pending/active user
  SELECT user_id INTO v_existing_user_id
  FROM badra_core.profiles
  WHERE phone = p_phone
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing_user_id IS NOT NULL THEN
    -- Return existing pending code if still pending
    SELECT code INTO v_activation_code
    FROM badra_core.activation_codes
    WHERE phone = p_phone AND user_id = v_existing_user_id AND expires_at > now()
    ORDER BY created_at DESC
    LIMIT 1;

    IF v_activation_code IS NOT NULL THEN
      RETURN jsonb_build_object('success', true, 'user_id', v_existing_user_id, 'activation_code', v_activation_code, 'message', 'exists');
    END IF;
  END IF;

  -- Generate 6-digit numeric activation code
  v_activation_code := lpad(floor(random() * 1000000)::int::text, 6, '0');

  -- Create auth user with pending metadata
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
    NULL,
    jsonb_build_object(
      'name', p_name,
      'phone', p_phone,
      'status', 'pending',
      'activation_code', v_activation_code,
      'ip', p_ip,
      'device_name', p_device_name,
      'device_id', p_device_id
    ),
    jsonb_build_object('provider', 'phone'),
    now(),
    now()
  )
  RETURNING id INTO v_user_id;

  INSERT INTO badra_core.profiles (
    user_id, name, phone, password_hash, ip, device_name, device_id, status, activation_code
  ) VALUES (
    v_user_id, p_name, p_phone, crypt(p_password, gen_salt('bf', 10)), p_ip, p_device_name, p_device_id, 'pending', v_activation_code
  );

  INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
  VALUES (p_phone, v_user_id, v_activation_code, now() + interval '24 hours');

  RETURN jsonb_build_object('success', true, 'user_id', v_user_id, 'activation_code', v_activation_code, 'message', 'created');
END;
$$;

-- 2. Update admin_fetch_activation_code
CREATE OR REPLACE FUNCTION badra_core.admin_fetch_activation_code(
  p_phone TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_user_id UUID;
  v_code TEXT;
BEGIN
  p_phone := regexp_replace(p_phone, '\D', '', 'g');

  SELECT user_id INTO v_user_id
  FROM badra_core.profiles
  WHERE phone = p_phone
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  -- Generate 6-digit numeric activation code
  v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');

  DELETE FROM badra_core.activation_codes
  WHERE phone = p_phone;

  INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
  VALUES (p_phone, v_user_id, v_code, now() + interval '24 hours');

  RETURN jsonb_build_object('success', true, 'code', v_code);
END;
$$;

-- 3. Update the trigger function for user creation (if exists)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc WHERE proname = 'handle_new_user' AND pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'badra_core')
  ) THEN
    EXECUTE $t$
    CREATE OR REPLACE FUNCTION badra_core.handle_new_user()
    RETURNS TRIGGER
    LANGUAGE plpgsql
    SECURITY DEFINER
    AS $f$
    DECLARE
      v_code TEXT;
    BEGIN
      IF NEW.raw_user_meta_data->>'status' = 'pending' THEN
        v_code := COALESCE(NEW.raw_user_meta_data->>'activation_code', lpad(floor(random() * 1000000)::int::text, 6, '0'));
        INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
        VALUES (NEW.phone, NEW.id, v_code, now() + interval '24 hours')
        ON CONFLICT (user_id) DO UPDATE
        SET code = EXCLUDED.code, expires_at = EXCLUDED.expires_at, created_at = now();
      END IF;
      RETURN NEW;
    END;
    $f$;
    $t$;
  END IF;
END $$;

SELECT 'activation code functions updated to 6 digits' AS status;
