// Sends a single Telegram alert when a new profile row appears (= a new
// user just signed up). Wire as a Supabase DB Webhook on
//   Table:   public.profiles
//   Events:  INSERT
//   URL:     https://api.bsheel.app/functions/v1/telegram-notify-signup
//   Headers: x-webhook-secret: <TELEGRAM_WEBHOOK_SECRET>
//
// Deploy:
//   Self-hosted: deployed automatically by .github/workflows/deploy-server.yml
//   (rsync to the Contabo box + functions-runtime restart on push to main).

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
const ADMIN_CHAT_ID = Deno.env.get("TELEGRAM_ADMIN_CHAT_ID") ?? "";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const TG = `https://api.telegram.org/bot${BOT_TOKEN}`;

function esc(s: string | null | undefined): string {
  return (s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });

  if (WEBHOOK_SECRET) {
    const got = req.headers.get("x-webhook-secret");
    if (got !== WEBHOOK_SECRET) {
      return new Response("forbidden", { status: 403 });
    }
  }

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }

  if (payload?.type !== "INSERT") {
    return new Response("ignored", { status: 200 });
  }
  const row = payload?.record;
  if (!row?.id) return new Response("ignored", { status: 200 });

  // Look up the auth.users row to get email + provider so we can show
  // how they signed up (email / google / apple).
  let email = "";
  let provider = "";
  try {
    const { data, error } = await supabase.auth.admin.getUserById(row.id);
    if (!error && data?.user) {
      email = data.user.email ?? "";
      const providers =
        (data.user.app_metadata as any)?.providers ??
        ((data.user.app_metadata as any)?.provider
          ? [(data.user.app_metadata as any).provider]
          : []);
      if (Array.isArray(providers) && providers.length > 0) {
        provider = providers.join(", ");
      }
    }
  } catch (e) {
    console.error("getUserById failed", e);
  }

  const username = (row.username as string | null) ?? "";
  const displayName = (row.display_name as string | null) ?? "";
  const handle = username ? `@${username}` : "(no handle yet)";
  const name = displayName || username || "(unnamed)";

  const lines = [
    "<b>🎉 NEW USER</b>",
    "",
    `<b>Name:</b> ${esc(name)}`,
    `<b>Handle:</b> ${esc(handle)}`,
    email ? `<b>Email:</b> ${esc(email)}` : null,
    provider ? `<b>Via:</b> ${esc(provider)}` : null,
    "",
    `<code>${esc(row.id)}</code>`,
  ].filter(Boolean).join("\n");

  try {
    const res = await fetch(`${TG}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: ADMIN_CHAT_ID,
        text: lines,
        parse_mode: "HTML",
      }),
    });
    if (!res.ok) {
      console.error("telegram sendMessage failed", await res.text());
    }
  } catch (e) {
    console.error("telegram-notify-signup", e);
  }
  return new Response("ok", { status: 200 });
});
