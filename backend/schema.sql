


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "badra_core";


ALTER SCHEMA "badra_core" OWNER TO "postgres";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "badra_core"."activate_user"("p_phone" "text", "p_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_code_record badra_core.activation_codes%ROWTYPE;
  v_user_id UUID;
  v_phone_clean TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'يجب تسجيل الدخول أولاً');
  END IF;

  v_phone_clean := replace(p_phone, '+', '');

  SELECT * INTO v_code_record
  FROM badra_core.activation_codes
  WHERE phone = v_phone_clean
    AND used = false
    AND expires_at > now()
  ORDER BY created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'كود التفعيل غير صحيح أو منتهي الصلاحية');
  END IF;

  IF v_code_record.user_id != v_user_id THEN
    RETURN jsonb_build_object('success', false, 'message', 'هذا الكود لا يخص حسابك');
  END IF;

  IF EXISTS (SELECT 1 FROM badra_core.profiles WHERE user_id = v_user_id AND is_active = true) THEN
    RETURN jsonb_build_object('success', false, 'message', 'الحساب مفعل بالفعل');
  END IF;

  IF v_code_record.code != p_code THEN
    UPDATE badra_core.activation_codes
    SET failed_attempts = failed_attempts + 1
    WHERE id = v_code_record.id;

    UPDATE badra_core.activation_codes
    SET expires_at = now()
    WHERE id = v_code_record.id AND failed_attempts >= 5;

    RETURN jsonb_build_object('success', false, 'message', 'كود التفعيل غير صحيح');
  END IF;

  -- Activate profile first
  UPDATE badra_core.profiles
  SET is_active = true, updated_at = now()
  WHERE user_id = v_user_id;

  -- Then delete the code (no traces, no reuse)
  DELETE FROM badra_core.activation_codes
  WHERE id = v_code_record.id;

  RETURN jsonb_build_object('success', true, 'message', 'تم تفعيل الحساب بنجاح');
END;
$$;


