-- SECURITY FIX: admin_fetch_activation_code(p_phone) generated a fresh
-- activation code for ANY phone without checking the caller is an admin.
-- Any authenticated user could mint codes (and wipe existing unused ones for
-- that phone via DELETE), enabling account-takeover of pending flows.
--
-- The 2-param overload already had the is_admin() check; the 1-param version
-- lost it when `fix_admin_fetch_activation_code_remove_is_admin`
-- (2026-07-24, applied out-of-band, not in version control) dropped it.
--
-- Usage verified before this change:
--   - admin panel (admin_panel/lib/services/supabase_service.dart:173,326)
--     calls it with the admin session (_client) -> auth.uid() = admin -> OK.
--   - Not called by the wallet app or any Edge Function.
--
-- Fix: restore the intended body (identical to migration
-- 20260723000100_fix_pending_users_flow.sql) with the is_admin() guard FIRST,
-- before any DELETE/INSERT. Behavior for admins is unchanged (same JSON
-- contract, 24h expiry, 6-digit random code).

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
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح: فقط الأدمن يمكنه تنفيذ هذه العملية.');
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

REVOKE EXECUTE ON FUNCTION badra_core.admin_fetch_activation_code(text) FROM anon, public;