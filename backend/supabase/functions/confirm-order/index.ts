import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import bcryptjs from "https://esm.sh/bcryptjs@2.4.3"

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
        },
        body,
      })
    } else {
      await fetch(info.webhook_url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Badra-Event": event,
        },
        body,
      })
    }
  } catch (err) {
    console.error("[confirm-order] Webhook error (non-blocking):", err)
  }
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-api-key, content-type",
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

    const apiKey = req.headers.get("x-api-key")
    if (!apiKey || apiKey.length < 20) {
      return jsonResponse(401, { success: false, error: "المفتاح غير صالح" })
    }

    const prefix = apiKey.substring(0, 16)

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    )

    // 1. Verify merchant
    const { data: merchants, error: merchantError } = await supabase
      .schema("badra_core")
      .from("merchants")
      .select("id, api_key_hash, is_active")
      .eq("api_key_prefix", prefix)
      .limit(1)

    if (merchantError || !merchants || merchants.length === 0) {
      return jsonResponse(401, { success: false, error: "المتجر غير موجود" })
    }

    const merchant = merchants[0]

    if (!merchant.is_active) {
      return jsonResponse(403, { success: false, error: "المتجر غير نشط" })
    }

    const keyValid = bcryptjs.compareSync(apiKey, merchant.api_key_hash)
    if (!keyValid) {
      return jsonResponse(401, { success: false, error: "المفتاح غير صحيح" })
    }

    // 2. Parse body
    const body = await req.json()
    const { request_id } = body

    if (!request_id) {
      return jsonResponse(400, { success: false, error: "request_id مطلوب" })
    }

    // 3. Verify payment request with row lock
    const { data: request, error: reqError } = await supabase
      .schema("badra_core")
      .rpc("confirm_payment_request", {
        p_request_id: request_id,
        p_merchant_id: merchant.id,
      })

    if (reqError) {
      console.error("[confirm-order] RPC error:", reqError)
      return jsonResponse(500, { success: false, error: reqError.message })
    }

    const result = request as any

    if (!result?.success) {
      return jsonResponse(400, result)
    }

    // Fire webhook (non-blocking) — merchant will receive payment confirmation
    sendWebhook(supabase, merchant.id, "payment.confirmed", {
      request_id,
      order_ref: result.order_ref || "",
      amount: result.amount || 0,
      tx_id: result.tx_id || "",
      status: "confirmed",
      confirmed_at: new Date().toISOString(),
    })

    return jsonResponse(200, result)
  } catch (e) {
    console.error("[confirm-order] Fatal error:", e)
    return jsonResponse(500, { success: false, error: "خطأ داخلي" })
  }
})
