import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

/** URL-safe base64 encode (no padding) */
function base64url(input: string): string {
  return btoa(input)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function getAccessToken(): Promise<string> {
  const serviceAccount = JSON.parse(
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}"
  );
  const now = Math.floor(Date.now() / 1000);
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64url(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  );
  const keyData = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\n/g, "");
  const key = await crypto.subtle.importKey(
    "pkcs8",
    Uint8Array.from(atob(keyData), (c) => c.charCodeAt(0)),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
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
  const data = await tokenResponse.json();
  return data.access_token;
}

async function sendFcmPush(
  fcmToken: string,
  title: string,
  body: string,
  userId?: string,
  metadata: {
    notificationId?: string;
    referenceId?: string;
    actorId?: string;
    actorUsername?: string;
    actorAvatarUrl?: string;
  } = {},
): Promise<void> {
  const firebaseProjectId =
    Deno.env.get("FIREBASE_PROJECT_ID") || "bitsheel";
  const accessToken = await getAccessToken();
  const imageUrl =
    metadata.actorAvatarUrl?.startsWith("https://") ? metadata.actorAvatarUrl : undefined;

  const message = {
    token: fcmToken,
    apns: {
      headers: { "apns-priority": "10" },
      payload: {
        aps: {
          alert: { title, body },
          sound: "quest_notification.caf",
          "mutable-content": imageUrl ? 1 : undefined,
        },
      },
      fcm_options: imageUrl ? { image: imageUrl } : undefined,
    },
    android: {
      notification: {
        title,
        body,
        sound: "quest_notification",
        image: imageUrl,
      },
    },
    data: {
      type: "notification",
      title,
      body,
      notification_id: metadata.notificationId ?? "",
      reference_id: metadata.referenceId ?? "",
      actor_id: metadata.actorId ?? "",
      actor_username: metadata.actorUsername ?? "",
      actor_avatar_url: metadata.actorAvatarUrl ?? "",
    },
  };

  const res = await fetch(
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

  if (!res.ok) {
    const err = await res.json();
    console.error("[notify-on-insert] FCM error:", JSON.stringify(err));
    // If token is invalid/unregistered, clean it up from the DB
    const errorCode = err?.error?.details?.[0]?.errorCode ?? err?.error?.code ?? "";
    if ((errorCode === "UNREGISTERED" || errorCode === "INVALID_ARGUMENT") && userId) {
      console.log("[notify-on-insert] Stale token detected, cleaning up for user:", userId);
      const cleanupClient = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );
      await cleanupClient.rpc("cleanup_stale_fcm_token", { p_user_id: userId });
    }
  }
}

serve(async (req) => {
  try {
    // Verify caller is using a service role key.
    // pg_net trigger sends the key stored in Supabase Vault.
    const authHeader = req.headers.get("Authorization") ?? "";
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const token = authHeader.replace("Bearer ", "");
    if (!token || token !== serviceRoleKey) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Supabase Database Webhooks send the record in the body as:
    // { type: "INSERT", table: "notifications", record: { ... }, ... }
    const payload = await req.json();
    const record = payload.record ?? payload; // support both webhook and direct call formats

    const userId: string = record.user_id;
    const title: string = record.title;
    const body: string = record.body;
    const actorId: string | undefined = record.actor_id;

    if (!userId || !title || !body) {
      return new Response(JSON.stringify({ error: "Missing fields" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Look up FCM token from private.profile_tokens via a SECURITY DEFINER RPC.
    // The private schema is not exposed through PostgREST — .schema('private')
    // does NOT work. The get_fcm_token RPC (migration 0035) reads from the
    // private schema and is restricted to service_role only.
    const serviceClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: fcmToken, error: tokenError } = await serviceClient
      .rpc("get_fcm_token", { p_user_id: userId });

    if (tokenError) {
      console.error("[notify-on-insert] Token lookup error:", tokenError.message);
    }

    if (!fcmToken) {
      // User has no FCM token registered — skip silently
      return new Response(JSON.stringify({ skipped: "no_fcm_token" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    let actorUsername = "";
    let actorAvatarUrl = "";
    if (actorId) {
      const { data: actorProfile, error: actorError } = await serviceClient
        .from("profiles")
        .select("username, avatar_url")
        .eq("id", actorId)
        .maybeSingle();

      if (actorError) {
        console.error("[notify-on-insert] Actor lookup error:", actorError.message);
      }

      actorUsername = actorProfile?.username ?? "";
      actorAvatarUrl = actorProfile?.avatar_url ?? "";
    }

    await sendFcmPush(fcmToken, title, body, userId, {
      notificationId: record.id,
      referenceId: record.reference_id,
      actorId,
      actorUsername,
      actorAvatarUrl,
    });

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (error) {
    // SEC-012: log internals server-side, surface a stable string.
    console.error("[notify-on-insert] internal error", error);
    return new Response(JSON.stringify({ error: "internal_error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
