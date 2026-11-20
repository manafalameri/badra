import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import bcryptjs from "https://esm.sh/bcryptjs@2.4.3"

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

    const body = await req.json()
    const { request_id } = body

    if (!request_id) {
      return jsonResponse(400, { success: false, error: "request_id مطلوب" })
    }

    const { data, error } = await supabase
      .schema("badra_core")
      .rpc("check_payment_request_status", {
        p_request_id: request_id,
        p_merchant_id: merchant.id,
      })

    if (error) {
      console.error("[check-payment-status] RPC error:", error)
      return jsonResponse(500, { success: false, error: error.message })
    }

    return jsonResponse(200, data as Record<string, unknown>)
  } catch (e) {
    console.error("[check-payment-status] Fatal error:", e)
    return jsonResponse(500, { success: false, error: "خطأ داخلي" })
  }
})
