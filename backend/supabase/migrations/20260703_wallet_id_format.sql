-- ============================================================
-- تغيير صيغة wallet_id: '101' + أرقام الهاتف بدل 'W-' + عشوائي
-- ============================================================

-- 1. تغيير DEFAULT في profiles
ALTER TABLE badra_core.profiles
ALTER COLUMN wallet_id SET DEFAULT '';

-- 2. تحديث الـ trigger لإنشاء wallet_id بشكل صحيح
CREATE OR REPLACE FUNCTION badra_core.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core, public
AS $$
DECLARE
  v_code TEXT;
  v_is_admin BOOLEAN;
BEGIN
  INSERT INTO badra_core.profiles (user_id, phone, name, is_active, wallet_id)
  VALUES (
    NEW.id,
    NEW.phone,
    COALESCE(NEW.raw_user_meta_data->>'name', NEW.phone),
    false,
    '101' || regexp_replace(NEW.phone, '[^0-9]', '', 'g')
  )
  ON CONFLICT (user_id) DO NOTHING;

  SELECT EXISTS (
    SELECT 1 FROM badra_core.admins WHERE user_id = NEW.id
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    v_code := COALESCE(
      NEW.raw_user_meta_data->>'activation_code',
      upper(substr(md5(gen_random_uuid()::text), 1, 6))
    );

    INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
    VALUES (NEW.phone, NEW.id, v_code, now() + interval '90 minutes')
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- 3. تحديث الحسابات الموجودة (backfill)
UPDATE badra_core.profiles
SET wallet_id = '101' || regexp_replace(phone, '[^0-9]', '', 'g')
WHERE wallet_id NOT LIKE '101%' OR wallet_id = '';
