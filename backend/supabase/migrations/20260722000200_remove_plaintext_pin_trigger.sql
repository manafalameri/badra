-- SECURITY FIX: Remove auto-generation of plaintext security codes
-- The trigger set_security_code_on_insert was creating plaintext PINs automatically,
-- bypassing the bcrypt-only set_security_code RPC and locking users out of changing it.

-- Drop the trigger that auto-generates plaintext security codes
DROP TRIGGER IF EXISTS trg_set_security_code ON badra_core.profiles;

-- Drop the helper function (no longer needed)
DROP FUNCTION IF EXISTS badra_core.set_security_code_on_insert();
DROP FUNCTION IF EXISTS badra_core.generate_security_code();

-- Ensure create_pending_user does NOT set security_code (user must set via app)
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

  -- security_code intentionally left NULL/empty; user must set it via PIN setup
  INSERT INTO badra_core.profiles (
    user_id, name, phone, password_hash, ip, device_name, device_id, status, activation_code, security_code
  ) VALUES (
    v_user_id, p_name, p_phone, crypt(p_password, gen_salt('bf', 10)), p_ip, p_device_name, p_device_id, 'pending', v_activation_code, ''
  );

  INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
  VALUES (p_phone, v_user_id, v_activation_code, now() + interval '24 hours');

  RETURN jsonb_build_object('success', true, 'user_id', v_user_id, 'activation_code', v_activation_code, 'message', 'created');
END;
$$;

-- Migrate any remaining plaintext security_codes to bcrypt
-- We cannot know the original PIN, so we hash them as-is (user must enter the same 6 digits)
UPDATE badra_core.profiles
SET security_code = crypt(security_code, gen_salt('bf', 10))
WHERE security_code IS NOT NULL
  AND security_code != ''
  AND security_code NOT LIKE '$2%';

SELECT 'plaintext PIN trigger removed and existing plaintext PINs hashed' AS status;
