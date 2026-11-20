-- =============================================================================
-- SECURITY FIX 7: Harden verify_store_identity against enumeration oracle (H8/H3)
-- =============================================================================
-- Vulnerability: verify_store_identity returned staged errors:
--   1. 'المستخدم غير موجود'   → phone-existence oracle
--   2. 'الاسم غير صحيح'       → name-correctness oracle
--   3. 'تاريخ الإنشاء غير صحيح' → DD/MM oracle (only 366 possible values!)
-- With a leaked merchant key, an attacker brute-forces identity in ~366 tries
-- after confirming phone+name, with zero rate limiting.
--
-- Fix:
--   1. ONE generic error for all failures
--   2. Phone-keyed attempt tracking with lockout (10 attempts / hour)
-- =============================================================================

-- Step 1: Attempt-tracking table (keyed by phone since user may not exist)
CREATE TABLE IF NOT EXISTS badra_core.identity_verify_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  phone TEXT NOT NULL,
  attempted_at TIMESTAMPTZ DEFAULT now() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_identity_verify_attempts_phone
  ON badra_core.identity_verify_attempts(phone, attempted_at);

ALTER TABLE badra_core.identity_verify_attempts ENABLE ROW LEVEL SECURITY;
-- No RLS policies: access only via SECURITY DEFINER functions

-- Step 2: Hardened function
CREATE OR REPLACE FUNCTION badra_core.verify_store_identity(
  p_phone TEXT,
  p_name TEXT,
  p_created_at TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'badra_core', 'public', 'extensions'
AS $function$
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
$function$;

REVOKE EXECUTE ON FUNCTION badra_core.verify_store_identity(TEXT, TEXT, TEXT) FROM anon, public, authenticated;
GRANT EXECUTE ON FUNCTION badra_core.verify_store_identity(TEXT, TEXT, TEXT) TO service_role;

COMMENT ON FUNCTION badra_core.verify_store_identity IS
  'SECURITY: Generic errors + phone-keyed lockout (10/hour) prevent enumeration.';