ALTER FUNCTION "badra_core"."activate_user"("p_phone" "text", "p_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_approve_finish"("p_phone" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_deleted INT;
  v_phone_clean TEXT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;
  v_phone_clean := replace(p_phone, '+', '');
  DELETE FROM badra_core.pending_users
  WHERE replace(phone, '+', '') = v_phone_clean;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN jsonb_build_object('success', true, 'message', 'تمت الموافقة وحذف ' || v_deleted || ' سجل', 'deleted', v_deleted);
END;
$$;


ALTER FUNCTION "badra_core"."admin_approve_finish"("p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_updated INT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '{"success":false,"message":"غير مصرح"}';
  END IF;

  UPDATE badra_core.pending_users
  SET status = 'approved', updated_at = now()
  WHERE phone = p_phone
    AND status = 'pending';

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  IF v_updated = 0 THEN
    RETURN '{"success":false,"message":"لم يتم العثور على طلب معلق بهذا الرقم"}';
  END IF;

  RETURN '{"success":true,"message":"تمت الموافقة بنجاح"}';
END;
$$;


ALTER FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text", "p_user_id" "uuid" DEFAULT NULL::"uuid", "p_device_id" "text" DEFAULT NULL::"text", "p_device_name" "text" DEFAULT NULL::"text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_updated INT;
  v_device TEXT := p_device_id;
  v_dev_name TEXT := p_device_name;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '{"success":false,"message":"غير مصرح"}';
  END IF;

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

  UPDATE badra_core.pending_users
  SET status = 'approved', updated_at = now()
  WHERE phone = p_phone AND status = 'pending';

  GET DIAGNOSTICS v_updated = ROW_COUNT;

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
$$;


ALTER FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text", "p_user_id" "uuid", "p_device_id" "text", "p_device_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_cleanup_expired_codes"("p_older_than_hours" integer DEFAULT 24) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_deleted INT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;

  DELETE FROM badra_core.activation_codes
  WHERE (used = true OR expires_at < now())
    AND created_at < now() - (p_older_than_hours || ' hours')::interval;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم حذف ' || v_deleted || ' سجل',
    'deleted', v_deleted
  );
END;
$$;


ALTER FUNCTION "badra_core"."admin_cleanup_expired_codes"("p_older_than_hours" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_count_active_users"() RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN 0;
  END IF;
  SELECT COUNT(*) INTO v_count
  FROM badra_core.profiles
  WHERE is_active = true;
  RETURN v_count;
END;
$$;


ALTER FUNCTION "badra_core"."admin_count_active_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_count_pending_users"() RETURNS integer
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN 0;
  END IF;
  SELECT COUNT(*) INTO v_count
  FROM badra_core.pending_users
  WHERE status = 'pending';
  RETURN v_count;
END;
$$;


ALTER FUNCTION "badra_core"."admin_count_pending_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_create_merchant"("p_name" "text", "p_webhook_url" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'extensions', 'public'
    AS $$
DECLARE
  v_merchant_id UUID;
  v_raw_key TEXT;
  v_hashed TEXT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  v_raw_key := 'bd_mch_' || encode(gen_random_bytes(16), 'hex');
  v_hashed := crypt(v_raw_key, extensions.gen_salt('bf', 10));

  INSERT INTO badra_core.merchants (name, api_key_hash, api_key_prefix, webhook_url)
  VALUES (p_name, v_hashed, left(v_raw_key, 16), p_webhook_url)
  RETURNING id INTO v_merchant_id;

  RETURN jsonb_build_object(
    'success', true,
    'merchant_id', v_merchant_id,
    'name', p_name,
    'api_key', v_raw_key,
    'warning', 'احتفظ بهذا المفتاح. لن يظهر مرة أخرى.'
  );
END;
$$;


ALTER FUNCTION "badra_core"."admin_create_merchant"("p_name" "text", "p_webhook_url" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_delete_pending_user"("p_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;
  DELETE FROM badra_core.pending_users
  WHERE id = p_id::uuid;
  RETURN jsonb_build_object('success', true, 'message', 'تم الحذف');
END;
$$;


ALTER FUNCTION "badra_core"."admin_delete_pending_user"("p_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
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


ALTER FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text", "p_user_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_code TEXT;
  v_phone_clean TEXT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;
  v_phone_clean := replace(p_phone, '+', '');
  v_code := upper(substr(md5(gen_random_uuid()::text), 1, 6));
  DELETE FROM badra_core.activation_codes
  WHERE replace(phone, '+', '') = v_phone_clean AND used = false;
  INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
  VALUES (v_phone_clean, p_user_id::uuid, v_code, now() + interval '90 minutes');
  RETURN jsonb_build_object('success', true, 'code', v_code, 'expires_in_minutes', 90);
END;
$$;


ALTER FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text", "p_user_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_get_deposit_records"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
    v_admin_id UUID;
    v_result JSONB;
BEGIN
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN RAISE EXCEPTION 'غير مصرح'; END IF;
    IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN
        RAISE EXCEPTION 'غير مصرح: أنت لست أدمن';
    END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'id', dr.id,
            'user_name', p.name,
            'user_phone', p.phone,
            'user_wallet_id', p.wallet_id,
            'amount', dr.amount,
            'bank_name', dr.bank_name,
            'receipt_number', dr.receipt_number,
            'notes', dr.notes,
            'admin_name', a.name,
            'created_at', dr.created_at
        ) ORDER BY dr.created_at DESC
    ) INTO v_result
    FROM badra_core.deposit_requests dr
    JOIN badra_core.profiles p ON p.user_id = dr.user_id
    JOIN badra_core.profiles a ON a.user_id = dr.admin_id;

    RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;


ALTER FUNCTION "badra_core"."admin_get_deposit_records"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_get_last_transactions"("p_limit" integer DEFAULT 5) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'user_id', t.user_id,
      'debtor', t.debtor,
      'creditor', t.creditor,
      'amount', t.amount,
      'date', t.date,
      'status', t.status,
      'title', t.title,
      'notes', t.notes
    ) ORDER BY t.date DESC
  ) INTO v_result
  FROM badra_core.transactions_v2 t
  LIMIT p_limit;

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;


ALTER FUNCTION "badra_core"."admin_get_last_transactions"("p_limit" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_get_pending_user_by_phone"("p_phone" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
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
    'password_hash', pu.password_hash,
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


ALTER FUNCTION "badra_core"."admin_get_pending_user_by_phone"("p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_get_sum"("p_is_in" integer DEFAULT 1) RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
  v_total NUMERIC;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RAISE EXCEPTION 'غير مصرح: أنت لست أدمن';
  END IF;

  SELECT CASE
    WHEN p_is_in = 1 THEN total_received
    WHEN p_is_in = 0 THEN total_distributed
    ELSE 0
  END
  INTO v_total
  FROM badra_core.balance_summary
  LIMIT 1;

  RETURN COALESCE(v_total, 0);
END;
$$;


ALTER FUNCTION "badra_core"."admin_get_sum"("p_is_in" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_get_total_balance"() RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN 0;
  END IF;
  RETURN COALESCE((SELECT SUM(balance) FROM badra_core.profiles), 0);
END;
$$;


ALTER FUNCTION "badra_core"."admin_get_total_balance"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_get_trading_volume"() RETURNS numeric
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN 0;
  END IF;
  RETURN COALESCE((SELECT SUM(amount) FROM badra_core.transactions_v2), 0);
END;
$$;


ALTER FUNCTION "badra_core"."admin_get_trading_volume"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_list_merchants"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_result JSONB;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', m.id,
      'name', m.name,
      'api_key_prefix', m.api_key_prefix,
      'webhook_url', m.webhook_url,
      'is_active', m.is_active,
      'created_at', m.created_at
    ) ORDER BY m.created_at DESC
  ), '[]'::jsonb) INTO v_result
  FROM badra_core.merchants m;

  RETURN v_result;
END;
$$;


ALTER FUNCTION "badra_core"."admin_list_merchants"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_manual_deposit"("p_wallet_id" "text", "p_phone" "text", "p_name" "text", "p_amount" numeric, "p_bank_name" "text", "p_receipt_number" "text" DEFAULT ''::"text", "p_notes" "text" DEFAULT ''::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
DECLARE
    v_admin_id UUID;
    v_profile_id UUID;
    v_user_id UUID;
    v_old_balance NUMERIC;
    v_admin_name TEXT;
    v_deposit_id UUID;
    v_tx_id UUID;
BEGIN
    v_admin_id := auth.uid();
    IF v_admin_id IS NULL THEN RAISE EXCEPTION 'غير مصرح'; END IF;
    IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN RAISE EXCEPTION 'غير مصرح: لست أدمن'; END IF;
    IF p_amount < 500 THEN RAISE EXCEPTION 'الحد الأدنى 500 ريال';
    ELSIF p_amount > 250000 THEN RAISE EXCEPTION 'الحد الأقصى 250,000 ريال'; END IF;
    IF p_bank_name NOT IN ('العمقي','الكرايمي','القطيبي','البسيري') THEN RAISE EXCEPTION 'بنك غير صحيح'; END IF;

    SELECT name INTO v_admin_name FROM badra_core.profiles WHERE user_id = v_admin_id LIMIT 1;
    IF v_admin_name IS NULL THEN v_admin_name := 'أدمن'; END IF;

    SELECT id, user_id, balance INTO v_profile_id, v_user_id, v_old_balance
    FROM badra_core.profiles
    WHERE wallet_id = p_wallet_id AND phone = p_phone AND name = p_name
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'المستخدم غير موجود'; END IF;

    UPDATE badra_core.profiles SET balance = balance + p_amount, updated_at = now()
    WHERE id = v_profile_id;

    INSERT INTO badra_core.deposit_requests(user_id,amount,bank_name,receipt_number,notes,admin_id,admin_name)
    VALUES(v_user_id,p_amount,p_bank_name,NULLIF(p_receipt_number,''),NULLIF(p_notes,''),v_admin_id,v_admin_name)
    RETURNING id INTO v_deposit_id;

    INSERT INTO badra_core.transactions_v2(user_id,is_in,amount,title,date,status,notes,deposit_request_id)
    VALUES(v_user_id,1,p_amount,'إيداع عبر الأدمن - '||p_bank_name,now(),'completed',NULLIF(p_notes,''),v_deposit_id)
    RETURNING id INTO v_tx_id;

    UPDATE badra_core.balance_summary
    SET total_received = total_received + p_amount, updated_at = now()
    WHERE id = (SELECT id FROM badra_core.balance_summary LIMIT 1);

    INSERT INTO badra_core.audit_log(action,table_name,record_id,old_values,new_values,admin_id,admin_name)
    VALUES('deposit','profiles',v_profile_id,
           jsonb_build_object('balance',v_old_balance),
           jsonb_build_object('balance',v_old_balance+p_amount,'deposit_id',v_deposit_id,'transaction_id',v_tx_id,'amount',p_amount,'bank',p_bank_name),
           v_admin_id,v_admin_name);

    RETURN jsonb_build_object('success',true,'amount',p_amount,'user_id',v_user_id,'old_balance',v_old_balance,'new_balance',v_old_balance+p_amount,'deposit_id',v_deposit_id,'transaction_id',v_tx_id);
END;
$$;


ALTER FUNCTION "badra_core"."admin_manual_deposit"("p_wallet_id" "text", "p_phone" "text", "p_name" "text", "p_amount" numeric, "p_bank_name" "text", "p_receipt_number" "text", "p_notes" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_toggle_merchant"("p_merchant_id" "uuid", "p_is_active" boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  UPDATE badra_core.merchants
  SET is_active = p_is_active
  WHERE id = p_merchant_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المتجر غير موجود');
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'تم تحديث الحالة');
END;
$$;


ALTER FUNCTION "badra_core"."admin_toggle_merchant"("p_merchant_id" "uuid", "p_is_active" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."admin_verify_device"("p_device_id" "text", "p_device_name" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_admin_id UUID;
  v_exists BOOLEAN;
BEGIN
  v_admin_id := auth.uid();
  IF v_admin_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = v_admin_id) THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح: أنت لست أدمن');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = v_admin_id AND device_id = p_device_id
  ) INTO v_exists;

  IF v_exists THEN
    UPDATE badra_core.user_devices
    SET last_login = now(), device_name = p_device_name
    WHERE user_id = v_admin_id AND device_id = p_device_id;
    RETURN jsonb_build_object('success', true, 'message', 'تم التحقق من الجهاز');
  END IF;

  INSERT INTO badra_core.user_devices (user_id, device_id, device_name, last_login)
  VALUES (v_admin_id, p_device_id, p_device_name, now());

  RETURN jsonb_build_object('success', true, 'message', 'تم تسجيل الجهاز بنجاح');
END;
$$;


ALTER FUNCTION "badra_core"."admin_verify_device"("p_device_id" "text", "p_device_name" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."approve_payment_request_v2"("p_request_id" "uuid", "p_challenge_code" "text" DEFAULT ''::"text", "p_device_id" "text" DEFAULT ''::"text", "p_security_code" "text" DEFAULT ''::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $_$
DECLARE
  v_user_id UUID;
  v_request RECORD;
  v_attempt_count INT;
  v_pin_stored TEXT;
  v_device_record RECORD;
  v_balance NUMERIC;
  v_tx_id UUID;
  v_merchant_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = 'security_code'
    AND attempted_at > now() - interval '30 minutes';
  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', false, 'error', 'تم قفل الرقم السري مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  SELECT * INTO v_request FROM badra_core.payment_requests WHERE id = p_request_id FOR UPDATE;
  IF v_request IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'طلب الدفع غير موجود'); END IF;
  IF v_request.user_id != v_user_id THEN RETURN jsonb_build_object('success', false, 'error', 'غير مصرح بهذا الطلب'); END IF;
  IF v_request.status != 'pending' THEN RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب تم معالجته مسبقاً'); END IF;
  IF v_request.expires_at < now() THEN
    UPDATE badra_core.payment_requests SET status = 'expired' WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  IF p_device_id = '' THEN RETURN jsonb_build_object('success', false, 'error', 'معرف الجهاز مطلوب'); END IF;
  SELECT * INTO v_device_record FROM badra_core.user_devices WHERE user_id = v_user_id AND device_id = p_device_id;
  IF v_device_record IS NULL THEN RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مسجل. يرجى تسجيل الدخول من جهازك'); END IF;

  SELECT security_code INTO v_pin_stored FROM badra_core.profiles WHERE user_id = v_user_id;
  IF v_pin_stored IS NULL OR v_pin_stored = '' THEN RETURN jsonb_build_object('success', false, 'error', 'لم يتم تعيين الرقم السري'); END IF;
  IF p_security_code = '' THEN RETURN jsonb_build_object('success', false, 'error', 'الرقم السري إجباري'); END IF;
  IF v_pin_stored NOT LIKE '$2%' THEN RETURN jsonb_build_object('success', false, 'error', 'يجب إعادة تعيين الرقم السري من الإعدادات'); END IF;
  IF v_pin_stored != crypt(p_security_code, v_pin_stored) THEN
    INSERT INTO badra_core.challenge_attempts (user_id, attempt_type) VALUES (v_user_id, 'security_code');
    RETURN jsonb_build_object('success', false, 'error', 'الرقم السري غير صحيح');
  END IF;
  DELETE FROM badra_core.challenge_attempts WHERE user_id = v_user_id AND attempt_type = 'security_code';

  SELECT balance INTO v_balance FROM badra_core.profiles WHERE user_id = v_user_id FOR UPDATE;
  IF v_balance < v_request.amount THEN RETURN jsonb_build_object('success', false, 'error', 'رصيد غير كافي'); END IF;

  UPDATE badra_core.profiles SET balance = balance - v_request.amount, updated_at = now() WHERE user_id = v_user_id;
  SELECT name INTO v_merchant_name FROM badra_core.merchants WHERE id = v_request.merchant_id;
  INSERT INTO badra_core.transactions_v2 (user_id, is_in, amount, title, status, date, notes, ref, store)
  VALUES (v_user_id, 0, v_request.amount, 'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'), 'completed', now(), 'order_ref: ' || v_request.order_ref, v_request.order_ref, COALESCE(v_merchant_name, ''))
  RETURNING id INTO v_tx_id;
  UPDATE badra_core.payment_requests SET status = 'approved', approved_at = now(), tx_id = v_tx_id WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'transaction_id', v_tx_id,
    'new_balance', v_balance - v_request.amount, 'old_balance', v_balance, 'amount', v_request.amount);
END;
$_$;


ALTER FUNCTION "badra_core"."approve_payment_request_v2"("p_request_id" "uuid", "p_challenge_code" "text", "p_device_id" "text", "p_security_code" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "badra_core"."approve_payment_request_v2"("p_request_id" "uuid", "p_challenge_code" "text", "p_device_id" "text", "p_security_code" "text") IS 'SECURITY: bcrypt-only PIN verification. Plaintext fallback removed.';



CREATE OR REPLACE FUNCTION "badra_core"."carve_device"("p_device_id" "text", "p_device_name" "text", "p_device_model" "text" DEFAULT ''::"text", "p_public_key_n" "text" DEFAULT ''::"text", "p_public_key_e" "text" DEFAULT ''::"text", "p_public_key_x" "text" DEFAULT ''::"text", "p_public_key_y" "text" DEFAULT ''::"text", "p_key_source" "text" DEFAULT ''::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
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

  IF EXISTS (
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = v_user_id AND carved_at IS NOT NULL AND device_id <> p_device_id
  ) THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الحساب مرتبط بجهاز آخر. لا يمكن ربط جهاز جديد.');
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


ALTER FUNCTION "badra_core"."carve_device"("p_device_id" "text", "p_device_name" "text", "p_device_model" "text", "p_public_key_n" "text", "p_public_key_e" "text", "p_public_key_x" "text", "p_public_key_y" "text", "p_key_source" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."check_lockout"("p_attempt_type" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_attempt_count INT;
  v_max_attempts INT := 5;
  v_lockout_minutes INT := 30;
  v_recent_attempt TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id
    AND attempt_type = p_attempt_type
    AND attempted_at > now() - (v_lockout_minutes || ' minutes')::INTERVAL;

  SELECT MAX(attempted_at) INTO v_recent_attempt
  FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id
    AND attempt_type = p_attempt_type;

  IF v_attempt_count >= v_max_attempts THEN
    RETURN jsonb_build_object(
      'success', false,
      'locked', true,
      'attempts', v_attempt_count,
      'max_attempts', v_max_attempts,
      'locked_until', v_recent_attempt + (v_lockout_minutes || ' minutes')::INTERVAL
    );
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'locked', false,
    'attempts', v_attempt_count,
    'max_attempts', v_max_attempts,
    'remaining', v_max_attempts - v_attempt_count
  );
END;
$$;


ALTER FUNCTION "badra_core"."check_lockout"("p_attempt_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."check_login_allowed"("p_phone" "text", "p_action" "text" DEFAULT 'login'::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_user_id UUID;
  v_attempt_count INT;
  v_profile RECORD;
BEGIN
  -- Look up user by phone
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE phone = p_phone;

  IF NOT FOUND THEN
    -- No user: don't reveal existence, allow to proceed
    RETURN jsonb_build_object('success', true, 'allowed', true, 'reason', 'no_user');
  END IF;

  -- Check if account is active
  IF NOT v_profile.is_active THEN
    RETURN jsonb_build_object('success', true, 'allowed', false, 'reason', 'inactive', 'error', 'الحساب غير نشط');
  END IF;

  -- Check lockout: max 5 failed login attempts in 30 minutes
  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = v_profile.user_id
    AND attempt_type = 'login'
    AND attempted_at > now() - interval '30 minutes';

  IF v_attempt_count >= 5 THEN
    RETURN jsonb_build_object('success', true, 'allowed', false, 'reason', 'locked', 'error', 'تم قفل الحساب مؤقتاً. حاول بعد 30 دقيقة.');
  END IF;

  -- Login allowed
  RETURN jsonb_build_object('success', true, 'allowed', true, 'reason', 'ok');
END;
$$;


ALTER FUNCTION "badra_core"."check_login_allowed"("p_phone" "text", "p_action" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."check_login_device"("p_device_id" "text", "p_device_name" "text" DEFAULT ''::"text", "p_device_model" "text" DEFAULT ''::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_carved_count INT;
  v_is_carved BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT COUNT(*) INTO v_carved_count
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND carved_at IS NOT NULL;

  IF p_device_id IS NULL OR p_device_id = '' OR p_device_id = 'unknown_device_id' THEN
    IF v_carved_count > 0 THEN
      RETURN jsonb_build_object('success', false, 'error', 'تعذر التحقق من هذا الجهاز. حاول مرة أخرى.');
    END IF;
    RETURN jsonb_build_object('success', true, 'bound', false);
  END IF;

  IF v_carved_count = 0 THEN
    INSERT INTO badra_core.user_devices (
      user_id, device_id, device_name, device_model, carved_at, last_login
    ) VALUES (
      v_user_id, p_device_id, p_device_name, p_device_model, now(), now()
    )
    ON CONFLICT (user_id, device_id) DO UPDATE SET
      carved_at = COALESCE(badra_core.user_devices.carved_at, now()),
      last_login = now(),
      device_name = CASE WHEN p_device_name != '' THEN p_device_name ELSE badra_core.user_devices.device_name END;
    RETURN jsonb_build_object('success', true, 'bound', true);
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = v_user_id AND device_id = p_device_id AND carved_at IS NOT NULL
  ) INTO v_is_carved;

  IF NOT v_is_carved THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الحساب مرتبط بجهاز آخر');
  END IF;

  UPDATE badra_core.user_devices
  SET last_login = now(),
      device_name = CASE WHEN p_device_name != '' THEN p_device_name ELSE device_name END
  WHERE user_id = v_user_id AND device_id = p_device_id;

  RETURN jsonb_build_object('success', true, 'bound', false);
END;
$$;


ALTER FUNCTION "badra_core"."check_login_device"("p_device_id" "text", "p_device_name" "text", "p_device_model" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."check_payment_request_status"("p_request_id" "uuid", "p_merchant_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_request badra_core.payment_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_request.merchant_id != p_merchant_id THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب لا يخص متجرك');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'status', v_request.status,
    'amount', v_request.amount,
    'order_ref', v_request.order_ref,
    'created_at', v_request.created_at,
    'expires_at', v_request.expires_at,
    'approved_at', v_request.approved_at,
    'rejected_at', v_request.rejected_at,
    'tx_id', v_request.tx_id
  );
END;
$$;


ALTER FUNCTION "badra_core"."check_payment_request_status"("p_request_id" "uuid", "p_merchant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."check_security_setup"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_has_pin BOOLEAN;
  v_has_device BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'setup_required', true);
  END IF;

  SELECT security_code IS NOT NULL AND security_code != '' INTO v_has_pin
  FROM badra_core.profiles WHERE user_id = v_user_id;

  SELECT COUNT(*) > 0 INTO v_has_device
  FROM badra_core.user_devices WHERE user_id = v_user_id AND carved_at IS NOT NULL;

  RETURN jsonb_build_object(
    'success', true,
    'has_pin', v_has_pin,
    'has_device', v_has_device,
    'setup_required', NOT v_has_pin
  );
END;
$$;


ALTER FUNCTION "badra_core"."check_security_setup"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."cleanup_pending_on_auth_insert"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
BEGIN
  DELETE FROM badra_core.pending_users
  WHERE replace(phone, '+', '') = replace(NEW.phone, '+', '');
  RETURN NEW;
END;
$$;


ALTER FUNCTION "badra_core"."cleanup_pending_on_auth_insert"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."clear_attempts"("p_attempt_type" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  DELETE FROM badra_core.challenge_attempts
  WHERE user_id = v_user_id AND attempt_type = p_attempt_type;

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "badra_core"."clear_attempts"("p_attempt_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."confirm_payment_request"("p_request_id" "uuid", "p_merchant_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_request badra_core.payment_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
    AND merchant_id = p_merchant_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', '?????? ?????????? ?????? ?????????? ???? ???? ?????? ?????? ????????????'
    );
  END IF;

  IF v_request.used THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', '???? ?????????? ?????? ?????????? ????????????'
    );
  END IF;

  IF v_request.status != 'approved' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', '?????????? ???? ?????? ???????????????? ???????? ??????',
      'status', v_request.status
    );
  END IF;

  UPDATE badra_core.payment_requests
  SET used = true
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'request_id', v_request.id,
    'amount', v_request.amount,
    'order_ref', v_request.order_ref,
    'status', 'approved',
    'tx_id', v_request.tx_id,
    'approved_at', v_request.approved_at
  );
END;
$$;


ALTER FUNCTION "badra_core"."confirm_payment_request"("p_request_id" "uuid", "p_merchant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."create_payment_request"("p_merchant_id" "uuid", "p_user_phone" "text", "p_amount" numeric, "p_order_ref" "text", "p_items" "jsonb" DEFAULT '[]'::"jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
    v_merchant badra_core.merchants%ROWTYPE;
    v_profile badra_core.profiles%ROWTYPE;
    v_request_id UUID;
    c_user_error CONSTANT TEXT := 'تعذر إنشاء الطلب. تحقق من بيانات المستخدم';
BEGIN
    SELECT * INTO v_merchant FROM badra_core.merchants WHERE id = p_merchant_id AND is_active = true;
    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'المتجر غير موجود أو غير نشط');
    END IF;

    SELECT * INTO v_profile FROM badra_core.profiles WHERE phone = p_user_phone AND is_active = true;
    IF NOT FOUND THEN RETURN jsonb_build_object('success', false, 'error', c_user_error); END IF;

    IF v_profile.security_code IS NULL OR v_profile.security_code = '' THEN
        RETURN jsonb_build_object('success', false, 'error', c_user_error);
    END IF;

    IF v_profile.balance < p_amount THEN
        RETURN jsonb_build_object('success', false, 'error', c_user_error);
    END IF;

    -- حماية: منع إنشاء طلبات متتالية سريعة من نفس المتجر لنفس المستخدم
    IF EXISTS (
        SELECT 1 FROM badra_core.payment_requests
        WHERE merchant_id = p_merchant_id
          AND user_id = v_profile.user_id
          AND created_at > now() - interval '30 seconds'
    ) THEN
        RETURN jsonb_build_object('success', false, 'error', 'طلب موجود مسبقاً، الرجاء الانتظار');
    END IF;

    IF EXISTS (SELECT 1 FROM badra_core.payment_requests WHERE merchant_id = p_merchant_id AND order_ref = p_order_ref) THEN
        RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب موجود مسبقاً');
    END IF;

    IF (SELECT COUNT(*) FROM badra_core.payment_requests WHERE user_id = v_profile.user_id AND status = 'pending' AND expires_at > now()) >= 5 THEN
        RETURN jsonb_build_object('success', false, 'error', c_user_error);
    END IF;

    INSERT INTO badra_core.payment_requests (merchant_id, user_id, amount, order_ref, items, status, expires_at)
    VALUES (p_merchant_id, v_profile.user_id, p_amount, p_order_ref, p_items, 'pending', now() + interval '10 minutes')
    RETURNING id INTO v_request_id;

    RETURN jsonb_build_object('success', true, 'request_id', v_request_id, 'status', 'pending', 'expires_in_seconds', 600);
END;
$$;


ALTER FUNCTION "badra_core"."create_payment_request"("p_merchant_id" "uuid", "p_user_phone" "text", "p_amount" numeric, "p_order_ref" "text", "p_items" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "badra_core"."create_payment_request"("p_merchant_id" "uuid", "p_user_phone" "text", "p_amount" numeric, "p_order_ref" "text", "p_items" "jsonb") IS 'SECURITY: Generic error messages prevent user enumeration and balance disclosure.';



CREATE OR REPLACE FUNCTION "badra_core"."create_pending_user"("p_name" "text", "p_phone" "text", "p_password" "text", "p_ip" "text", "p_device_name" "text", "p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
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
$$;


ALTER FUNCTION "badra_core"."create_pending_user"("p_name" "text", "p_phone" "text", "p_password" "text", "p_ip" "text", "p_device_name" "text", "p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."execute_approved_payment"("p_user_id" "uuid", "p_request_id" "uuid", "p_amount" numeric, "p_merchant_id" "uuid", "p_order_ref" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_request badra_core.payment_requests%ROWTYPE;
  v_merchant_name TEXT;
  v_new_balance NUMERIC;
  v_tx_id UUID;
BEGIN
  -- Lock the payment request row
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_request.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب لم يعد معلقاً');
  END IF;

  IF v_request.expires_at <= now() THEN
    UPDATE badra_core.payment_requests
    SET status = 'expired'
    WHERE id = p_request_id;
    RETURN jsonb_build_object('success', false, 'error', 'انتهت صلاحية الطلب');
  END IF;

  -- Lock and check user balance
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'المستخدم غير موجود');
  END IF;

  IF v_profile.balance < p_amount THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'الرصيد غير كاف',
      'balance', v_profile.balance, 'required', p_amount
    );
  END IF;

  -- Deduct balance
  v_new_balance := v_profile.balance - p_amount;

  UPDATE badra_core.profiles
  SET balance = v_new_balance, updated_at = now()
  WHERE user_id = p_user_id;

  -- Get merchant name
  SELECT name INTO v_merchant_name
  FROM badra_core.merchants
  WHERE id = p_merchant_id;

  -- Create transaction record
  INSERT INTO badra_core.transactions_v2 (
    user_id, is_in, amount, title, status, date, notes, ref, store
  ) VALUES (
    p_user_id, 0, p_amount,
    'مشتريات من ' || COALESCE(v_merchant_name, 'متجر'),
    'completed', now(),
    'order_ref: ' || p_order_ref,
    p_order_ref,
    COALESCE(v_merchant_name, '')
  ) RETURNING id INTO v_tx_id;

  -- Update payment request
  UPDATE badra_core.payment_requests
  SET status = 'approved', approved_at = now(), tx_id = v_tx_id
  WHERE id = p_request_id;

  RETURN jsonb_build_object(
    'success', true,
    'transaction_id', v_tx_id,
    'new_balance', v_new_balance,
    'old_balance', v_profile.balance,
    'amount', p_amount
  );
END;
$$;


ALTER FUNCTION "badra_core"."execute_approved_payment"("p_user_id" "uuid", "p_request_id" "uuid", "p_amount" numeric, "p_merchant_id" "uuid", "p_order_ref" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_deposit_data"() RETURNS "text"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_config badra_core.deposit_config%ROWTYPE;
BEGIN
  SELECT * INTO v_config
  FROM badra_core.deposit_config
  WHERE is_active = true
  ORDER BY updated_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN '0#0#0#0#Unknown';
  END IF;

  RETURN v_config.bank1 || '#' ||
         v_config.bank2 || '#' ||
         v_config.bank3 || '#' ||
         v_config.bank4 || '#' ||
         v_config.account_holder_name;
END;
$$;


ALTER FUNCTION "badra_core"."get_deposit_data"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_device_public_key"("p_user_id" "uuid", "p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
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


ALTER FUNCTION "badra_core"."get_device_public_key"("p_user_id" "uuid", "p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_merchant_webhook_info"("p_merchant_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_merchant badra_core.merchants%ROWTYPE;
BEGIN
  SELECT * INTO v_merchant
  FROM badra_core.merchants
  WHERE id = p_merchant_id AND is_active = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false);
  END IF;

  IF v_merchant.webhook_url IS NULL OR v_merchant.webhook_url = '' THEN
    RETURN jsonb_build_object('success', false, 'reason', 'no_webhook');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'webhook_url', v_merchant.webhook_url,
    'webhook_secret', v_merchant.webhook_secret
  );
END;
$$;


ALTER FUNCTION "badra_core"."get_merchant_webhook_info"("p_merchant_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_my_activation_code"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_code TEXT;
  v_expires_at TIMESTAMPTZ;
  v_phone TEXT;
BEGIN
  SELECT ac.code, ac.expires_at, ac.phone
    INTO v_code, v_expires_at, v_phone
  FROM badra_core.activation_codes ac
  WHERE ac.user_id = auth.uid()
    AND ac.used = false
    AND ac.expires_at > now()
  ORDER BY ac.created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'message', 'لا يوجد كود تفعيل صالح');
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'code', v_code,
    'phone', v_phone,
    'expires_in_minutes', extract(epoch from (v_expires_at - now())) / 60
  );
END;
$$;


ALTER FUNCTION "badra_core"."get_my_activation_code"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_my_pending_requests"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', pr.id,
      'merchant_name', m.name,
      'amount', pr.amount,
      'order_ref', pr.order_ref,
      'items', pr.items,
      'expires_at', pr.expires_at,
      'created_at', pr.created_at,
      'expires_in_seconds', extract(epoch from (pr.expires_at - now()))
    ) ORDER BY pr.created_at DESC
  ), '[]'::jsonb) INTO v_result
  FROM badra_core.payment_requests pr
  JOIN badra_core.merchants m ON m.id = pr.merchant_id
  WHERE pr.user_id = auth.uid()
    AND pr.status = 'pending'
    AND pr.expires_at > now();

  RETURN v_result;
END;
$$;


ALTER FUNCTION "badra_core"."get_my_pending_requests"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_my_profile"("p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_check JSONB;
BEGIN
  v_check := badra_core.verify_authorized_device(p_device_id);
  IF v_check->>'success' != 'true' THEN
    RETURN jsonb_build_object('error', COALESCE(v_check->>'error', 'الجهاز غير مصرح'));
  END IF;

  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profile not found');
  END IF;

  RETURN jsonb_build_object(
    'name', v_profile.name,
    'balance', v_profile.balance,
    'is_active', v_profile.is_active,
    'created_at', v_profile.created_at
  );
END;
$$;


ALTER FUNCTION "badra_core"."get_my_profile"("p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_my_security_code"("p_phone" "text") RETURNS "text"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
    v_code TEXT;
BEGIN
    SELECT security_code INTO v_code FROM badra_core.profiles WHERE phone = p_phone;
    RETURN v_code;
END;
$$;


ALTER FUNCTION "badra_core"."get_my_security_code"("p_phone" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_my_transactions_fast"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_result JSONB;
BEGIN
  SELECT jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'is_in', t.is_in,
      'ref', t.ref,
      'store', t.store,
      'title', t.title,
      'amount', t.amount,
      'date', t.date,
      'status', t.status,
      'debtor', t.debtor,
      'creditor', t.creditor,
      'notes', t.notes
    ) ORDER BY t.date DESC
  ) INTO v_result
  FROM badra_core.transactions_v2 t
  WHERE t.user_id = auth.uid();

  RETURN COALESCE(v_result, '[]'::jsonb);
END;
$$;


ALTER FUNCTION "badra_core"."get_my_transactions_fast"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_my_transactions_paginated"("p_limit" integer DEFAULT 10, "p_offset" integer DEFAULT 0) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_total INTEGER;
  v_transactions JSONB;
BEGIN
  SELECT COUNT(*) INTO v_total
  FROM badra_core.transactions_v2
  WHERE user_id = auth.uid();

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', t.id,
      'is_in', t.is_in,
      'ref', t.ref,
      'store', t.store,
      'title', t.title,
      'amount', t.amount,
      'date', t.date,
      'status', t.status,
      'debtor', t.debtor,
      'creditor', t.creditor,
      'notes', t.notes
    ) ORDER BY t.date DESC
  ), '[]'::jsonb) INTO v_transactions
  FROM badra_core.transactions_v2 t
  WHERE t.user_id = auth.uid()
  ORDER BY t.date DESC
  LIMIT p_limit
  OFFSET p_offset;

  RETURN jsonb_build_object(
    'total_count', v_total,
    'transactions', v_transactions
  );
