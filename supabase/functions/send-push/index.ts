import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

// Comma-separated env var, e.g. "https://admin.bsheel.app,https://staging-admin.example.com,http://localhost:8080".
// Falls back to a safe production-only default if the env var is missing
// so a misconfigured deploy never silently allows '*'.
const ALLOWED_ORIGINS_ENV = Deno.env.get("ADMIN_ALLOWED_ORIGINS") ?? "";
const allowedOrigins: string[] = ALLOWED_ORIGINS_ENV
  ? ALLOWED_ORIGINS_ENV.split(",").map((o) => o.trim()).filter((o) => o.length > 0)
  : ["https://admin.bsheel.app"];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") ?? "";
  const allowedOrigin = allowedOrigins.includes(origin) ? origin : "";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}

/** URL-safe base64 encode (no padding) */
function base64url(input: string): string {
  return btoa(input)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

// H2 (2026-05-17): cache the imported RSA key and the issued OAuth
// access token at module scope so the private key isn't re-parsed on
// every push (and won't get logged through a transient stack trace).
// Tokens last 3600s; we refresh ~5min early.
let cachedKey: CryptoKey | null = null;
let cachedClientEmail: string | null = null;
let cachedToken: string | null = null;
let cachedTokenExpiresAt = 0;

// H3 (2026-05-17): per-admin rate limit so a compromised admin (or a
// runaway script) can't burn FCM quota in seconds. 30 sends/min/admin.
const SEND_PUSH_LIMIT_PER_MIN = 30;
const sendPushBuckets = new Map<string, { count: number; resetAt: number }>();
function pushRateLimitOk(adminId: string): boolean {
  const now = Date.now();
  const slot = sendPushBuckets.get(adminId);
  if (!slot || slot.resetAt < now) {
    sendPushBuckets.set(adminId, { count: 1, resetAt: now + 60_000 });
    return true;
  }
  if (slot.count >= SEND_PUSH_LIMIT_PER_MIN) return false;
  slot.count++;
  return true;
}

async function getCachedKey(): Promise<{ key: CryptoKey; clientEmail: string }> {
  if (cachedKey && cachedClientEmail) {
    return { key: cachedKey, clientEmail: cachedClientEmail };
  }
  const serviceAccount = JSON.parse(
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}"
  );
  if (!serviceAccount.private_key || !serviceAccount.client_email) {
    throw new Error("firebase_service_account_invalid");
  }
  const keyData = (serviceAccount.private_key as string)
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\n/g, "");
  cachedKey = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
  cachedClientEmail = serviceAccount.client_email as string;
  return { key: cachedKey, clientEmail: cachedClientEmail };
}

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now < cachedTokenExpiresAt - 300) {
    return cachedToken;
  }

  const { key, clientEmail } = await getCachedKey();
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(
    JSON.stringify({
      iss: clientEmail,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${payload}`)
  );
  const sig = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  const jwt = `${header}.${payload}.${sig}`;
  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  if (!tokenResponse.ok) {
    // Don't echo the response body — Google sometimes embeds parts of
    // the assertion or the client_email in error messages.
    throw new Error(`oauth_token_failed_${tokenResponse.status}`);
  }
  const tokenData = await tokenResponse.json();
  if (!tokenData.access_token) {
    throw new Error("oauth_token_missing");
  }
  cachedToken = tokenData.access_token as string;
  cachedTokenExpiresAt = now + (typeof tokenData.expires_in === "number" ? tokenData.expires_in : 3600);
  return cachedToken;
}

serve(async (req) => {
  const corsHeaders = getCorsHeaders(req);

  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // --- Authenticate the caller via Supabase JWT ---
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing Authorization header" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const anonClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } }
    );
    const {
      data: { user: caller },
    } = await anonClient.auth.getUser();
    if (!caller) {
      return new Response(
        JSON.stringify({ error: "Not authenticated" }),
        {
          status: 401,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const { topic, token, title, body } = await req.json();
    if (!title || !body || (!topic && !token)) {
      return new Response(
        JSON.stringify({
          error: "title, body, and either topic or token are required",
        }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }
    if (
      typeof title !== "string" ||
      title.length > 200 ||
      typeof body !== "string" ||
      body.length > 1000
    ) {
      return new Response(
        JSON.stringify({ error: "title or body too long" }),
        {
          status: 400,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // --- Require admin privileges for ALL targeted sends (topic or token) ---
    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );
    const { data: adminRow } = await serviceClient
      .from("admins")
      .select("role")
      .eq("user_id", caller.id)
      .maybeSingle();

    if (!adminRow) {
      return new Response(
        JSON.stringify({
          error: "Only admins can send push notifications",
        }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    // H3 (2026-05-17): cap per-admin send rate.
    if (!pushRateLimitOk(caller.id)) {
      return new Response(
        JSON.stringify({ error: "rate_limited", retry_after_seconds: 60 }),
        {
          status: 429,
          headers: { ...corsHeaders, "Content-Type": "application/json", "Retry-After": "60" },
        }
      );
    }

    // Build the FCM message — either topic-based or token-based.
    // NOTE: Do NOT use top-level `notification` key together with `apns` —
    // FCM overrides the APNs sound with "default" when both are present.
    // Instead, set title/body per-platform so custom sound is respected.
    const message: Record<string, unknown> = {
      apns: {
        headers: { "apns-priority": "10" },
        payload: {
          aps: {
            alert: { title, body },
            sound: "quest_notification.caf",
          },
        },
      },
      android: {
        notification: {
          title,
          body,
          sound: "quest_notification",
        },
      },
      data: { type: "notification", title, body },
    };
    if (token) {
      message.token = token;
    } else {
      message.topic = topic;
    }

    const firebaseProjectId =
      Deno.env.get("FIREBASE_PROJECT_ID") || "bitsheel";
    const accessToken = await getAccessToken();
    const fcmResponse = await fetch(
      `https://fcm.googleapis.com/v1/projects/${firebaseProjectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${accessToken}`,
        },
        body: JSON.stringify({ message }),
      }
    );
    const result = await fcmResponse.json();
    return new Response(JSON.stringify({ success: true, fcm: result }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    // SEC-012: log internals server-side, don't leak them to the caller.
    console.error("[send-push] internal error", error);
    return new Response(JSON.stringify({ error: "internal_error" }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
