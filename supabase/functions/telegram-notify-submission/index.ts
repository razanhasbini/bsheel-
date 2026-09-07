// Sends a Telegram message with Approve/Reject inline buttons whenever
// a new submission row is inserted, plus a media group containing every
// image / video the user attached.
//
// Wire this up as a Supabase Database Webhook:
//   Table:   public.submissions
//   Events:  INSERT
//   URL:     https://api.bsheel.app/functions/v1/telegram-notify-submission
//   HTTP headers: x-webhook-secret: <TELEGRAM_WEBHOOK_SECRET>
//
// Required env:
//   TELEGRAM_BOT_TOKEN
//   TELEGRAM_WEBHOOK_SECRET   (re-used to authenticate DB webhook)
//   TELEGRAM_ADMIN_CHAT_ID    (single chat id that receives alerts)
//   SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY (auto)
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

/** Parse the `media_url` field. Stored as a JSON array string for
 * multi-asset posts, a single URL for one-asset posts, or null/empty. */
function parseMediaUrls(raw: unknown): string[] {
  if (!raw) return [];
  if (Array.isArray(raw)) return raw.filter((u) => typeof u === "string" && u);
  if (typeof raw === "string") {
    const trimmed = raw.trim();
    if (!trimmed) return [];
    if (trimmed.startsWith("[")) {
      try {
        const parsed = JSON.parse(trimmed);
        if (Array.isArray(parsed)) {
          return parsed.filter((u) => typeof u === "string" && u);
        }
      } catch {
        // fall through to single-URL handling
      }
    }
    return [trimmed];
  }
  return [];
}

function isVideoUrl(url: string, mediaType: string | null): boolean {
  if (mediaType === "video") return true;
  const lower = url.toLowerCase().split("?")[0];
  return [".mp4", ".mov", ".webm", ".m4v"].some((ext) => lower.endsWith(ext));
}

/** Send a single message with Approve/Reject buttons.
 *  Returns the Telegram message_id so callers can persist it for later
 *  edits (web-side review sync). */
async function sendCaptionMessage(
  text: string,
  submissionId: string,
): Promise<number | null> {
  const body = {
    chat_id: ADMIN_CHAT_ID,
    text,
    parse_mode: "HTML",
    reply_markup: {
      inline_keyboard: [
        [
          { text: "✅ Approve", callback_data: `approve:${submissionId}` },
          { text: "❌ Reject", callback_data: `reject:${submissionId}` },
        ],
      ],
    },
  };
  const res = await fetch(`${TG}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    console.error("telegram sendMessage failed", await res.text());
    return null;
  }
  try {
    const json = await res.json();
    const id = json?.result?.message_id;
    return typeof id === "number" ? id : null;
  } catch (_) {
    return null;
  }
}

/** Send a Telegram media group with up to 10 mixed photos/videos. */
async function sendMediaGroup(
  urls: string[],
  mediaType: string | null,
  caption: string,
): Promise<void> {
  // Telegram caps a media group at 10 items.
  const slice = urls.slice(0, 10);
  if (slice.length === 0) return;

  const media = slice.map((url, i) => ({
    type: isVideoUrl(url, mediaType) ? "video" : "photo",
    media: url,
    // Caption goes only on the first item; Telegram rejects per-item
    // captions on subsequent media in a group.
    ...(i === 0 ? { caption, parse_mode: "HTML" } : {}),
  }));

  const res = await fetch(`${TG}/sendMediaGroup`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: ADMIN_CHAT_ID, media }),
  });
  if (!res.ok) {
    console.error("telegram sendMediaGroup failed", await res.text());
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

  // Supabase DB webhook shape: { type, table, record, old_record, schema }
  const row = payload?.record;
  if (!row || payload?.type !== "INSERT") {
    return new Response("ignored", { status: 200 });
  }
  if (row.status && row.status !== "pending") {
    return new Response("not pending", { status: 200 });
  }

  const submissionId: string = row.id;
  const userId: string | null = row.user_id ?? null;
  const userQuestId: string | null = row.user_quest_id ?? null;
  const caption: string | null = row.caption ?? null;
  const mediaType: string | null = row.media_type ?? null;
  const mediaUrls = parseMediaUrls(row.media_url);

  // Resolve the quest title via the user_quest → quest join.
  // The submissions table only stores user_quest_id; quests live one hop
  // away, which is why the previous "row.quest_id" lookup always failed.
  let questTitle = "(unknown quest)";
  if (userQuestId) {
    const { data, error } = await supabase
      .from("user_quests")
      .select("quests:quest_id (title)")
      .eq("id", userQuestId)
      .maybeSingle();
    if (error) {
      console.error("user_quest lookup failed", error);
    }
    const t = (data as any)?.quests?.title as string | undefined;
    if (t && t.trim().length > 0) questTitle = t;
  }

  // Resolve the user.
  let userName = "(unknown user)";
  let userHandle = "";
  if (userId) {
    const { data } = await supabase
      .from("profiles")
      .select("username, display_name")
      .eq("id", userId)
      .maybeSingle();
    if (data) {
      userName = data.display_name || data.username || userName;
      if (data.username) userHandle = `@${data.username}`;
    }
  }

  // Build the caption / message body.
  const headerLines = [
    "<b>🆕 NEW SUBMISSION</b>",
    "",
    `<b>Quest:</b> ${esc(questTitle)}`,
    `<b>User:</b> ${esc(userName)}${
      userHandle ? ` (${esc(userHandle)})` : ""
    }`,
  ];
  if (caption && caption.trim().length > 0) {
    headerLines.push(`<b>Caption:</b> ${esc(caption.trim())}`);
  }
  if (mediaUrls.length > 0) {
    headerLines.push(
      `<b>Media:</b> ${mediaUrls.length} ${
        mediaUrls.length === 1 ? "file" : "files"
      }`,
    );
  }
  if (row.review_note) {
    headerLines.push(`<b>Note:</b> ${esc(row.review_note)}`);
  }
  headerLines.push("", `<code>${esc(submissionId)}</code>`);
  const headerText = headerLines.join("\n");

  let buttonMessageId: number | null = null;
  try {
    if (mediaUrls.length > 0) {
      // Telegram caption hard limit on media groups is 1024 chars; the
      // header is well under that even with a long quest title + caption.
      // Media group goes first (admins see the proof inline), then the
      // approve/reject button message follows so the buttons stay
      // tappable at the bottom of the chat.
      await sendMediaGroup(mediaUrls, mediaType, headerText);
      buttonMessageId = await sendCaptionMessage(
        `<b>${esc(questTitle)}</b> — review the media above ⬆️`,
        submissionId,
      );
    } else {
      buttonMessageId = await sendCaptionMessage(headerText, submissionId);
    }
  } catch (e) {
    console.error("telegram-notify-submission", e);
  }

  // Persist the button-message id so telegram-sync-submission can edit
  // it later if the review happens via the admin web panel instead of
  // via the inline buttons.
  if (buttonMessageId !== null) {
    try {
      await supabase
        .from("submissions")
        .update({ telegram_message_id: buttonMessageId })
        .eq("id", submissionId);
    } catch (e) {
      console.error("telegram-notify-submission: persist message_id", e);
    }
  }

  return new Response("ok", { status: 200 });
});
