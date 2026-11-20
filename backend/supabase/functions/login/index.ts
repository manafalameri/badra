import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

// =============================================================================
// SECURE LOGIN — the single official login path.
// =============================================================================
// The Flutter app calls THIS function with phone + password only. All lockout
// logic lives server-side (SECURITY DEFINER RPCs, service_role only) so the
// 5/30min lockout can never be bypassed by a modified client.
//
// verify_jwt: false (intentionally — this is the pre-auth entry point).
// Protection of this endpoint itself:
//   - check_lockout_v2 (user/device/ip/global dimensions, fail-closed)
//   - GoTrue bcrypt password verification (never done by us)
//   - uniform_timing on every rejection path (no timing oracle)
//   - cf-connecting-ip is set by Cloudflare and cannot be spoofed by clients
//
// On device rejection the freshly minted session is revoked server-side
// (userClient.auth.signOut()) and the tokens NEVER leave this function.
// =============================================================================

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  })
}

const GENERIC_FAILURE = "بيانات الدخول غير صحيحة"

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS })
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse(405, { success: false, error: "Method not allowed" })
    }

    const body = await req.json()
    const { phone, password, device_id, device_name, device_model } = body

    if (typeof phone !== "string" || phone.trim() === "") {
      return jsonResponse(400, { success: false, error: "رقم الهاتف مطلوب" })
    }
    if (typeof password !== "string" || password === "") {
      return jsonResponse(400, { success: false, error: "كلمة المرور مطلوبة" })
    }

    const ip = req.headers.get("cf-connecting-ip")
      ?? req.headers.get("x-real-ip")
      ?? "unknown"
    const ua = req.headers.get("user-agent") ?? ""
    const deviceId = typeof device_id === "string" ? device_id : ""

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    // ── 1. Lockout check (fail-closed: if the check fails, deny) ──
    const { data: lockout, error: lockoutError } = await supabase
      .schema("badra_core")
      .rpc("check_lockout_v2", {
        p_phone: phone.trim(),
        p_device_hash: deviceId,
        p_ip: ip,
      })

    if (lockoutError || !lockout) {
      console.error("[login] lockout check failed:", lockoutError?.message)
      await supabase.schema("badra_core").rpc("uniform_timing")
      return jsonResponse(503, { success: false, error: "تعذر التحقق من الحساب. حاول لاحقاً" })
    }

    if (lockout.locked === true) {
      await supabase.schema("badra_core").rpc("uniform_timing")
      return jsonResponse(429, {
        success: false,
        error: lockout.locked_forever === true
          ? "الحساب مقفل نهائياً. تواصل مع الدعم الفني."
          : "الحساب مقفل مؤقتاً بسبب محاولات فاشلة كثيرة. حاول مرة أخرى لاحقاً.",
        locked: true,
        locked_forever: lockout.locked_forever === true,
        retry_after: lockout.retry_after ?? null,
      })
    }

    // ── 2. Verify password — GoTrue does the bcrypt, we never see hashes ──
    // supabase-js can THROW (AuthRetryableFetchError) when GoTrue rate-limits
    // (429) or hiccups — treat any throw exactly like a failed attempt so the
    // response surface stays uniform (record + timing + generic 401).
    let authData: Awaited<ReturnType<typeof supabase.auth.signInWithPassword>>["data"] | null = null
    let authError: { message?: string } | null = null
    try {
      const res = await supabase.auth.signInWithPassword({
        phone: phone.trim(),
        password,
      })
      authData = res.data
      authError = res.error
    } catch (thrown) {
      authError = { message: thrown instanceof Error ? thrown.message : "auth throw" }
    }

    if (authError || !authData?.session || !authData.user) {
      await supabase.schema("badra_core").rpc("record_failed_login_v2", {
        p_phone: phone.trim(),
        p_device_hash: deviceId,
        p_ip: ip,
        p_user_agent: ua,
      })
      await supabase.schema("badra_core").rpc("uniform_timing")
      return jsonResponse(401, { success: false, error: GENERIC_FAILURE })
    }

    const user = authData.user
    const session = authData.session

    // ── 3. Device binding check, acting as the user ──
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      {
        global: {
          headers: { Authorization: `Bearer ${session.access_token}` },
        },
      }
    )

    const { data: deviceResp, error: deviceError } = await userClient
      .schema("badra_core")
      .rpc("check_login_device", {
        p_device_id: deviceId,
        p_device_name: typeof device_name === "string" ? device_name : "",
        p_device_model: typeof device_model === "string" ? device_model : "",
      })

    const deviceOk = !deviceError && deviceResp?.success === true

    if (!deviceOk) {
      // New/unknown device: revoke this exact session, tokens never leave.
      await userClient.auth.signOut().catch(() => {})
      await supabase.schema("badra_core").rpc("record_failed_login_v2", {
        p_phone: phone.trim(),
        p_device_hash: deviceId,
        p_ip: ip,
        p_user_agent: ua,
      })
      await supabase.schema("badra_core").rpc("uniform_timing")
      return jsonResponse(403, {
        success: false,
        error: deviceResp?.error ?? "هذا الحساب مرتبط بجهاز آخر",
      })
    }

    // ── 4. Success: wipe counters + audit trail ──
    const { error: clearErr } = await supabase.schema("badra_core").rpc("clear_attempts_v2", {
      p_phone: phone.trim(),
      p_device_hash: deviceId,
    })
    if (clearErr) console.error("[login] clear_attempts_v2 error:", clearErr.message)
    const { error: recErr } = await supabase.schema("badra_core").rpc("record_successful_login_v2", {
      p_phone: phone.trim(),
      p_device_hash: deviceId,
      p_ip: ip,
      p_user_agent: ua,
    })
    if (recErr) console.error("[login] record_successful_login_v2 error:", recErr.message)

    return jsonResponse(200, {
      success: true,
      access_token: session.access_token,
      refresh_token: session.refresh_token,
      user: {
        id: user.id,
        phone: user.phone,
        email: user.email,
      },
    })
  } catch (e) {
    console.error("[login] fatal error:", e)
    return jsonResponse(500, { success: false, error: "حدث خطأ أثناء التواصل مع الخادم. حاول مرة أخرى لاحقاً." })
  }
})