END;
$$;


ALTER FUNCTION "badra_core"."get_my_transactions_paginated"("p_limit" integer, "p_offset" integer) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_payment_request_by_order_ref"("p_merchant_id" "uuid", "p_order_ref" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
    v_request badra_core.payment_requests%ROWTYPE;
BEGIN
    SELECT * INTO v_request
    FROM badra_core.payment_requests
    WHERE merchant_id = p_merchant_id AND order_ref = p_order_ref
    LIMIT 1;

    IF NOT FOUND THEN
        RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'request_id', v_request.id,
        'status', v_request.status,
        'amount', v_request.amount,
        'order_ref', v_request.order_ref,
        'created_at', v_request.created_at,
        'expires_at', v_request.expires_at,
        'approved_at', v_request.approved_at,
        'rejected_at', v_request.rejected_at,
        'tx_id', v_request.tx_id
    );
END;
$$;


ALTER FUNCTION "badra_core"."get_payment_request_by_order_ref"("p_merchant_id" "uuid", "p_order_ref" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."get_pending_users"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
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
      'password_hash', pu.password_hash,
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


ALTER FUNCTION "badra_core"."get_pending_users"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_code TEXT;
BEGIN
  -- Generate activation code
  v_code := lpad(floor(random() * 1000000)::int::text, 6, '0');

  -- Create profile (is_active=false by default)
  INSERT INTO badra_core.profiles (user_id, name, phone, wallet_id)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'name', ''),
    NEW.phone,
    '101' || NEW.phone
  )
  ON CONFLICT (user_id) DO NOTHING;

  -- Create activation code
  INSERT INTO badra_core.activation_codes (phone, user_id, code, expires_at)
  VALUES (NEW.phone, NEW.id, v_code, now() + interval '24 hours')
  ON CONFLICT (user_id) DO UPDATE
  SET code = EXCLUDED.code, expires_at = EXCLUDED.expires_at, created_at = now();

  RETURN NEW;
