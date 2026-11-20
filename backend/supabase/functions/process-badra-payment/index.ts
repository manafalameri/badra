import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"
import bcryptjs from "https://esm.sh/bcryptjs@2.4.3"

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "x-api-key, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
}

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  })
}

// ── Cached Firebase OAuth token (valid ~1h, refreshed 5min before expiry) ──
let cachedAccessToken: string | null = null
let cachedAccessTokenExpiry = 0

async function getAccessToken(
  projectId: string,
  clientEmail: string,
  privateKey: string
): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedAccessToken && cachedAccessTokenExpiry - now > 300) {
    return cachedAccessToken
  }

  const expiry = now + 3600

  const header = { alg: "RS256", typ: "JWT" }
  const payload = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: expiry,
  }

  const encodedHeader = btoa(JSON.stringify(header)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_")
  const encodedPayload = btoa(JSON.stringify(payload)).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_")

  const dataToSign = `${encodedHeader}.${encodedPayload}`

  const keyData = privateKey.replace(/-----BEGIN PRIVATE KEY-----/g, "").replace(/-----END PRIVATE KEY-----/g, "").replace(/\s/g, "")

  const binaryKey = Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0))

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  )

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(dataToSign)
  )

  const encodedSignature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")

  const jwt = `${dataToSign}.${encodedSignature}`

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${jwt}`,
  })

  const tokenResult = await tokenResponse.json()

  if (!tokenResult.access_token) {
    throw new Error(`Firebase token error: ${tokenResult.error || "unknown"}`)
  }

  cachedAccessToken = tokenResult.access_token
  cachedAccessTokenExpiry = expiry

  return tokenResult.access_token
}

async function sendFcmNotification(
  supabase: any,
  merchantName: string,
  amount: number,
  requestId: string
): Promise<{ success: boolean; error?: string }> {
  const tag = `[FCM:${requestId.slice(0, 8)}]`

  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")

  const missing = [
    !projectId && "FIREBASE_PROJECT_ID",
    !clientEmail && "FIREBASE_CLIENT_EMAIL",
    !privateKey && "FIREBASE_PRIVATE_KEY",
  ].filter(Boolean)

  if (missing.length > 0) {
    console.error(`${tag} S0 secrets: MISSING ${missing.join(",")}`)
    return { success: false, error: `Firebase secrets missing: ${missing.join(",")}` }
  }
  console.log(`${tag} S0 secrets: ok`)

  const { data: request, error: requestError } = await supabase
    .schema("badra_core")
    .from("payment_requests")
    .select("user_id")
    .eq("id", requestId)
    .single()

  if (requestError || !request?.user_id) {
    console.error(`${tag} S1 request lookup: FAIL ${(requestError?.message || "no user_id").slice(0, 120)}`)
    return { success: false, error: "Request not found" }
  }
  console.log(`${tag} S1 request lookup: ok`)

  const { data: device, error: deviceError } = await supabase
    .schema("badra_core")
    .from("user_devices")
    .select("fcm_token")
    .eq("user_id", request.user_id)
    .not("fcm_token", "eq", "")
    .limit(1)
    .single()

  if (deviceError || !device?.fcm_token) {
    console.error(`${tag} S2 token: NOT FOUND for user ${request.user_id}`)
    return { success: false, error: "No FCM token" }
  }
  console.log(`${tag} S2 token: ok len=${device.fcm_token.length} prefix=${device.fcm_token.slice(0, 8)}…`)

  try {
    const accessToken = await getAccessToken(projectId!, clientEmail!, privateKey!)
    console.log(`${tag} S3 oauth: ok${cachedAccessToken === accessToken ? " (cached)" : " (fresh)"}`)

    // FCM HTTP v1 schema — legacy fields (content_available/time_to_live) are
    // rejected with 400 INVALID_ARGUMENT; TTL lives at android.ttl ("3600s").
    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: device.fcm_token,
            notification: {
              title: "طلب دفع جديد",
              body: `طلب دفع من ${merchantName} — ${amount} ر.س`,
            },
            data: {
              type: "payment_request",
              request_id: requestId,
            },
            android: {
              priority: "HIGH",
              ttl: "3600s",
              notification: {
                channel_id: "payment_requests",
                sound: "default",
              },
            },
            apns: {
              headers: {
                "apns-priority": "10",
                "apns-push-type": "alert",
              },
              payload: {
                aps: {
                  "content-available": 1,
                  sound: "default",
                },
              },
            },
          },
        }),
      }
    )

    if (!fcmResponse.ok) {
      const errBody = await fcmResponse.text()
      console.error(`${tag} S4 fcm api: HTTP ${fcmResponse.status} ${errBody.slice(0, 300)}`)
      return { success: false, error: `HTTP ${fcmResponse.status}` }
    }

    const fcmResult = await fcmResponse.json()
    console.log(`${tag} S4 fcm api: SENT ${fcmResult.name || ""}`)
    return { success: true }
  } catch (e) {
    console.error(`${tag} S3/S4 exception: ${String(e).slice(0, 200)}`)
    return { success: false, error: String(e) }
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS })
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

    const { data: merchants } = await supabase
      .schema("badra_core")
      .from("merchants")
      .select("id, name, api_key_hash, is_active, webhook_url, webhook_secret")
      .eq("api_key_prefix", prefix)
      .limit(1)

    if (!merchants?.length) {
      return jsonResponse(401, { success: false, error: "المتجر غير موجود" })
    }

    const merchant = merchants[0]
    if (!merchant.is_active) {
      return jsonResponse(403, { success: false, error: "المتجر غير نشط" })
    }

    if (!bcryptjs.compareSync(apiKey, merchant.api_key_hash)) {
      return jsonResponse(401, { success: false, error: "المفتاح غير صحيح" })
    }

    const body = await req.json()

    // ── مسار إلغاء طلب الدفع من المتجر (Action: cancel) ──
    if (body.action === "cancel") {
      const orderRef = String(body.order_ref || "").trim()

      if (!/^[A-Za-z0-9_-]{4,40}$/.test(orderRef)) {
        return jsonResponse(400, { success: false, error: "رقم الطلب غير صالح" })
      }

      // البحث عن الطلب المربوط بهذا المتجر في المحفظة
      const { data: request, error: fetchErr } = await supabase
        .schema("badra_core")
        .from("payment_requests")
        .select("id, status, user_id, amount, created_at")
        .eq("merchant_id", merchant.id)
        .eq("order_ref", orderRef)
        .maybeSingle()

      if (fetchErr) {
        console.error("[process-badra-payment] Cancel fetch error:", fetchErr)
        return jsonResponse(500, { success: false, error: "خطأ داخلي أثناء استعلام الطلب" })
      }

      // إذا لم يكن الطلب موجوداً في المحفظة، يُعتبر ملغياً بنجاح (idempotent)
      if (!request) {
        return jsonResponse(200, {
          success: true,
          cancelled: true,
          message: "الطلب غير موجود في المحفظة"
        })
      }

      // حماية ضد سباق العمليات: منع إلغاء أي طلب تم سداده بالفعل
      if (request.status === "approved" || request.status === "completed") {
        return jsonResponse(409, {
          success: false,
          error: "ALREADY_PAID",
          message: "تم سداد هذا الطلب في المحفظة بالفعل ولا يمكن إلغاؤه"
        })
      }

      // إذا كان الطلب ملغياً أو منتهياً بالفعل
      if (request.status === "cancelled" || request.status === "rejected" || request.status === "expired") {
        return jsonResponse(200, {
          success: true,
          cancelled: true,
          message: `الطلب ملغي مسبقاً (${request.status})`
        })
      }

      // تحديث ذري مشروط: لا يلغي إلا إذا كان لا يزال pending
      // ملاحظة معمارية: قيد الجدول يسمح حصراً بـ ('pending', 'approved', 'rejected', 'expired')
      const nowIso = new Date().toISOString()
      const { data: updated, error: updateErr } = await supabase
        .schema("badra_core")
        .from("payment_requests")
        .update({
          status: "rejected",
          rejected_at: nowIso,
        })
        .eq("id", request.id)
        .eq("merchant_id", merchant.id)
        .eq("status", "pending")
        .select("id")

      if (updateErr) {
        console.error("[process-badra-payment] Cancel update error:", updateErr)
        return jsonResponse(500, { success: false, error: "فشل تحديث حالة الطلب في المحفظة" })
      }

      if (!updated || updated.length === 0) {
        // حالة سباق: تغيرت حالة الطلب أثناء تنفيذ الإلغاء
        return jsonResponse(409, {
          success: false,
          error: "STATE_CHANGED",
          message: "تغيرت حالة الطلب أثناء محاولة الإلغاء، يرجى إعادة المحاولة"
        })
      }

      return jsonResponse(200, {
        success: true,
        cancelled: true,
        order_ref: orderRef,
      })
    }
    const { order_ref, amount, items, name, metadata, user_phone, created_at, device_id, device_name, device_model } = body

    const phone = String(user_phone || "").trim().replace(/^\+/, "")
    const orderRef = String(order_ref || "").trim()
    const amountNum = Number(amount)
    const customerName = String(name || "").trim()
    const createdAt = String(created_at || "").trim()
    const deviceId = String(device_id || "").trim()

    if (!/^967\d{9}$/.test(phone)) {
      return jsonResponse(400, { success: false, error: "رقم الهاتف غير صالح" })
    }
    if (!Number.isFinite(amountNum) || amountNum <= 0 || amountNum > 50000) {
      return jsonResponse(400, { success: false, error: "المبلغ غير صالح" })
    }
    if (!/^[A-Za-z0-9_-]{4,40}$/.test(orderRef)) {
      return jsonResponse(400, { success: false, error: "رقم الطلب غير صالح" })
    }
    if (!customerName) {
      return jsonResponse(400, { success: false, error: "اسم العميل مطلوب" })
    }
    if (!/^\d{2}\/\d{2}$/.test(createdAt)) {
      return jsonResponse(400, { success: false, error: "تاريخ إنشاء الطلب غير صالح" })
    }
    if (!deviceId || deviceId.length < 10) {
      return jsonResponse(400, { success: false, error: "معرف الجهاز غير صالح" })
    }
    if (!Array.isArray(items) || items.length === 0) {
      return jsonResponse(400, { success: false, error: "عناصر الطلب مطلوبة" })
    }
    for (const item of items) {
      const code = Number(item?.code)
      const qty = Number(item?.quantity)
      if (!Number.isInteger(code) || code <= 0 || !Number.isInteger(qty) || qty <= 0) {
        return jsonResponse(400, { success: false, error: "عنصر طلب غير صالح" })
      }
    }

    const metadataObj = metadata && typeof metadata === "object" ? metadata : {}

    const { data, error } = await supabase
      .schema("badra_core")
      .rpc("enqueue_payment", {
        p_merchant_id: merchant.id,
        p_user_phone: phone,
        p_amount: amountNum,
        p_order_ref: orderRef,
        p_items: items,
        p_name: customerName,
        p_created_at: createdAt,
        p_device_id: deviceId,
        p_device_name: String(device_name || "").trim(),
        p_device_model: String(device_model || "").trim(),
        p_ip: req.headers.get("x-forwarded-for") || "",
        p_user_agent: req.headers.get("user-agent") || "",
        p_metadata: metadataObj,
      })

    if (error) {
      console.error("[process-badra-payment] RPC error:", error)
      return jsonResponse(500, { success: false, error: "خطأ داخلي" })
    }

    const result = data as any
    if (!result?.success) {
      const msg = result?.error?.toString() || "فشل إنشاء الطلب"
      if (msg.includes("غير مصرح") || msg.includes("تعذر")) {
        return jsonResponse(400, { success: false, error: msg })
      }
      return jsonResponse(400, result)
    }

    if (result?.request_id) {
      try {
        const fcmResult = await sendFcmNotification(supabase, merchant.name, amountNum, result.request_id)
        if (!fcmResult.success) {
          console.warn("[process-badra-payment] FCM send failed:", fcmResult.error)
        }
      } catch (fcmErr) {
        console.error("[process-badra-payment] FCM exception (non-blocking):", fcmErr)
      }
    }

    return jsonResponse(200, result)
  } catch (e) {
    console.error("[process-badra-payment] Fatal error:", e)
    return jsonResponse(500, { success: false, error: "خطأ داخلي" })
  }
})