// Sends a Telegram alert with Re-approve / Re-reject buttons when a user
// appeals a previously-rejected submission. Detected on submissions UPDATE
// when `appealed` flips false → true.
//
// Wire as a Supabase DB Webhook:
//   Table:   public.submissions
//   Events:  UPDATE
//   URL:     https://api.bsheel.app/functions/v1/telegram-notify-appeal
//   Headers: x-webhook-secret: <TELEGRAM_WEBHOOK_SECRET>
//
// Note: this is a SEPARATE webhook from telegram-sync-submission. Both
// fire on submissions UPDATE, but each one filters for its own event:
//   - sync-submission:  status flip pending → approved/rejected
//   - notify-appeal:    appealed flip false → true
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
    if (got !== WEBHOOK_SECRET) return new Response("forbidden", { status: 403 });
  }

  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }
  if (payload?.type !== "UPDATE") {
    return new Response("ignored (not update)", { status: 200 });
  }
  const row = payload?.record;
  const old = payload?.old_record;
  if (!row || !old) return new Response("ignored", { status: 200 });

  // Fire only on the moment the user appeals (appealed flips to true and
  // the submission goes back to pending).
  if (!(old.appealed === false && row.appealed === true)) {
    return new Response("ignored (not appeal flip)", { status: 200 });
  }

  const submissionId: string = row.id;
  const userId: string | null = row.user_id ?? null;
  const userQuestId: string | null = row.user_quest_id ?? null;
  const note: string | null = row.review_note ?? null;

  let questTitle = "(unknown quest)";
  if (userQuestId) {
    const { data } = await supabase
      .from("user_quests")
      .select("quests:quest_id (title)")
      .eq("id", userQuestId)
      .maybeSingle();
    const t = (data as any)?.quests?.title as string | undefined;
    if (t && t.trim()) questTitle = t;
  }

  let userName = "(unknown user)";
  if (userId) {
    const { data } = await supabase
      .from("profiles")
      .select("username, display_name")
      .eq("id", userId)
      .maybeSingle();
    if (data) {
      userName = data.display_name ||
        (data.username ? `@${data.username}` : userName);
    }
  }

  const text = [
    "<b>📩 APPEAL SUBMITTED</b>",
    "",
    `<b>Quest:</b> ${esc(questTitle)}`,
    `<b>User:</b> ${esc(userName)}`,
    note && note.trim() ? `<b>Appeal note:</b> ${esc(note.trim())}` : null,
    "",
    `<code>${esc(submissionId)}</code>`,
  ].filter(Boolean).join("\n");

  const body = {
    chat_id: ADMIN_CHAT_ID,
    text,
    parse_mode: "HTML",
    reply_markup: {
      inline_keyboard: [
        [
          { text: "✅ Approve appeal", callback_data: `approve:${submissionId}` },
          { text: "❌ Reject again", callback_data: `reject:${submissionId}` },
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
    } else {
      // Persist the appeal-message id so telegram-sync-submission can
      // edit THIS message later (and not the original alert).
      try {
        const json = await res.json();
        const id = json?.result?.message_id;
        if (typeof id === "number") {
          await supabase
            .from("submissions")
            .update({ telegram_message_id: id })
            .eq("id", submissionId);
        }
      } catch (_) {/* best-effort */}
    }
  } catch (e) {
    console.error("telegram-notify-appeal", e);
  }
  return new Response("ok", { status: 200 });
});
