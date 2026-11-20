-- ============================================================
-- ECDSA P-256 KeyStore columns + carve_device RPC update
-- ============================================================

-- 1. Add ECDSA public key columns + key_source
ALTER TABLE badra_core.user_devices
  ADD COLUMN IF NOT EXISTS public_key_x TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS public_key_y TEXT DEFAULT '',
  ADD COLUMN IF NOT EXISTS key_source TEXT DEFAULT 'software';

-- 2. Update carve_device to accept x, y, key_source
CREATE OR REPLACE FUNCTION badra_core.carve_device(
  p_device_id TEXT,
  p_device_name TEXT,
  p_device_model TEXT DEFAULT '',
  p_public_key_n TEXT DEFAULT '',
  p_public_key_e TEXT DEFAULT '',
  p_public_key_x TEXT DEFAULT '',
  p_public_key_y TEXT DEFAULT '',
  p_key_source TEXT DEFAULT ''
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public, extensions
AS $$
DECLARE
  v_user_id UUID;
  v_existing_carved_at TIMESTAMPTZ;
  v_carved_at TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT carved_at INTO v_existing_carved_at
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND device_id = p_device_id;

  IF v_existing_carved_at IS NOT NULL THEN
    UPDATE badra_core.user_devices
    SET last_login = now(),
        device_name = p_device_name,
        device_model = CASE WHEN p_device_model != '' THEN p_device_model ELSE device_model END,
        public_key_n = CASE WHEN p_public_key_n != '' THEN p_public_key_n ELSE public_key_n END,
        public_key_e = CASE WHEN p_public_key_e != '' THEN p_public_key_e ELSE public_key_e END,
        public_key_x = CASE WHEN p_public_key_x != '' THEN p_public_key_x ELSE public_key_x END,
        public_key_y = CASE WHEN p_public_key_y != '' THEN p_public_key_y ELSE public_key_y END,
        key_source = CASE WHEN p_key_source != '' THEN p_key_source ELSE key_source END,
        key_created_at = CASE WHEN p_public_key_x != '' OR p_public_key_n != '' THEN now() ELSE key_created_at END
    WHERE user_id = v_user_id AND device_id = p_device_id;
    RETURN jsonb_build_object('success', true, 'carved_at', v_existing_carved_at, 'already_carved', true);
  END IF;

  INSERT INTO badra_core.user_devices (
    user_id, device_id, device_name, device_model,
    carved_at, last_login,
    public_key_n, public_key_e,
    public_key_x, public_key_y, key_source, key_created_at
  ) VALUES (
    v_user_id, p_device_id, p_device_name, p_device_model,
    now(), now(),
    p_public_key_n, p_public_key_e,
    p_public_key_x, p_public_key_y, p_key_source,
    CASE WHEN p_public_key_x != '' OR p_public_key_n != '' THEN now() ELSE NULL END
  )
  ON CONFLICT (user_id, device_id) DO UPDATE SET
    last_login = now(),
    carved_at = COALESCE(badra_core.user_devices.carved_at, now()),
    public_key_n = CASE WHEN p_public_key_n != '' THEN p_public_key_n ELSE badra_core.user_devices.public_key_n END,
    public_key_e = CASE WHEN p_public_key_e != '' THEN p_public_key_e ELSE badra_core.user_devices.public_key_e END,
    public_key_x = CASE WHEN p_public_key_x != '' THEN p_public_key_x ELSE badra_core.user_devices.public_key_x END,
    public_key_y = CASE WHEN p_public_key_y != '' THEN p_public_key_y ELSE badra_core.user_devices.public_key_y END,
    key_source = CASE WHEN p_key_source != '' THEN p_key_source ELSE badra_core.user_devices.key_source END,
    key_created_at = CASE WHEN p_public_key_x != '' OR p_public_key_n != '' THEN now() ELSE badra_core.user_devices.key_created_at END;

  SELECT carved_at INTO v_carved_at
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND device_id = p_device_id;

  RETURN jsonb_build_object('success', true, 'carved_at', v_carved_at);
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.carve_device FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.carve_device TO authenticated;

-- 3. Update get_device_public_key to return x, y, key_source
CREATE OR REPLACE FUNCTION badra_core.get_device_public_key(
  p_user_id UUID,
  p_device_id TEXT
) RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_device badra_core.user_devices%ROWTYPE;
BEGIN
  SELECT * INTO v_device
  FROM badra_core.user_devices
  WHERE user_id = p_user_id AND device_id = p_device_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير موجود');
  END IF;

  IF (v_device.public_key_x IS NULL OR v_device.public_key_x = '') AND
     (v_device.public_key_n IS NULL OR v_device.public_key_n = '') THEN
    RETURN jsonb_build_object('success', false, 'error', 'المفتاح العام غير موجود لهذا الجهاز');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'n', v_device.public_key_n,
    'e', v_device.public_key_e,
    'x', v_device.public_key_x,
    'y', v_device.public_key_y,
    'key_source', v_device.key_source
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION badra_core.get_device_public_key FROM anon, public;
GRANT EXECUTE ON FUNCTION badra_core.get_device_public_key TO service_role;
