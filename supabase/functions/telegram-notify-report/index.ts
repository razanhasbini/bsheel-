// Sends a Telegram alert with Dismiss / Action buttons whenever a new
// row is inserted into public.reports. Wire as a Supabase DB Webhook:
//   Table:   public.reports
//   Events:  INSERT
//   URL:     https://api.bsheel.app/functions/v1/telegram-notify-report
//   Headers: x-webhook-secret: <TELEGRAM_WEBHOOK_SECRET>
//
// The buttons here pipe through the same telegram-webhook function as the
// submission Approve/Reject flow — its callback handler routes by the
// `report:` prefix.
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

async function nameFor(userId: string | null | undefined): Promise<string> {
  if (!userId) return "(unknown)";
  const { data } = await supabase
    .from("profiles")
    .select("username, display_name")
    .eq("id", userId)
    .maybeSingle();
  if (!data) return "(unknown)";
  return data.display_name || (data.username ? `@${data.username}` : "(unknown)");
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });
  if (WEBHOOK_SECRET) {
    const got = req.headers.get("x-webhook-secret");
    if (got !== WEBHOOK_SECRET) return new Response("forbidden", { status: 403 });
  }

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }
  if (payload?.type !== "INSERT") return new Response("ignored", { status: 200 });

  const row = payload?.record;
  if (!row?.id) return new Response("ignored", { status: 200 });
  if (row.status && row.status !== "pending") {
    return new Response("not pending", { status: 200 });
  }

  const reportId: string = row.id;
  const reportedType: string = row.reported_type ?? "?";
  const reportedId: string = row.reported_id ?? "";
  const reason: string = row.reason ?? "";

  const reporter = await nameFor(row.reporter_id);

  // For submission reports we can look up the offender user too.
  let reportedName = `(${reportedType})`;
  if (reportedType === "user") {
    reportedName = await nameFor(reportedId);
  } else if (reportedType === "submission") {
    const { data: sub } = await supabase
      .from("submissions")
      .select("user_id")
      .eq("id", reportedId)
      .maybeSingle();
    if (sub?.user_id) reportedName = await nameFor(sub.user_id);
  }

  const text = [
    "<b>🚨 NEW REPORT</b>",
    "",
    `<b>Reporter:</b> ${esc(reporter)}`,
    `<b>Reported:</b> ${esc(reportedName)} (${esc(reportedType)})`,
    `<b>Reason:</b> ${esc(reason)}`,
    "",
    `<code>${esc(reportId)}</code>`,
  ].join("\n");

  const body = {
    chat_id: ADMIN_CHAT_ID,
    text,
    parse_mode: "HTML",
    reply_markup: {
      inline_keyboard: [
        [
          {
            text: "✅ Action (ban + dismiss)",
            callback_data: `report_action:${reportId}`,
          },
          {
            text: "❌ Dismiss",
            callback_data: `report_dismiss:${reportId}`,
          },
        ],
      ],
    },
  };

  try {
    const res = await fetch(`${TG}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      console.error("telegram sendMessage failed", await res.text());
    }
  } catch (e) {
    console.error("telegram-notify-report", e);
  }
  return new Response("ok", { status: 200 });
});
