// Edits the original Telegram alert when a submission's status flips
// to approved/rejected via the admin WEB panel (or any non-Telegram
// path). Without this, the original Telegram message keeps showing
// the Approve/Reject buttons looking actionable even though the
// submission has already been reviewed.
//
// Wire this up as a Supabase Database Webhook:
//   Table:   public.submissions
//   Events:  UPDATE
//   URL:     https://api.bsheel.app/functions/v1/telegram-sync-submission
//   HTTP headers: x-webhook-secret: <TELEGRAM_WEBHOOK_SECRET>
//
// Required env (same as the other telegram functions):
//   TELEGRAM_BOT_TOKEN
//   TELEGRAM_WEBHOOK_SECRET
//   TELEGRAM_ADMIN_CHAT_ID
//
// Deploy:
//   Self-hosted: deployed automatically by .github/workflows/deploy-server.yml
//   (rsync to the Contabo box + functions-runtime restart on push to main).

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
const ADMIN_CHAT_ID = Deno.env.get("TELEGRAM_ADMIN_CHAT_ID") ?? "";

const TG = `https://api.telegram.org/bot${BOT_TOKEN}`;

function esc(s: string | null | undefined): string {
  return (s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

/** Replace the message text + drop the inline keyboard so the buttons
 *  disappear after the submission is reviewed elsewhere. Telegram is
 *  fine with editMessageText replacing reply_markup as part of the
 *  same call — pass an empty inline_keyboard to clear it. */
async function editMessage(
  messageId: number,
  text: string,
): Promise<void> {
  const res = await fetch(`${TG}/editMessageText`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: ADMIN_CHAT_ID,
      message_id: messageId,
      text,
      parse_mode: "HTML",
      reply_markup: { inline_keyboard: [] },
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    // 400 + "message is not modified" is the common no-op; ignore it.
    if (!body.includes("message is not modified")) {
      console.error("telegram editMessageText failed", res.status, body);
    }
  }
}

// F-011: privacy-policy cascade — when a submission is deleted, the
// moderation channel's copy should also disappear. 400 + "message to
// delete not found" is benign (already gone); everything else logs.
async function deleteMessage(messageId: number): Promise<void> {
  const res = await fetch(`${TG}/deleteMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      chat_id: ADMIN_CHAT_ID,
      message_id: messageId,
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    if (!body.includes("message to delete not found")) {
      console.error("telegram deleteMessage failed", res.status, body);
    }
  }
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

  if (payload?.type !== "UPDATE") {
    return new Response("ignored (not update)", { status: 200 });
  }
  const row = payload?.record;
  const old = payload?.old_record;
  if (!row || !old) {
    return new Response("ignored (missing record)", { status: 200 });
  }

  // F-011 (pentest 2026-05-20): when a submission becomes deleted
  // (either soft via visibility=deleted/deleted_at IS NOT NULL, or by
  // user self-delete that hard-removes the row), the corresponding
  // Telegram moderation message must also disappear. Without this,
  // the privacy policy promise ("deletion cascades to Telegram")
  // breaks and the mirror channel keeps copies forever.
  const wasVisible = old.visibility === "visible" && old.deleted_at == null;
  const nowDeleted =
    row.visibility !== "visible" || row.deleted_at != null;
  if (wasVisible && nowDeleted) {
    const mid = row.telegram_message_id as number | null | undefined;
    if (mid) {
      try {
        await deleteMessage(mid);
      } catch (e) {
        console.error("telegram-sync-submission delete", e);
      }
    }
    return new Response("ok (deleted cascade)", { status: 200 });
  }

  // Only react to a status transition out of 'pending' — i.e. the
  // moment the submission was actually reviewed.
  const wasPending = old.status === "pending";
  const nowReviewed =
    row.status === "approved" || row.status === "rejected";
  if (!wasPending || !nowReviewed) {
    return new Response("ignored (not a pending → reviewed flip)", {
      status: 200,
    });
  }

  const messageId = row.telegram_message_id as number | null | undefined;
  if (!messageId) {
    // Submission landed before we started tracking message ids, OR
    // the original Telegram alert failed to send. Nothing to edit.
    return new Response("no telegram_message_id", { status: 200 });
  }

  const prefix = row.status === "approved" ? "✅ APPROVED" : "❌ REJECTED";
  const note = row.review_note ? `\n<i>${esc(row.review_note)}</i>` : "";
  const newText = `${prefix}${note}\n\n<i>Reviewed via the admin panel.</i>`;

  try {
    await editMessage(messageId, newText);
  } catch (e) {
    console.error("telegram-sync-submission", e);
  }

  // Tier 1 #4: when an appealed submission gets re-rejected, fire a
  // separate alert so the admin team notices a "rejected x2" — useful
  // for spotting if reviewers are being too strict / pattern emerging.
  if (row.status === "rejected" && row.appealed === true) {
    await sendSecondRejectAlert(row);
  }

  return new Response("ok", { status: 200 });
});

async function sendSecondRejectAlert(row: any): Promise<void> {
  const submissionId: string = row.id;
  const userId: string | null = row.user_id ?? null;
  const userQuestId: string | null = row.user_quest_id ?? null;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

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
    "<b>⚠️ SECOND REJECT</b>",
    "",
    `<b>Quest:</b> ${esc(questTitle)}`,
    `<b>User:</b> ${esc(userName)}`,
    "",
    "This submission has now been rejected twice — final decision.",
    "Worth a quick sanity check on whether the rejection criteria are",
    "too strict for this quest type.",
    "",
    `<code>${esc(submissionId)}</code>`,
  ].join("\n");

  try {
    const res = await fetch(`${TG}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: ADMIN_CHAT_ID,
        text,
        parse_mode: "HTML",
      }),
    });
    if (!res.ok) {
      console.error("second-reject sendMessage failed", await res.text());
    }
  } catch (e) {
    console.error("second-reject", e);
  }
}