END;
$$;


ALTER FUNCTION "badra_core"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."has_carved_device"() RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_count INT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND carved_at IS NOT NULL;

  RETURN jsonb_build_object('success', true, 'has_device', v_count > 0, 'device_count', v_count);
END;
$$;


ALTER FUNCTION "badra_core"."has_carved_device"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."is_admin"() RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core'
    AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM badra_core.admins
    WHERE user_id = auth.uid()
  );
END;
$$;


ALTER FUNCTION "badra_core"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."is_admin_uid"("uid" "uuid") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    AS $$
  SELECT EXISTS (SELECT 1 FROM badra_core.admins WHERE user_id = uid);
$$;


ALTER FUNCTION "badra_core"."is_admin_uid"("uid" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."record_failed_attempt"("p_attempt_type" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  INSERT INTO badra_core.challenge_attempts (user_id, attempt_type)
  VALUES (v_user_id, p_attempt_type);

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "badra_core"."record_failed_attempt"("p_attempt_type" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."register_device_public_key"("p_device_id" "text", "p_public_key_n" "text", "p_public_key_e" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_public_key_n IS NULL OR p_public_key_n = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'المفتاح العام مطلوب');
  END IF;

  UPDATE badra_core.user_devices
  SET public_key_n = p_public_key_n,
      public_key_e = CASE WHEN p_public_key_e IS NULL OR p_public_key_e = '' THEN 'AQAB' ELSE p_public_key_e END,
      key_created_at = now()
  WHERE user_id = v_user_id AND device_id = p_device_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مسجل');
  END IF;

  RETURN jsonb_build_object('success', true, 'message', 'تم تسجيل المفتاح العام');
END;
$$;


ALTER FUNCTION "badra_core"."register_device_public_key"("p_device_id" "text", "p_public_key_n" "text", "p_public_key_e" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."register_fcm_token"("p_fcm_token" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_fcm_token = '' THEN
    RETURN jsonb_build_object('success', false, 'error', 'FCM token فارغ');
  END IF;

  UPDATE badra_core.user_devices
  SET fcm_token = p_fcm_token
  WHERE user_id = v_user_id
    AND id = (
      SELECT id FROM badra_core.user_devices
      WHERE user_id = v_user_id
      ORDER BY last_login DESC NULLS LAST
      LIMIT 1
    );

  IF NOT FOUND THEN
    INSERT INTO badra_core.user_devices (user_id, fcm_token)
    VALUES (v_user_id, p_fcm_token);
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "badra_core"."register_fcm_token"("p_fcm_token" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."reject_payment_request"("p_request_id" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_request badra_core.payment_requests%ROWTYPE;
BEGIN
  SELECT * INTO v_request
  FROM badra_core.payment_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب غير موجود');
  END IF;

  IF v_request.user_id != auth.uid() THEN
    RETURN jsonb_build_object('success', false, 'error', 'هذا الطلب لا يخصك');
  END IF;

  IF v_request.status != 'pending' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الطلب لم يعد معلقاً');
  END IF;

  UPDATE badra_core.payment_requests
  SET status = 'rejected', rejected_at = now()
  WHERE id = p_request_id;

  RETURN jsonb_build_object('success', true, 'message', 'تم رفض الطلب');
END;
$$;


ALTER FUNCTION "badra_core"."reject_payment_request"("p_request_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."reject_pending_user"("p_phone" "text", "p_reason" "text" DEFAULT ''::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_updated INT;
BEGIN
  IF NOT badra_core.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'message', 'غير مصرح. فقط الأدمن يمكنه تنفيذ هذه العملية.');
  END IF;
  UPDATE badra_core.pending_users
  SET status = 'rejected', updated_at = now()
  WHERE replace(phone, '+', '') = replace(p_phone, '+', '') AND status = 'pending';
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('success', false, 'message', 'لم يتم العثور على طلب معلق بهذا الرقم');
  END IF;
  RETURN jsonb_build_object('success', true, 'message', 'تم رفض الطلب');
END;
$$;


ALTER FUNCTION "badra_core"."reject_pending_user"("p_phone" "text", "p_reason" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."set_security_code"("p_new_code" "text", "p_current_code" "text" DEFAULT ''::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'extensions', 'public'
    AS $_$
DECLARE
  v_user_id UUID;
  v_stored_hash TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_new_code !~ '^\d{6}$' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الرقم السري يجب أن يكون 6 أرقام');
  END IF;

  SELECT security_code INTO v_stored_hash
  FROM badra_core.profiles
  WHERE user_id = v_user_id;

  IF v_stored_hash IS NOT NULL AND v_stored_hash != '' THEN
    IF p_current_code = '' THEN
      RETURN jsonb_build_object('success', false, 'error', 'يجب إدخال الرقم السري الحالي لتغييره');
    END IF;

    IF v_stored_hash NOT LIKE '$2%' THEN
      RETURN jsonb_build_object('success', false, 'error', 'يجب إعادة تعيين الرقم السري');
    END IF;

    IF v_stored_hash != crypt(p_current_code, v_stored_hash) THEN
      RETURN jsonb_build_object('success', false, 'error', 'الرقم السري الحالي غير صحيح');
    END IF;
  END IF;

  UPDATE badra_core.profiles
  SET security_code = crypt(p_new_code, extensions.gen_salt('bf', 10)),
      updated_at = now()
  WHERE user_id = v_user_id;

  RETURN jsonb_build_object('success', true);
END;
$_$;


ALTER FUNCTION "badra_core"."set_security_code"("p_new_code" "text", "p_current_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."set_security_codes_for_existing"() RETURNS TABLE("phone_out" "text", "code" "text")
    LANGUAGE "plpgsql"
    AS $$ DECLARE rec RECORD; new_code TEXT; BEGIN FOR rec IN SELECT id, phone FROM badra_core.profiles WHERE security_code IS NULL LOOP new_code := badra_core.generate_security_code(); UPDATE badra_core.profiles SET security_code = new_code WHERE id = rec.id; phone_out := rec.phone; code := new_code; RETURN NEXT; END LOOP; END; $$;


ALTER FUNCTION "badra_core"."set_security_codes_for_existing"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."sync_home_data"("p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public'
    AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_check JSONB;
  v_pending JSONB;
  v_has_device BOOLEAN;
  v_setup_required BOOLEAN;
  v_locked BOOLEAN;
  v_attempt_count INT;
  v_max_attempts INT := 5;
  v_lockout_minutes INT := 30;
BEGIN
  v_check := badra_core.verify_authorized_device(p_device_id);
  IF v_check->>'success' != 'true' THEN
    RETURN jsonb_build_object('error', COALESCE(v_check->>'error', 'الجهاز غير مصرح'));
  END IF;

  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'Profile not found');
  END IF;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', pr.id,
      'merchant_name', m.name,
      'amount', pr.amount,
      'order_ref', pr.order_ref,
      'items', pr.items,
      'expires_at', pr.expires_at,
      'created_at', pr.created_at,
      'expires_in_seconds', extract(epoch from (pr.expires_at - now()))
    ) ORDER BY pr.created_at DESC
  ), '[]'::jsonb) INTO v_pending
  FROM badra_core.payment_requests pr
  JOIN badra_core.merchants m ON m.id = pr.merchant_id
  WHERE pr.user_id = auth.uid()
    AND pr.status = 'pending'
    AND pr.expires_at > now();

  SELECT EXISTS(
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = auth.uid() AND carved_at IS NOT NULL
  ) INTO v_has_device;

  SELECT security_code IS NULL OR security_code = '' INTO v_setup_required
  FROM badra_core.profiles
  WHERE user_id = auth.uid();

  SELECT COUNT(*) INTO v_attempt_count
  FROM badra_core.challenge_attempts
  WHERE user_id = auth.uid()
    AND attempt_type = 'security_code'
    AND attempted_at > now() - (v_lockout_minutes || ' minutes')::INTERVAL;

  v_locked := v_attempt_count >= v_max_attempts;

  RETURN jsonb_build_object(
    'profile', jsonb_build_object(
      'name', v_profile.name,
      'balance', v_profile.balance
    ),
    'pending_requests', v_pending,
    'has_device', v_has_device,
    'setup_required', v_setup_required,
    'locked', v_locked,
    'created_at', v_profile.created_at
  );
END;
$$;


ALTER FUNCTION "badra_core"."sync_home_data"("p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."verify_authorized_device"("p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_ok BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  IF p_device_id IS NULL OR p_device_id = '' OR p_device_id = 'unknown_device_id' THEN
    RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مصرح');
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM badra_core.user_devices
    WHERE user_id = v_user_id AND device_id = p_device_id AND carved_at IS NOT NULL
  ) INTO v_ok;

  IF NOT v_ok THEN
    RETURN jsonb_build_object('success', false, 'error', 'الجهاز غير مصرح');
  END IF;

  RETURN jsonb_build_object('success', true);
END;
$$;


ALTER FUNCTION "badra_core"."verify_authorized_device"("p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."verify_device"("p_device_id" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_user_id UUID;
  v_carved_at TIMESTAMPTZ;
  v_device_name TEXT;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'غير مصرح');
  END IF;

  SELECT carved_at, device_name INTO v_carved_at, v_device_name
  FROM badra_core.user_devices
  WHERE user_id = v_user_id AND device_id = p_device_id;

  IF v_carved_at IS NULL THEN
    RETURN jsonb_build_object('success', false, 'carved', false, 'error', 'الجهاز غير مسجل');
  END IF;

  UPDATE badra_core.user_devices
  SET last_login = now()
  WHERE user_id = v_user_id AND device_id = p_device_id;

  RETURN jsonb_build_object('success', true, 'carved', true, 'carved_at', v_carved_at, 'device_name', v_device_name);
END;
$$;


ALTER FUNCTION "badra_core"."verify_device"("p_device_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."verify_security_code"("p_user_id" "uuid", "p_security_code" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_stored_hash TEXT;
BEGIN
  SELECT security_code INTO v_stored_hash
  FROM badra_core.profiles
  WHERE user_id = p_user_id;

  IF v_stored_hash IS NULL OR v_stored_hash = '' THEN
    RETURN jsonb_build_object('valid', false, 'error', 'لم يتم تعيين الرقم السري');
  END IF;

  IF v_stored_hash = crypt(p_security_code, v_stored_hash) THEN
    RETURN jsonb_build_object('valid', true);
  END IF;

  RETURN jsonb_build_object('valid', false, 'error', 'الرقم السري غير صحيح');
END;
$$;


ALTER FUNCTION "badra_core"."verify_security_code"("p_user_id" "uuid", "p_security_code" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "badra_core"."verify_store_identity"("p_phone" "text", "p_name" "text", "p_created_at" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'badra_core', 'public', 'extensions'
    AS $$
DECLARE
  v_profile badra_core.profiles%ROWTYPE;
  v_auth_created TIMESTAMPTZ;
  v_ddmm TEXT;
  v_attempts INT;
  c_error CONSTANT TEXT := 'فشل التحقق من الهوية';
BEGIN
  -- Lockout: max 10 attempts per phone per hour (regardless of success path)
  SELECT COUNT(*) INTO v_attempts
  FROM badra_core.identity_verify_attempts
  WHERE phone = p_phone
    AND attempted_at > now() - interval '1 hour';

  IF v_attempts >= 10 THEN
    RETURN jsonb_build_object('success', false, 'error', c_error);
  END IF;

  -- Record this attempt
  INSERT INTO badra_core.identity_verify_attempts (phone) VALUES (p_phone);

  -- Fetch profile
  SELECT * INTO v_profile
  FROM badra_core.profiles
  WHERE phone = p_phone AND is_active = true;

  -- GENERIC failure for: user not found
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', c_error);
  END IF;

  -- GENERIC failure for: name mismatch
  IF v_profile.name != p_name THEN
    RETURN jsonb_build_object('success', false, 'error', c_error);
  END IF;

  SELECT created_at INTO v_auth_created
  FROM auth.users WHERE id = v_profile.user_id;

  IF v_auth_created IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', c_error);
  END IF;

  v_ddmm := to_char(v_auth_created, 'DD/MM');

  -- GENERIC failure for: date mismatch
  IF v_ddmm != p_created_at THEN
    RETURN jsonb_build_object('success', false, 'error', c_error);
  END IF;

  -- Success: clear attempts for this phone
  DELETE FROM badra_core.identity_verify_attempts WHERE phone = p_phone;

  RETURN jsonb_build_object('success', true, 'user_id', v_profile.user_id);
END;
$$;


ALTER FUNCTION "badra_core"."verify_store_identity"("p_phone" "text", "p_name" "text", "p_created_at" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "badra_core"."verify_store_identity"("p_phone" "text", "p_name" "text", "p_created_at" "text") IS 'SECURITY: Generic errors + phone-keyed lockout (10/hour) prevent enumeration.';


SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "badra_core"."activation_codes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "phone" "text" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "code" "text" NOT NULL,
    "used" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "expires_at" timestamp with time zone DEFAULT ("now"() + '01:30:00'::interval) NOT NULL,
    "failed_attempts" integer DEFAULT 0
);


ALTER TABLE "badra_core"."activation_codes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."admins" (
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "device_id" "text" DEFAULT ''::"text",
    "device_name" "text" DEFAULT ''::"text",
    "last_login" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "badra_core"."admins" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."audit_log" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "action" "text" NOT NULL,
    "table_name" "text" NOT NULL,
    "record_id" "uuid",
    "old_values" "jsonb",
    "new_values" "jsonb",
    "admin_id" "uuid",
    "admin_name" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "badra_core"."audit_log" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."balance_summary" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "total_received" numeric DEFAULT 0 NOT NULL,
    "total_distributed" numeric DEFAULT 0 NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "badra_core"."balance_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."bank_accounts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "bank_name" "text" NOT NULL,
    "account_number_encrypted" "text" NOT NULL,
    "account_holder_name" "text" DEFAULT ''::"text",
    "is_default" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "badra_core"."bank_accounts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."challenge_attempts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "attempt_type" "text" NOT NULL,
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "challenge_attempts_attempt_type_check" CHECK (("attempt_type" = 'security_code'::"text"))
);


ALTER TABLE "badra_core"."challenge_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."deposit_config" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "bank1" "text" DEFAULT ''::"text",
    "bank2" "text" DEFAULT ''::"text",
    "bank3" "text" DEFAULT ''::"text",
    "bank4" "text" DEFAULT ''::"text",
    "account_holder_name" "text" DEFAULT ''::"text",
    "is_active" boolean DEFAULT true,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "badra_core"."deposit_config" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."deposit_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "amount" numeric NOT NULL,
    "bank_name" "text" NOT NULL,
    "type" "text" DEFAULT 'manual'::"text" NOT NULL,
    "status" "text" DEFAULT 'approved'::"text" NOT NULL,
    "receipt_number" "text",
    "notes" "text" DEFAULT ''::"text",
    "admin_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "admin_name" "text" DEFAULT ''::"text",
    CONSTRAINT "deposit_requests_bank_name_check" CHECK (("bank_name" = ANY (ARRAY['العمقي'::"text", 'الكرايمي'::"text", 'القطيبي'::"text", 'البسيري'::"text"]))),
    CONSTRAINT "deposit_requests_status_check" CHECK (("status" = 'approved'::"text")),
    CONSTRAINT "deposit_requests_type_check" CHECK (("type" = 'manual'::"text"))
);


ALTER TABLE "badra_core"."deposit_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."identity_verify_attempts" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "phone" "text" NOT NULL,
    "attempted_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "badra_core"."identity_verify_attempts" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."merchants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "api_key_hash" "text" NOT NULL,
    "api_key_prefix" "text" NOT NULL,
    "webhook_url" "text" DEFAULT ''::"text",
    "webhook_secret" "text" DEFAULT ''::"text",
    "is_active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "badra_core"."merchants" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."payment_requests" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "merchant_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "amount" numeric NOT NULL,
    "order_ref" "text" NOT NULL,
    "items" "jsonb" DEFAULT '[]'::"jsonb",
    "status" "text" DEFAULT 'pending'::"text",
    "expires_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "approved_at" timestamp with time zone,
    "rejected_at" timestamp with time zone,
    "tx_id" "uuid",
    "used" boolean DEFAULT false NOT NULL,
    CONSTRAINT "payment_requests_amount_check" CHECK (("amount" > (0)::numeric)),
    CONSTRAINT "payment_requests_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text", 'expired'::"text"])))
);


ALTER TABLE "badra_core"."payment_requests" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."pending_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "phone" "text" NOT NULL,
    "password_hash" "text" NOT NULL,
    "ip" "text" DEFAULT ''::"text",
    "device_name" "text" DEFAULT ''::"text",
    "device_id" "text" DEFAULT ''::"text",
    "status" "text" DEFAULT 'pending'::"text",
    "activation_code" "text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "pending_users_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "badra_core"."pending_users" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."profiles" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "phone" "text" NOT NULL,
    "name" "text" NOT NULL,
    "wallet_id" "text" DEFAULT ''::"text" NOT NULL,
    "balance" numeric DEFAULT 0 NOT NULL,
    "is_active" boolean DEFAULT false NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "failed_login_count" integer DEFAULT 0,
    "locked_until" timestamp with time zone,
    "security_code" "text"
);


ALTER TABLE "badra_core"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."transactions_v2" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "is_in" integer DEFAULT 0,
    "ref" "text" DEFAULT ''::"text",
    "store" "text" DEFAULT ''::"text",
    "title" "text" DEFAULT ''::"text",
    "amount" numeric NOT NULL,
    "date" timestamp with time zone NOT NULL,
    "status" "text" DEFAULT 'completed'::"text",
    "debtor" "text" DEFAULT ''::"text",
    "creditor" "text" DEFAULT ''::"text",
    "notes" "text" DEFAULT ''::"text",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "deposit_request_id" "uuid",
    CONSTRAINT "transactions_v2_is_in_check" CHECK (("is_in" = ANY (ARRAY[0, 1])))
);


ALTER TABLE "badra_core"."transactions_v2" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "badra_core"."user_devices" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "device_name" "text" DEFAULT ''::"text",
    "device_id" "text" DEFAULT ''::"text",
    "ip" "text" DEFAULT ''::"text",
    "last_login" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "fcm_token" "text" DEFAULT ''::"text",
    "carved_at" timestamp with time zone,
    "device_model" "text" DEFAULT ''::"text",
    "public_key_n" "text",
    "public_key_e" "text",
    "key_created_at" timestamp with time zone,
    "public_key_x" "text" DEFAULT ''::"text",
    "public_key_y" "text" DEFAULT ''::"text",
    "key_source" "text" DEFAULT 'software'::"text"
);


