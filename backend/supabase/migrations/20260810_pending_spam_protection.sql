-- ============================================================
-- بذرة (Badra) — حماية قائمة الانتظار من الإغراق (اختياري)
-- حد 3 طلبات جديدة لكل IP خلال ساعة
-- التطبيق: Supabase Dashboard → SQL Editor → Run
-- ============================================================

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
SET search_path TO 'badra_core', 'public'
AS $function$
DECLARE
  v_existing_id UUID;
  v_recent_count INT;
BEGIN
  p_phone := regexp_replace(p_phone, '\D', '', 'g');
  IF p_phone NOT LIKE '967%' THEN
    p_phone := '967' || p_phone;
  END IF;

  -- حماية: حد 3 طلبات لكل IP خلال آخر ساعة (منع إغراق قائمة الانتظار)
  SELECT COUNT(*) INTO v_recent_count
  FROM badra_core.pending_users
  WHERE ip = p_ip
    AND created_at > now() - interval '1 hour';

  IF v_recent_count >= 3 THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'لقد أرسلت أكثر من 3 طلبات خلال ساعة. حاول لاحقاً.'
    );
  END IF;

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
$function$;