import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

async function sendWebhook(
  supabase: any,
  merchantId: string,
  event: string,
  payload: Record<string, unknown>
) {
  try {
    const { data: webhookData } = await supabase
      .schema("badra_core")
      .rpc("get_merchant_webhook_info", { p_merchant_id: merchantId })

    const info = webhookData as any
    if (!info?.success || !info.webhook_url) return

    const body = JSON.stringify({ event, ...payload })
    const timestamp = Date.now().toString()
    const nonce = crypto.randomUUID()

    if (info.webhook_secret) {
      const keyData = new TextEncoder().encode(info.webhook_secret)
      const msgData = new TextEncoder().encode(body)
      const cryptoKey = await crypto.subtle.importKey(
        "raw", keyData,
        { name: "HMAC", hash: "SHA-256" },
        false, ["sign"]
      )
      const sig = await crypto.subtle.sign("HMAC", cryptoKey, msgData)
      const sigHex = Array.from(new Uint8Array(sig))
        .map((b) => b.toString(16).padStart(2, "0"))
        .join("")

      await fetch(info.webhook_url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Badra-Signature-256": sigHex,
          "X-Badra-Event": event,
          "X-Badra-Timestamp": timestamp,
          "X-Badra-Nonce": nonce,
        },
        body,
      })
    } else {
      await fetch(info.webhook_url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Badra-Event": event,
          "X-Badra-Timestamp": timestamp,
          "X-Badra-Nonce": nonce,
        },
        body,
      })
    }
  } catch (err) {
    console.error("[approve-payment-signature] Webhook error (non-blocking):", err)
  }
}

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

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS })
  }

  try {
    if (req.method !== "POST") {
      return jsonResponse(405, { success: false, error: "Method not allowed" })
    }

    const body = await req.json()
    const { request_id, device_id, security_code, signature, timestamp, coupon_code } = body

    if (!request_id || !device_id || !security_code || !signature || !timestamp) {
      return jsonResponse(400, {
        success: false,
        error: "جميع الحقول مطلوبة: request_id, device_id, security_code, signature, timestamp",
      })
    }

    // Strict validation for coupon_code (Anti-DoS & Regex Check)
    let sanitizedCoupon: string | null = null
    if (coupon_code !== undefined && coupon_code !== null) {
      if (typeof coupon_code !== "string" || !/^\d{6}$/.test(coupon_code.trim())) {
        return jsonResponse(400, {
          success: false,
          error: "كود الخصم يجب أن يتكون من 6 أرقام رقمية فقط",
        })
      }
      sanitizedCoupon = coupon_code.trim()
    }

    // 1. Verify timestamp (60 seconds window)
    const now = Date.now()
    const requestTime = new Date(timestamp).getTime()
    if (isNaN(requestTime) || Math.abs(now - requestTime) > 60_000) {
      return jsonResponse(401, {
        success: false,
        error: "انتهت صلاحية الطلب أو التوقيع غير صالح (صلاحية 60 ثانية)",
      })
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    // 2. Fetch the payment request
    const { data: request, error: reqError } = await supabase
      .schema("badra_core")
      .from("payment_requests")
      .select("id, user_id, amount, status, expires_at, merchant_id, order_ref, items, metadata")
      .eq("id", request_id)
      .single()

    if (reqError || !request) {
      return jsonResponse(404, { success: false, error: "طلب الدفع غير موجود" })
    }

    if (request.status !== "pending") {
      return jsonResponse(400, { success: false, error: "هذا الطلب تم معالجته مسبقاً" })
    }

    if (new Date(request.expires_at).getTime() < now) {
      await supabase
        .schema("badra_core")
        .from("payment_requests")
        .update({ status: "expired" })
        .eq("id", request_id)
      return jsonResponse(400, { success: false, error: "انتهت صلاحية الطلب" })
    }

    // 3. Fetch device public key
    const { data: keyData, error: keyError } = await supabase
      .schema("badra_core")
      .rpc("get_device_public_key", {
        p_user_id: request.user_id,
        p_device_id: device_id,
      })

    if (keyError || !keyData) {
      return jsonResponse(401, { success: false, error: "المفتاح العام غير موجود لهذا الجهاز" })
    }

    const keyResult = keyData as any
    if (!keyResult.success) {
      return jsonResponse(401, { success: false, error: keyResult.error || "المفتاح العام غير موجود" })
    }

    // 4. Verify ECDSA signature using the device's public key
    const jwk: Record<string, string> = {
      kty: "EC", crv: "P-256", x: keyResult.x, y: keyResult.y, ext: "true",
    }

    let cryptoKey: CryptoKey
    try {
      cryptoKey = await crypto.subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"])
    } catch (err) {
      console.error("[approve-payment-signature] Key import error:", err)
      return jsonResponse(401, { success: false, error: "فشل استيراد المفتاح العام" })
    }

    // 5. Verify the signature (bound to requestId + timestamp + deviceId)
    const payload = `${request_id}|${timestamp}|${device_id}`
    const data = new TextEncoder().encode(payload)

    let sigBytes: Uint8Array
    try {
      const sigPadded = signature.replace(/-/g, "+").replace(/_/g, "/")
      const padded = sigPadded + "=".repeat((4 - (sigPadded.length % 4)) % 4)
      sigBytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0))
    } catch {
      return jsonResponse(401, { success: false, error: "توقيع غير صالح" })
    }

    let valid = false
    try {
      valid = await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, cryptoKey, sigBytes, data)
    } catch (err) {
      console.error("[approve-payment-signature] Signature verify error:", err)
    }

    if (!valid) {
      return jsonResponse(401, { success: false, error: "التوقيع غير صالح" })
    }

    // 6. Verify security code (PIN) via PostgreSQL crypt()
    //    Lockout (max 5 attempts / 30 min) is enforced INSIDE verify_security_code —
    //    unbypassable and shared with every caller.
    const { data: verifyResult, error: verifyError } = await supabase
      .schema("badra_core")
      .rpc("verify_security_code", {
        p_user_id: request.user_id,
        p_security_code: security_code,
      })

    if (verifyError || !verifyResult) {
      return jsonResponse(500, { success: false, error: "خطأ في التحقق من الرقم السري" })
    }

    const verification = verifyResult as any
    if (!verification?.valid || verification?.locked) {
      return jsonResponse(401, {
        success: false,
        error: verification?.error || "الرقم السري غير صحيح",
      })
    }

    // 7. Execute payment with optional coupon — atomic RPC handles:
    //    coupon validation + discount calculation + balance deduction + tx creation
    const { data: approveResult, error: approveError } = await supabase
      .schema("badra_core")
      .rpc("redeem_coupon_and_pay", {
        p_user_id:     request.user_id,
        p_request_id:  request.id,
        p_amount:      request.amount,
        p_merchant_id: request.merchant_id,
        p_order_ref:   request.order_ref,
        p_coupon_code: sanitizedCoupon,
        p_device_id:   device_id,
      })

    if (approveError) {
      console.error("[approve-payment-signature] Approve error:", approveError)
      return jsonResponse(500, { success: false, error: approveError.message })
    }

    const result = approveResult as any
    if (!result?.success) {
      return jsonResponse(400, result)
    }

    // Fire webhook (non-blocking) — merchant will receive approval notification with full headers and payload
    const metadata = (request.metadata && typeof request.metadata === "object" ? request.metadata : {}) as Record<string, unknown>
    sendWebhook(supabase, request.merchant_id, "payment.approved", {
      request_id,
      order_ref:       request.order_ref || "",
      amount:          request.amount || 0,
      original_amount: request.amount || 0,
      discount:        result.discount || 0,
      final_amount:    result.final_amount || request.amount || 0,
      coupon_applied:  result.coupon_applied || false,
      tx_id:           result.transaction_id || "",
      items:           request.items || [],
      metadata:        metadata,
      user_phone:      metadata.user_phone || "",
      customer_name:   metadata.customer_name || "",
      delivery:        metadata.delivery ?? false,
      delivery_address: metadata.delivery_address || null,
      latitude:        metadata.latitude || 0,
      longitude:       metadata.longitude || 0,
      status:          "approved",
      approved_at:     new Date().toISOString(),
    })

    return jsonResponse(200, result)
  } catch (e) {
    console.error("[approve-payment-signature] Fatal error:", e)
    return jsonResponse(500, { success: false, error: "خطأ داخلي" })
  }
})