ALTER TABLE "badra_core"."user_devices" OWNER TO "postgres";


ALTER TABLE ONLY "badra_core"."activation_codes"
    ADD CONSTRAINT "activation_codes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."activation_codes"
    ADD CONSTRAINT "activation_codes_user_id_unique" UNIQUE ("user_id");



ALTER TABLE ONLY "badra_core"."admins"
    ADD CONSTRAINT "admins_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "badra_core"."audit_log"
    ADD CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."balance_summary"
    ADD CONSTRAINT "balance_summary_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."bank_accounts"
    ADD CONSTRAINT "bank_accounts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."challenge_attempts"
    ADD CONSTRAINT "challenge_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."deposit_config"
    ADD CONSTRAINT "deposit_config_pkey" PRIMARY KEY ("id");



ALTER TABLE "badra_core"."deposit_requests"
    ADD CONSTRAINT "deposit_requests_amount_check" CHECK ((("amount" >= (500)::numeric) AND ("amount" <= (250000)::numeric))) NOT VALID;



ALTER TABLE ONLY "badra_core"."deposit_requests"
    ADD CONSTRAINT "deposit_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."identity_verify_attempts"
    ADD CONSTRAINT "identity_verify_attempts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."merchants"
    ADD CONSTRAINT "merchants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."payment_requests"
    ADD CONSTRAINT "payment_requests_merchant_id_order_ref_key" UNIQUE ("merchant_id", "order_ref");



