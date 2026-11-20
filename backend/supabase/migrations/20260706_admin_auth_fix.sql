-- ============================================================
-- إصلاح نظام الصلاحيات: توحيد is_admin() على جدول admins
-- يحل المشكلة #2 و #11
-- ============================================================

-- 1. تغيير is_admin() لاستخدام auth.uid() + admins table بدلاً من JWT app_metadata
CREATE OR REPLACE FUNCTION badra_core.is_admin()
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = badra_core
AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM badra_core.admins
    WHERE user_id = auth.uid()
  );
END;
$$;

-- 2. تحديث handle_new_user() لاستخدام admins table بدل raw_user_meta_data->>'role'
-- Trigger 1: Auto-create profile + activation code on user signup
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

-- 3. حذف trigger sync_role_to_app_metadata (النسخة القديمة غير الآمنة)
DROP TRIGGER IF EXISTS on_auth_user_sync_role ON auth.users;
DROP FUNCTION IF EXISTS badra_core.sync_role_to_app_metadata();
