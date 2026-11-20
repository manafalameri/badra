-- ============================================================
-- بذرة (Badra) — ربط جهاز الزبون رسمياً عند موافقة الأدمن
-- admin_approve_pending_user: يقبل p_user_id + p_device_id + p_device_name
-- ويثبت الجهاز (carved_at) فور الموافقة — قبل أول تسجيل دخول
-- ============================================================

CREATE OR REPLACE FUNCTION badra_core.admin_approve_pending_user(
  p_phone text,
  p_user_id uuid DEFAULT NULL,
  p_device_id text DEFAULT NULL,
  p_device_name text DEFAULT NULL
) RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'badra_core', 'public'
AS $function$
DECLARE
  v_updated INT;
  v_device TEXT := p_device_id;
  v_dev_name TEXT := p_device_name;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '{"success":false,"message":"غير مصرح"}';
  END IF;

  -- إن لم يُمرر الجهاز: جرّب السجل المعلق، ثم metadata الحساب
  IF p_user_id IS NOT NULL AND (v_device IS NULL OR v_device = '') THEN
    SELECT device_id, device_name INTO v_device, v_dev_name
    FROM badra_core.pending_users
    WHERE phone = p_phone AND status = 'pending'
    LIMIT 1;

    IF v_device IS NULL OR v_device = '' THEN
      SELECT raw_user_meta_data->>'device_id',
             raw_user_meta_data->>'device_name'
      INTO v_device, v_dev_name
      FROM auth.users
      WHERE id = p_user_id;
    END IF;
  END IF;

  -- الموافقة على الطلب
  UPDATE badra_core.pending_users
  SET status = 'approved', updated_at = now()
  WHERE phone = p_phone AND status = 'pending';

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  -- حفر جهاز الزبون فوراً: لا يُقبل أي جهاز آخر عند أول دخول
  IF p_user_id IS NOT NULL AND v_device IS NOT NULL AND v_device <> '' THEN
    INSERT INTO badra_core.user_devices (
      user_id, device_id, device_name, carved_at, last_login
    ) VALUES (
      p_user_id, v_device, COALESCE(v_dev_name, ''), now(), now()
    )
    ON CONFLICT (user_id, device_id) DO UPDATE SET
      carved_at = COALESCE(badra_core.user_devices.carved_at, now()),
      last_login = now(),
      device_name = CASE
        WHEN EXCLUDED.device_name <> ''
          THEN EXCLUDED.device_name
        ELSE badra_core.user_devices.device_name
      END;
  END IF;

  IF v_updated = 0 THEN
    RETURN '{"success":false,"message":"لم يتم العثور على طلب معلق بهذا الرقم"}';
  END IF;

  RETURN '{"success":true,"message":"تمت الموافقة بنجاح","device_bound":true}';
END;
$function$;