ALTER TABLE ONLY "badra_core"."payment_requests"
    ADD CONSTRAINT "payment_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."pending_users"
    ADD CONSTRAINT "pending_users_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "badra_core"."pending_users"
    ADD CONSTRAINT "pending_users_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."profiles"
    ADD CONSTRAINT "profiles_phone_key" UNIQUE ("phone");



ALTER TABLE ONLY "badra_core"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."profiles"
    ADD CONSTRAINT "profiles_user_id_key" UNIQUE ("user_id");



ALTER TABLE ONLY "badra_core"."profiles"
    ADD CONSTRAINT "profiles_wallet_id_key" UNIQUE ("wallet_id");



ALTER TABLE ONLY "badra_core"."transactions_v2"
    ADD CONSTRAINT "transactions_v2_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."user_devices"
    ADD CONSTRAINT "user_devices_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "badra_core"."user_devices"
    ADD CONSTRAINT "user_devices_user_device_unique" UNIQUE ("user_id", "device_id");



CREATE INDEX "idx_activation_codes_phone" ON "badra_core"."activation_codes" USING "btree" ("phone");



CREATE INDEX "idx_activation_codes_user_id" ON "badra_core"."activation_codes" USING "btree" ("user_id");



CREATE INDEX "idx_bank_accounts_user_id" ON "badra_core"."bank_accounts" USING "btree" ("user_id");



CREATE INDEX "idx_challenge_attempts_user" ON "badra_core"."challenge_attempts" USING "btree" ("user_id", "attempt_type", "attempted_at");



CREATE INDEX "idx_deposit_config_active_updated" ON "badra_core"."deposit_config" USING "btree" ("is_active", "updated_at" DESC) WHERE ("is_active" = true);



CREATE INDEX "idx_deposit_requests_admin_id" ON "badra_core"."deposit_requests" USING "btree" ("admin_id");



CREATE INDEX "idx_deposit_requests_created_at" ON "badra_core"."deposit_requests" USING "btree" ("created_at" DESC);



CREATE UNIQUE INDEX "idx_deposit_requests_receipt_number" ON "badra_core"."deposit_requests" USING "btree" ("receipt_number") WHERE (("receipt_number" IS NOT NULL) AND ("receipt_number" <> ''::"text"));



CREATE INDEX "idx_deposit_requests_user_id" ON "badra_core"."deposit_requests" USING "btree" ("user_id");



CREATE INDEX "idx_identity_verify_attempts_phone" ON "badra_core"."identity_verify_attempts" USING "btree" ("phone", "attempted_at");



CREATE UNIQUE INDEX "idx_merchants_api_key_prefix" ON "badra_core"."merchants" USING "btree" ("api_key_prefix");



CREATE INDEX "idx_payment_requests_expires" ON "badra_core"."payment_requests" USING "btree" ("expires_at");



CREATE INDEX "idx_payment_requests_merchant_id" ON "badra_core"."payment_requests" USING "btree" ("merchant_id");



CREATE INDEX "idx_payment_requests_status" ON "badra_core"."payment_requests" USING "btree" ("status");



CREATE INDEX "idx_payment_requests_used" ON "badra_core"."payment_requests" USING "btree" ("used") WHERE ("used" = false);



CREATE INDEX "idx_payment_requests_user_id" ON "badra_core"."payment_requests" USING "btree" ("user_id");



CREATE INDEX "idx_pending_users_phone" ON "badra_core"."pending_users" USING "btree" ("phone");



CREATE INDEX "idx_pending_users_status" ON "badra_core"."pending_users" USING "btree" ("status");



CREATE INDEX "idx_profiles_user_id" ON "badra_core"."profiles" USING "btree" ("user_id");



CREATE INDEX "idx_transactions_v2_deposit_request_id" ON "badra_core"."transactions_v2" USING "btree" ("deposit_request_id");



CREATE INDEX "idx_transactions_v2_user_date" ON "badra_core"."transactions_v2" USING "btree" ("user_id", "date" DESC);



CREATE INDEX "idx_transactions_v2_user_id" ON "badra_core"."transactions_v2" USING "btree" ("user_id");



CREATE INDEX "idx_transactions_v2_user_status" ON "badra_core"."transactions_v2" USING "btree" ("user_id", "status");



CREATE INDEX "idx_user_devices_user_id" ON "badra_core"."user_devices" USING "btree" ("user_id");



ALTER TABLE ONLY "badra_core"."activation_codes"
    ADD CONSTRAINT "activation_codes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "badra_core"."admins"
    ADD CONSTRAINT "admins_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "badra_core"."audit_log"
    ADD CONSTRAINT "audit_log_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "badra_core"."bank_accounts"
    ADD CONSTRAINT "bank_accounts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "badra_core"."challenge_attempts"
    ADD CONSTRAINT "challenge_attempts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "badra_core"."deposit_requests"
    ADD CONSTRAINT "deposit_requests_admin_id_fkey" FOREIGN KEY ("admin_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "badra_core"."deposit_requests"
    ADD CONSTRAINT "deposit_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "badra_core"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "badra_core"."payment_requests"
    ADD CONSTRAINT "payment_requests_merchant_id_fkey" FOREIGN KEY ("merchant_id") REFERENCES "badra_core"."merchants"("id");



ALTER TABLE ONLY "badra_core"."payment_requests"
    ADD CONSTRAINT "payment_requests_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "badra_core"."profiles"("user_id");



ALTER TABLE ONLY "badra_core"."profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "badra_core"."transactions_v2"
    ADD CONSTRAINT "transactions_v2_deposit_request_id_fkey" FOREIGN KEY ("deposit_request_id") REFERENCES "badra_core"."deposit_requests"("id");



ALTER TABLE ONLY "badra_core"."transactions_v2"
    ADD CONSTRAINT "transactions_v2_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "badra_core"."profiles"("user_id") ON DELETE CASCADE;



ALTER TABLE ONLY "badra_core"."user_devices"
    ADD CONSTRAINT "user_devices_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE "badra_core"."activation_codes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "admin_balance_summary_insert" ON "badra_core"."balance_summary" FOR INSERT TO "authenticated" WITH CHECK ((((( SELECT "auth"."jwt"() AS "jwt") -> 'app_metadata'::"text") ->> 'role'::"text") = 'admin'::"text"));



CREATE POLICY "admin_balance_summary_select" ON "badra_core"."balance_summary" FOR SELECT TO "authenticated" USING ((((( SELECT "auth"."jwt"() AS "jwt") -> 'app_metadata'::"text") ->> 'role'::"text") = 'admin'::"text"));



CREATE POLICY "admin_balance_summary_update" ON "badra_core"."balance_summary" FOR UPDATE TO "authenticated" USING ((((( SELECT "auth"."jwt"() AS "jwt") -> 'app_metadata'::"text") ->> 'role'::"text") = 'admin'::"text")) WITH CHECK ((((( SELECT "auth"."jwt"() AS "jwt") -> 'app_metadata'::"text") ->> 'role'::"text") = 'admin'::"text"));



CREATE POLICY "admin_deposit_config_all" ON "badra_core"."deposit_config" TO "authenticated" USING ((((( SELECT "auth"."jwt"() AS "jwt") -> 'app_metadata'::"text") ->> 'role'::"text") = 'admin'::"text")) WITH CHECK ((((( SELECT "auth"."jwt"() AS "jwt") -> 'app_metadata'::"text") ->> 'role'::"text") = 'admin'::"text"));



CREATE POLICY "admin_deposit_requests_insert" ON "badra_core"."deposit_requests" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() IN ( SELECT "admins"."user_id"
   FROM "badra_core"."admins")));



CREATE POLICY "admin_only_activation_codes" ON "badra_core"."activation_codes" USING ("badra_core"."is_admin_uid"("auth"."uid"()));



CREATE POLICY "admin_only_audit_log" ON "badra_core"."audit_log" USING ("badra_core"."is_admin_uid"("auth"."uid"()));



CREATE POLICY "admin_only_merchants" ON "badra_core"."merchants" USING ("badra_core"."is_admin_uid"("auth"."uid"()));



CREATE POLICY "admin_only_pending_users" ON "badra_core"."pending_users" USING ("badra_core"."is_admin_uid"("auth"."uid"()));



CREATE POLICY "admin_profiles_all" ON "badra_core"."profiles" TO "authenticated" USING ("badra_core"."is_admin"());



CREATE POLICY "admin_transactions_v2_insert" ON "badra_core"."transactions_v2" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() IN ( SELECT "admins"."user_id"
   FROM "badra_core"."admins")));



CREATE POLICY "admin_transactions_v2_select" ON "badra_core"."transactions_v2" FOR SELECT TO "authenticated" USING ("badra_core"."is_admin"());



ALTER TABLE "badra_core"."admins" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "badra_core"."audit_log" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "badra_core"."balance_summary" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "balance_summary_admin_only" ON "badra_core"."balance_summary" FOR SELECT USING ("badra_core"."is_admin_uid"("auth"."uid"()));



ALTER TABLE "badra_core"."bank_accounts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "badra_core"."challenge_attempts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "challenge_attempts_select_own" ON "badra_core"."challenge_attempts" FOR SELECT TO "authenticated" USING (("user_id" = "auth"."uid"()));



ALTER TABLE "badra_core"."deposit_config" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "deposit_config_admin_only" ON "badra_core"."deposit_config" USING ("badra_core"."is_admin_uid"("auth"."uid"()));



ALTER TABLE "badra_core"."deposit_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "badra_core"."identity_verify_attempts" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "identity_verify_attempts_select_own_phone" ON "badra_core"."identity_verify_attempts" FOR SELECT TO "authenticated" USING (("phone" = ("auth"."jwt"() ->> 'phone'::"text")));



ALTER TABLE "badra_core"."merchants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "badra_core"."payment_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "badra_core"."pending_users" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "badra_core"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "reject_own_pending_requests" ON "badra_core"."payment_requests" FOR UPDATE USING ((("user_id" = "auth"."uid"()) AND ("status" = 'pending'::"text"))) WITH CHECK ((("user_id" = "auth"."uid"()) AND ("status" = 'rejected'::"text")));



CREATE POLICY "select_admins" ON "badra_core"."admins" FOR SELECT USING ("badra_core"."is_admin"());



CREATE POLICY "select_deposit_requests" ON "badra_core"."deposit_requests" FOR SELECT USING ("badra_core"."is_admin"());



CREATE POLICY "select_own_bank_accounts" ON "badra_core"."bank_accounts" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "select_own_payment_requests" ON "badra_core"."payment_requests" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "select_own_profile" ON "badra_core"."profiles" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "select_own_transactions_v2" ON "badra_core"."transactions_v2" FOR SELECT USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



ALTER TABLE "badra_core"."transactions_v2" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_activation_codes_select" ON "badra_core"."activation_codes" FOR SELECT TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "user_deposit_config_select" ON "badra_core"."deposit_config" FOR SELECT TO "authenticated" USING (("is_active" = true));



ALTER TABLE "badra_core"."user_devices" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "user_devices_select_own" ON "badra_core"."user_devices" FOR SELECT USING (("user_id" = "auth"."uid"()));



CREATE POLICY "user_profiles_update" ON "badra_core"."profiles" FOR UPDATE TO "authenticated" USING (("user_id" = ( SELECT "auth"."uid"() AS "uid"))) WITH CHECK (("user_id" = ( SELECT "auth"."uid"() AS "uid")));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "badra_core"."payment_requests";



GRANT USAGE ON SCHEMA "badra_core" TO "anon";
GRANT USAGE ON SCHEMA "badra_core" TO "authenticated";
GRANT USAGE ON SCHEMA "badra_core" TO "service_role";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."activate_user"("p_phone" "text", "p_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."activate_user"("p_phone" "text", "p_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."activate_user"("p_phone" "text", "p_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_approve_finish"("p_phone" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_approve_finish"("p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_approve_finish"("p_phone" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text", "p_user_id" "uuid", "p_device_id" "text", "p_device_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text", "p_user_id" "uuid", "p_device_id" "text", "p_device_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_approve_pending_user"("p_phone" "text", "p_user_id" "uuid", "p_device_id" "text", "p_device_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_cleanup_expired_codes"("p_older_than_hours" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_cleanup_expired_codes"("p_older_than_hours" integer) TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_cleanup_expired_codes"("p_older_than_hours" integer) TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_count_active_users"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_count_active_users"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_count_active_users"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_count_pending_users"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_count_pending_users"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_count_pending_users"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_create_merchant"("p_name" "text", "p_webhook_url" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_create_merchant"("p_name" "text", "p_webhook_url" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_create_merchant"("p_name" "text", "p_webhook_url" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_delete_pending_user"("p_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_delete_pending_user"("p_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_delete_pending_user"("p_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text", "p_user_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text", "p_user_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_fetch_activation_code"("p_phone" "text", "p_user_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_get_deposit_records"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_get_deposit_records"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_get_deposit_records"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_get_last_transactions"("p_limit" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_get_last_transactions"("p_limit" integer) TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_get_last_transactions"("p_limit" integer) TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_get_pending_user_by_phone"("p_phone" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_get_pending_user_by_phone"("p_phone" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_get_pending_user_by_phone"("p_phone" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_get_sum"("p_is_in" integer) FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_get_sum"("p_is_in" integer) TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_get_sum"("p_is_in" integer) TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_get_total_balance"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_get_total_balance"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_get_total_balance"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_get_trading_volume"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_get_trading_volume"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_get_trading_volume"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_list_merchants"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_list_merchants"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_list_merchants"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_manual_deposit"("p_wallet_id" "text", "p_phone" "text", "p_name" "text", "p_amount" numeric, "p_bank_name" "text", "p_receipt_number" "text", "p_notes" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_manual_deposit"("p_wallet_id" "text", "p_phone" "text", "p_name" "text", "p_amount" numeric, "p_bank_name" "text", "p_receipt_number" "text", "p_notes" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_manual_deposit"("p_wallet_id" "text", "p_phone" "text", "p_name" "text", "p_amount" numeric, "p_bank_name" "text", "p_receipt_number" "text", "p_notes" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_toggle_merchant"("p_merchant_id" "uuid", "p_is_active" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_toggle_merchant"("p_merchant_id" "uuid", "p_is_active" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_toggle_merchant"("p_merchant_id" "uuid", "p_is_active" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."admin_verify_device"("p_device_id" "text", "p_device_name" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."admin_verify_device"("p_device_id" "text", "p_device_name" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."admin_verify_device"("p_device_id" "text", "p_device_name" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."approve_payment_request_v2"("p_request_id" "uuid", "p_challenge_code" "text", "p_device_id" "text", "p_security_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."approve_payment_request_v2"("p_request_id" "uuid", "p_challenge_code" "text", "p_device_id" "text", "p_security_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."approve_payment_request_v2"("p_request_id" "uuid", "p_challenge_code" "text", "p_device_id" "text", "p_security_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."carve_device"("p_device_id" "text", "p_device_name" "text", "p_device_model" "text", "p_public_key_n" "text", "p_public_key_e" "text", "p_public_key_x" "text", "p_public_key_y" "text", "p_key_source" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."carve_device"("p_device_id" "text", "p_device_name" "text", "p_device_model" "text", "p_public_key_n" "text", "p_public_key_e" "text", "p_public_key_x" "text", "p_public_key_y" "text", "p_key_source" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."carve_device"("p_device_id" "text", "p_device_name" "text", "p_device_model" "text", "p_public_key_n" "text", "p_public_key_e" "text", "p_public_key_x" "text", "p_public_key_y" "text", "p_key_source" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."check_lockout"("p_attempt_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."check_lockout"("p_attempt_type" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."check_lockout"("p_attempt_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."check_login_allowed"("p_phone" "text", "p_action" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."check_login_allowed"("p_phone" "text", "p_action" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."check_login_allowed"("p_phone" "text", "p_action" "text") TO "service_role";
GRANT ALL ON FUNCTION "badra_core"."check_login_allowed"("p_phone" "text", "p_action" "text") TO "anon";



REVOKE ALL ON FUNCTION "badra_core"."check_login_device"("p_device_id" "text", "p_device_name" "text", "p_device_model" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."check_login_device"("p_device_id" "text", "p_device_name" "text", "p_device_model" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."check_login_device"("p_device_id" "text", "p_device_name" "text", "p_device_model" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."check_payment_request_status"("p_request_id" "uuid", "p_merchant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."check_payment_request_status"("p_request_id" "uuid", "p_merchant_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."check_security_setup"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."check_security_setup"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."check_security_setup"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."cleanup_pending_on_auth_insert"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."cleanup_pending_on_auth_insert"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."clear_attempts"("p_attempt_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."clear_attempts"("p_attempt_type" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."confirm_payment_request"("p_request_id" "uuid", "p_merchant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."confirm_payment_request"("p_request_id" "uuid", "p_merchant_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."create_payment_request"("p_merchant_id" "uuid", "p_user_phone" "text", "p_amount" numeric, "p_order_ref" "text", "p_items" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."create_payment_request"("p_merchant_id" "uuid", "p_user_phone" "text", "p_amount" numeric, "p_order_ref" "text", "p_items" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "badra_core"."create_pending_user"("p_name" "text", "p_phone" "text", "p_password" "text", "p_ip" "text", "p_device_name" "text", "p_device_id" "text") TO "anon";
GRANT ALL ON FUNCTION "badra_core"."create_pending_user"("p_name" "text", "p_phone" "text", "p_password" "text", "p_ip" "text", "p_device_name" "text", "p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."create_pending_user"("p_name" "text", "p_phone" "text", "p_password" "text", "p_ip" "text", "p_device_name" "text", "p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."execute_approved_payment"("p_user_id" "uuid", "p_request_id" "uuid", "p_amount" numeric, "p_merchant_id" "uuid", "p_order_ref" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."execute_approved_payment"("p_user_id" "uuid", "p_request_id" "uuid", "p_amount" numeric, "p_merchant_id" "uuid", "p_order_ref" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."get_deposit_data"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."get_deposit_data"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."get_deposit_data"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."get_device_public_key"("p_user_id" "uuid", "p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."get_device_public_key"("p_user_id" "uuid", "p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."get_device_public_key"("p_user_id" "uuid", "p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."get_merchant_webhook_info"("p_merchant_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."get_merchant_webhook_info"("p_merchant_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."get_my_activation_code"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."get_my_activation_code"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."get_my_activation_code"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."get_my_pending_requests"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."get_my_pending_requests"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."get_my_pending_requests"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."get_my_profile"("p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."get_my_profile"("p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."get_my_profile"("p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."get_my_security_code"("p_phone" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."get_my_security_code"("p_phone" "text") TO "service_role";



GRANT ALL ON FUNCTION "badra_core"."get_my_transactions_fast"() TO "anon";
GRANT ALL ON FUNCTION "badra_core"."get_my_transactions_fast"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."get_my_transactions_fast"() TO "service_role";



GRANT ALL ON FUNCTION "badra_core"."get_my_transactions_paginated"("p_limit" integer, "p_offset" integer) TO "anon";
GRANT ALL ON FUNCTION "badra_core"."get_my_transactions_paginated"("p_limit" integer, "p_offset" integer) TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."get_my_transactions_paginated"("p_limit" integer, "p_offset" integer) TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."get_payment_request_by_order_ref"("p_merchant_id" "uuid", "p_order_ref" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."get_payment_request_by_order_ref"("p_merchant_id" "uuid", "p_order_ref" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."get_payment_request_by_order_ref"("p_merchant_id" "uuid", "p_order_ref" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."get_pending_users"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."get_pending_users"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."get_pending_users"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."handle_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."has_carved_device"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."has_carved_device"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."has_carved_device"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."is_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."is_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."is_admin_uid"("uid" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."is_admin_uid"("uid" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."is_admin_uid"("uid" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."record_failed_attempt"("p_attempt_type" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."record_failed_attempt"("p_attempt_type" "text") TO "service_role";



GRANT ALL ON FUNCTION "badra_core"."register_device_public_key"("p_device_id" "text", "p_public_key_n" "text", "p_public_key_e" "text") TO "anon";
GRANT ALL ON FUNCTION "badra_core"."register_device_public_key"("p_device_id" "text", "p_public_key_n" "text", "p_public_key_e" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."register_device_public_key"("p_device_id" "text", "p_public_key_n" "text", "p_public_key_e" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."register_fcm_token"("p_fcm_token" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."register_fcm_token"("p_fcm_token" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."register_fcm_token"("p_fcm_token" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."reject_payment_request"("p_request_id" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."reject_payment_request"("p_request_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."reject_payment_request"("p_request_id" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."reject_pending_user"("p_phone" "text", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."reject_pending_user"("p_phone" "text", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."reject_pending_user"("p_phone" "text", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."set_security_code"("p_new_code" "text", "p_current_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."set_security_code"("p_new_code" "text", "p_current_code" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."set_security_code"("p_new_code" "text", "p_current_code" "text") TO "service_role";



GRANT ALL ON FUNCTION "badra_core"."set_security_codes_for_existing"() TO "anon";
GRANT ALL ON FUNCTION "badra_core"."set_security_codes_for_existing"() TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."set_security_codes_for_existing"() TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."sync_home_data"("p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."sync_home_data"("p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."sync_home_data"("p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."verify_authorized_device"("p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."verify_authorized_device"("p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."verify_authorized_device"("p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."verify_device"("p_device_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."verify_device"("p_device_id" "text") TO "authenticated";
GRANT ALL ON FUNCTION "badra_core"."verify_device"("p_device_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."verify_security_code"("p_user_id" "uuid", "p_security_code" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."verify_security_code"("p_user_id" "uuid", "p_security_code" "text") TO "service_role";



REVOKE ALL ON FUNCTION "badra_core"."verify_store_identity"("p_phone" "text", "p_name" "text", "p_created_at" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "badra_core"."verify_store_identity"("p_phone" "text", "p_name" "text", "p_created_at" "text") TO "service_role";































































































































































GRANT ALL ON TABLE "badra_core"."activation_codes" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."activation_codes" TO "service_role";



GRANT ALL ON TABLE "badra_core"."admins" TO "anon";
GRANT ALL ON TABLE "badra_core"."admins" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."admins" TO "service_role";



GRANT ALL ON TABLE "badra_core"."audit_log" TO "anon";
GRANT ALL ON TABLE "badra_core"."audit_log" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."audit_log" TO "service_role";



GRANT ALL ON TABLE "badra_core"."balance_summary" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."balance_summary" TO "service_role";



GRANT ALL ON TABLE "badra_core"."bank_accounts" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."bank_accounts" TO "service_role";



GRANT ALL ON TABLE "badra_core"."challenge_attempts" TO "anon";
GRANT ALL ON TABLE "badra_core"."challenge_attempts" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."challenge_attempts" TO "service_role";



GRANT ALL ON TABLE "badra_core"."deposit_config" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."deposit_config" TO "service_role";



GRANT ALL ON TABLE "badra_core"."deposit_requests" TO "anon";
GRANT ALL ON TABLE "badra_core"."deposit_requests" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."deposit_requests" TO "service_role";



GRANT ALL ON TABLE "badra_core"."identity_verify_attempts" TO "anon";
GRANT ALL ON TABLE "badra_core"."identity_verify_attempts" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."identity_verify_attempts" TO "service_role";



GRANT ALL ON TABLE "badra_core"."merchants" TO "anon";
GRANT ALL ON TABLE "badra_core"."merchants" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."merchants" TO "service_role";



GRANT ALL ON TABLE "badra_core"."payment_requests" TO "anon";
GRANT ALL ON TABLE "badra_core"."payment_requests" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."payment_requests" TO "service_role";



GRANT ALL ON TABLE "badra_core"."pending_users" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."pending_users" TO "service_role";



GRANT SELECT,INSERT,REFERENCES,DELETE,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "badra_core"."profiles" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."profiles" TO "service_role";



GRANT UPDATE("phone") ON TABLE "badra_core"."profiles" TO "authenticated";



GRANT UPDATE("name") ON TABLE "badra_core"."profiles" TO "authenticated";



GRANT ALL ON TABLE "badra_core"."transactions_v2" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."transactions_v2" TO "service_role";



GRANT SELECT,REFERENCES,TRIGGER,TRUNCATE,MAINTAIN ON TABLE "badra_core"."user_devices" TO "authenticated";
GRANT ALL ON TABLE "badra_core"."user_devices" TO "service_role";















ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "badra_core" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "badra_core" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "badra_core" GRANT ALL ON SEQUENCES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "badra_core" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "badra_core" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "badra_core" GRANT ALL ON FUNCTIONS TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "badra_core" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "badra_core" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "badra_core" GRANT ALL ON TABLES TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































