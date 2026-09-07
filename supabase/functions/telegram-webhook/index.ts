// Telegram bot webhook for Bit Sheel? admin actions.
//
// Responsibilities:
//   1. Approve / reject user submissions from inline buttons.
//   2. Broadcast a push notification to every user via /broadcast <msg>.
//
// Required env:
//   TELEGRAM_BOT_TOKEN          - from @BotFather
//   TELEGRAM_WEBHOOK_SECRET     - value sent as X-Telegram-Bot-Api-Secret-Token
//   TELEGRAM_ALLOWED_CHAT_IDS   - comma-separated chat ids allowed to control the bot
//   FIREBASE_SERVICE_ACCOUNT    - already used by send-push
//   FIREBASE_PROJECT_ID         - already used by send-push
//   SUPABASE_URL                - auto
//   SUPABASE_SERVICE_ROLE_KEY   - auto
//
// Deploy with:
//   Self-hosted: deployed automatically by .github/workflows/deploy-server.yml
//   (rsync to the Contabo box + functions-runtime restart on push to main).
// Then register the webhook:
//   curl "https://api.telegram.org/bot<TOKEN>/setWebhook" \
//     -d url="https://api.bsheel.app/functions/v1/telegram-webhook" \
//     -d secret_token="<TELEGRAM_WEBHOOK_SECRET>"

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.10";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";

// Constant-time string equality. Avoids the byte-by-byte timing side
// channel of `a === b` on the webhook secret check — see audit C6
// (2026-05-17).
function constantTimeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  let diff = ab.length ^ bb.length;
  const n = Math.min(ab.length, bb.length);
  for (let i = 0; i < n; i++) diff |= ab[i] ^ bb[i];
  return diff === 0;
}
const ALLOWED_CHAT_IDS = (Deno.env.get("TELEGRAM_ALLOWED_CHAT_IDS") ?? "")
  .split(",")
  .map((s) => s.trim())
  .filter(Boolean);

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// ---------- Telegram helpers ----------

async function tg(method: string, body: Record<string, unknown>) {
  const res = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return await res.json();
}

async function answerCallback(id: string, text: string) {
  return tg("answerCallbackQuery", { callback_query_id: id, text });
}

async function sendMessage(chatId: number | string, text: string) {
  return tg("sendMessage", { chat_id: chatId, text, parse_mode: "HTML" });
}

async function editMessageText(
  chatId: number | string,
  messageId: number,
  text: string,
  { clearKeyboard = false }: { clearKeyboard?: boolean } = {},
) {
  return tg("editMessageText", {
    chat_id: chatId,
    message_id: messageId,
    text,
    parse_mode: "HTML",
    // Pass an empty inline_keyboard to drop the buttons after the
    // submission was reviewed. Without this they stay tappable but
    // would just hit the "Already approved/rejected" guard.
    ...(clearKeyboard
      ? { reply_markup: { inline_keyboard: [] } }
      : {}),
  });
}

// ---------- FCM (JWT + v1 send) ----------

function base64url(input: string): string {
  return btoa(input).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getFcmAccessToken(): Promise<string> {
  const serviceAccount = JSON.parse(
    Deno.env.get("FIREBASE_SERVICE_ACCOUNT") ?? "{}",
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
    }),
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
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(`${header}.${payload}`),
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

async function sendFcmToToken(
  accessToken: string,
  token: string,
  title: string,
  body: string,
): Promise<"ok" | "unregistered" | "error"> {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID") || "bitsheel";
  const message = {
    token,
    apns: {
      headers: { "apns-priority": "10" },
      payload: {
        aps: { alert: { title, body }, sound: "quest_notification.caf" },
      },
    },
    android: {
      notification: { title, body, sound: "quest_notification" },
    },
    data: { type: "broadcast", title, body },
  };
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ message }),
    },
  );
  if (res.ok) return "ok";
  const err = await res.json().catch(() => ({}));
  const status = err?.error?.details?.[0]?.errorCode ?? err?.error?.status;
  if (status === "UNREGISTERED" || status === "NOT_FOUND") return "unregistered";
  return "error";
}

// ---------- Actions ----------

async function reviewSubmission(
  submissionId: string,
  approve: boolean,
  telegramChatId?: number | string,
  telegramMessageId?: number,
): Promise<{ ok: boolean; message: string }> {
  // SEC-018: route through telegram_review_submission (migration 0125).
  // We CANNOT call admin_approve_submission / admin_reject_submission
  // directly here — those RPCs check is_admin() against auth.uid(),
  // which is null for the service-role webhook. telegram_review_submission
  // is a SECURITY DEFINER wrapper scoped to service_role; sets the 0119
  // bypass GUC, applies the same BEFORE-UPDATE guard rules
  // admin_approve/reject would, and writes an admin_audit_log row tagged
  // source=telegram so this path stays auditable. (Supersedes the PR #52
  // attempt to call the admin_* RPCs directly, which would 42501 here.)
  const { error } = await supabase.rpc("telegram_review_submission", {
    p_submission_id: submissionId,
    p_approve: approve,
    p_review_note: approve ? null : "Rejected via Telegram",
    p_telegram_chat_id: telegramChatId !== undefined ? String(telegramChatId) : null,
    p_telegram_msg_id: telegramMessageId !== undefined ? String(telegramMessageId) : null,
  });
  if (error) {
    const msg = (error.message || "").toLowerCase();
    if (msg.includes("not found")) return { ok: false, message: "Submission not found" };
    if (msg.includes("no longer pending")) return { ok: false, message: "Already moderated" };
    console.error("[telegram-webhook] telegram_review_submission failed", error);
    return { ok: false, message: "Internal error" };
  }
  return { ok: true, message: approve ? "Approved" : "Rejected" };
}

async function broadcastToAll(
  title: string,
  body: string,
): Promise<{ sent: number; failed: number; stale: number }> {
  const { data: rows, error } = await supabase.rpc("get_all_fcm_tokens");
  if (error) throw error;
  const accessToken = await getFcmAccessToken();
  let sent = 0;
  let failed = 0;
  let stale = 0;
  for (const row of rows ?? []) {
    const token = (row as { fcm_token: string }).fcm_token;
    const userId = (row as { user_id: string }).user_id;
    try {
      const result = await sendFcmToToken(accessToken, token, title, body);
      if (result === "ok") sent++;
      else if (result === "unregistered") {
        stale++;
        await supabase.rpc("cleanup_stale_fcm_token", { p_user_id: userId });
      } else failed++;
    } catch (_) {
      failed++;
    }
  }
  return { sent, failed, stale };
}

// ---------- Update handlers ----------

function isAllowed(chatId: number | undefined): boolean {
  if (!chatId) return false;
  return ALLOWED_CHAT_IDS.includes(String(chatId));
}

async function handleCallback(cb: any) {
  const chatId = cb.message?.chat?.id;
  if (!isAllowed(chatId)) {
    await answerCallback(cb.id, "Not authorized");
    return;
  }
  const data: string = cb.data ?? "";
  const [action, targetId] = data.split(":");
  if (!targetId) {
    await answerCallback(cb.id, "Unknown action");
    return;
  }

  switch (action) {
    case "approve":
    case "reject":
      await handleSubmissionCallback(cb, chatId, action, targetId);
      return;
    case "report_action":
    case "report_dismiss":
      await handleReportCallback(cb, chatId, action, targetId);
      return;
    default:
      await answerCallback(cb.id, "Unknown action");
  }
}

async function handleSubmissionCallback(
  cb: any,
  chatId: number | string,
  action: "approve" | "reject",
  submissionId: string,
) {
  const result = await reviewSubmission(
    submissionId,
    action === "approve",
    chatId,
    cb.message?.message_id,
  );
  await answerCallback(cb.id, result.message);
  if (cb.message?.message_id) {
    const prefix = result.ok
      ? action === "approve"
        ? "✅ APPROVED"
        : "❌ REJECTED"
      : "⚠️ " + result.message;
    const original = cb.message.text ?? "";
    await editMessageText(
      chatId,
      cb.message.message_id,
      `${prefix}\n\n${original}`,
      { clearKeyboard: result.ok },
    );
  }
}

/** Resolve the offender for a report row. Returns the user_id of the
 *  person to action against (or null if it can't be determined). */
async function reportOffenderUserId(
  reportId: string,
): Promise<{ ok: boolean; userId?: string; reason?: string }> {
  const { data: report, error } = await supabase
    .from("reports")
    .select("id, status, reported_type, reported_id")
    .eq("id", reportId)
    .maybeSingle();
  if (error || !report) return { ok: false, reason: "Report not found" };
  if (report.status !== "pending") {
    return { ok: false, reason: `Already ${report.status}` };
  }
  switch (report.reported_type) {
    case "user":
      return { ok: true, userId: report.reported_id };
    case "submission": {
      const { data: sub } = await supabase
        .from("submissions")
        .select("user_id")
        .eq("id", report.reported_id)
        .maybeSingle();
      if (!sub?.user_id) return { ok: false, reason: "Submission not found" };
      return { ok: true, userId: sub.user_id };
    }
    case "comment": {
      const { data: c } = await supabase
        .from("comments")
        .select("user_id")
        .eq("id", report.reported_id)
        .maybeSingle();
      if (!c?.user_id) return { ok: false, reason: "Comment not found" };
      return { ok: true, userId: c.user_id };
    }
    default:
      return { ok: false, reason: "Unknown reported_type" };
  }
}

async function handleReportCallback(
  cb: any,
  chatId: number | string,
  action: "report_action" | "report_dismiss",
  reportId: string,
) {
  if (action === "report_dismiss") {
    const { error } = await supabase
      .from("reports")
      .update({ status: "dismissed", reviewed_at: new Date().toISOString() })
      .eq("id", reportId)
      .eq("status", "pending");
    if (error) {
      await answerCallback(cb.id, "Failed: " + error.message);
      return;
    }
    await answerCallback(cb.id, "Dismissed");
    if (cb.message?.message_id) {
      await editMessageText(
        chatId,
        cb.message.message_id,
        `❌ DISMISSED\n\n${cb.message.text ?? ""}`,
        { clearKeyboard: true },
      );
    }
    return;
  }

  // report_action — ban the offender + mark report as actioned.
  const offender = await reportOffenderUserId(reportId);
  if (!offender.ok || !offender.userId) {
    await answerCallback(cb.id, offender.reason ?? "Failed");
    return;
  }
  const { error: banError } = await supabase.rpc(
    "set_user_account_status",
    { p_user_id: offender.userId, p_status: "banned" },
  );
  if (banError) {
    await answerCallback(cb.id, "Ban failed: " + banError.message);
    return;
  }
  await supabase
    .from("reports")
    .update({ status: "actioned", reviewed_at: new Date().toISOString() })
    .eq("id", reportId);
  await answerCallback(cb.id, "User banned");
  if (cb.message?.message_id) {
    await editMessageText(
      chatId,
      cb.message.message_id,
      `✅ ACTIONED · user banned\n\n${cb.message.text ?? ""}`,
      { clearKeyboard: true },
    );
  }
}

async function handleMessage(msg: any) {
  const chatId = msg.chat?.id;
  if (!isAllowed(chatId)) {
    await sendMessage(chatId, "Not authorized.");
    return;
  }
  const text: string = (msg.text ?? "").trim();

  // /cancel always wins — kills any pending FSM and short-circuits.
  if (text.toLowerCase() === "/cancel") {
    await clearFsmState(chatId);
    await sendMessage(chatId, "Cancelled.");
    return;
  }

  // If a multi-step command is in progress (e.g. /quest add), route
  // free text through the FSM before the slash dispatcher.
  if (!text.startsWith("/")) {
    const handled = await routeFsmInput(chatId, text);
    if (handled) return;
    await sendMessage(chatId, "Unknown command. Try /help");
    return;
  }

  // First word = command (strip @botname suffix Telegram appends in groups).
  const firstSpace = text.indexOf(" ");
  const head = (firstSpace === -1 ? text : text.slice(0, firstSpace))
    .split("@")[0]
    .toLowerCase();
  const rest = firstSpace === -1 ? "" : text.slice(firstSpace + 1).trim();

  switch (head) {
    case "/start":
    case "/help":
      await handleHelp(chatId);
      return;
    case "/broadcast":
      await handleBroadcast(chatId, rest);
      return;
    case "/pending":
      await handlePending(chatId);
      return;
    case "/stats":
      await handleStats(chatId, rest);
      return;
    case "/user":
      await handleUser(chatId, rest);
      return;
    case "/ban":
      await handleBan(chatId, rest, true);
      return;
    case "/unban":
      await handleBan(chatId, rest, false);
      return;
    case "/quest":
      await handleQuest(chatId, rest);
      return;
    case "/audit":
      await handleAudit(chatId, rest);
      return;
    case "/leaderboard":
      await handleLeaderboard(chatId);
      return;
    default:
      await sendMessage(chatId, "Unknown command. Try /help");
  }
}

async function handleHelp(chatId: number | string) {
  await sendMessage(
    chatId,
    [
      "<b>Bit Sheel? admin bot</b>",
      "",
      "<b>Push</b>",
      "• /broadcast &lt;title&gt; | &lt;body&gt; — push to all users",
      "",
      "<b>Triage</b>",
      "• /pending — pending submissions, appeals, reports",
      "• /stats — today's submissions/approvals/signups/DAU",
      "• /stats week — same, last 7 days",
      "",
      "<b>Users</b>",
      "• /user @handle — profile card",
      "• /ban @handle — ban a user",
      "• /unban @handle — restore access",
      "",
      "<b>Quests</b>",
      "• /quest spotlight — push today's spotlight to all users",
      "• /quest add — interactive new-quest flow",
      "• /cancel — abort any in-progress flow",
      "",
      "<b>Audit</b>",
      "• /audit — last 10 admin actions",
      "• /audit @admin — filter by admin handle",
      "• /leaderboard — top 5 this week",
      "",
      "Submissions, reports and appeals arrive here with action buttons.",
    ].join("\n"),
  );
}

async function handleBroadcast(chatId: number | string, payload: string) {
  if (!payload) {
    await sendMessage(chatId, "Usage: /broadcast <title> | <body>");
    return;
  }
  let title = "Bit Sheel?";
  let body = payload;
  if (payload.includes("|")) {
    const [t, ...rest] = payload.split("|");
    title = t.trim() || title;
    body = rest.join("|").trim();
  }
  if (!body) {
    await sendMessage(chatId, "Broadcast body is empty.");
    return;
  }
  await sendMessage(chatId, `Broadcasting…\n<b>${title}</b>\n${body}`);
  try {
    const { sent, failed, stale } = await broadcastToAll(title, body);
    await sendMessage(
      chatId,
      `Done. sent=${sent} failed=${failed} stale=${stale}`,
    );
  } catch (e) {
    await sendMessage(chatId, `Broadcast failed: ${(e as Error).message}`);
  }
}

// ---------- Wave 2 command handlers ----------

function escapeHtml(s: string | null | undefined): string {
  return (s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function stripHandle(input: string): string {
  return input.replace(/^@/, "").trim();
}

async function profileByHandle(handle: string) {
  const clean = stripHandle(handle);
  if (!clean) return null;
  const { data } = await supabase
    .from("profiles")
    .select("id, username, display_name, xp, level, quests_completed, account_status, created_at")
    .ilike("username", clean)
    .maybeSingle();
  return data;
}

async function handlePending(chatId: number | string) {
  const [subs, appeals, reports] = await Promise.all([
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .eq("status", "pending").eq("appealed", false),
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .eq("status", "pending").eq("appealed", true),
    supabase.from("reports").select("id", { count: "exact", head: true })
      .eq("status", "pending"),
  ]);
  const lines = [
    "<b>📋 PENDING QUEUE</b>",
    "",
    `• Submissions: <b>${subs.count ?? 0}</b>`,
    `• Appeals:     <b>${appeals.count ?? 0}</b>`,
    `• Reports:     <b>${reports.count ?? 0}</b>`,
  ];
  await sendMessage(chatId, lines.join("\n"));
}

async function handleStats(chatId: number | string, arg: string) {
  const isWeek = arg.trim().toLowerCase() === "week";
  const sinceMs = Date.now() - (isWeek ? 7 : 1) * 86_400_000;
  const since = new Date(sinceMs).toISOString();

  const [subs, approved, rejected, signups, activeRows] = await Promise.all([
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .gte("created_at", since),
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .eq("status", "approved").gte("reviewed_at", since),
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .eq("status", "rejected").gte("reviewed_at", since),
    supabase.from("profiles").select("id", { count: "exact", head: true })
      .gte("created_at", since),
    // No last_seen_at column — use distinct submitters in window as a
    // proxy for "active users".
    supabase.from("submissions").select("user_id").gte("created_at", since),
  ]);
  const distinctActive = new Set(
    ((activeRows.data ?? []) as any[]).map((r) => r.user_id).filter(Boolean),
  ).size;

  const label = isWeek ? "LAST 7 DAYS" : "TODAY";
  await sendMessage(chatId, [
    `<b>📊 STATS · ${label}</b>`,
    "",
    `• Submissions: <b>${subs.count ?? 0}</b>`,
    `• Approved:    <b>${approved.count ?? 0}</b>`,
    `• Rejected:    <b>${rejected.count ?? 0}</b>`,
    `• Signups:     <b>${signups.count ?? 0}</b>`,
    `• Submitters:  <b>${distinctActive}</b>`,
  ].join("\n"));
}

async function handleUser(chatId: number | string, arg: string) {
  if (!arg) {
    await sendMessage(chatId, "Usage: /user @handle");
    return;
  }
  const p = await profileByHandle(arg);
  if (!p) {
    await sendMessage(chatId, `No user found for ${escapeHtml(arg)}`);
    return;
  }
  const [pending, lastSub] = await Promise.all([
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .eq("user_id", p.id).eq("status", "pending"),
    supabase.from("submissions").select("created_at")
      .eq("user_id", p.id).order("created_at", { ascending: false }).limit(1)
      .maybeSingle(),
  ]);
  const lastActive = (lastSub.data as any)?.created_at;
  await sendMessage(chatId, [
    `<b>👤 ${escapeHtml(p.display_name || p.username || "(unnamed)")}</b>`,
    "",
    `• Handle:    @${escapeHtml(p.username ?? "")}`,
    `• Status:    ${escapeHtml(p.account_status ?? "active")}`,
    `• XP:        <b>${p.xp ?? 0}</b>`,
    `• Level:     <b>${p.level ?? 1}</b>`,
    `• Done:      ${p.quests_completed ?? 0} quests`,
    `• Pending:   ${pending.count ?? 0} submissions`,
    `• Joined:    ${p.created_at ? new Date(p.created_at).toISOString().slice(0, 10) : "?"}`,
    `• Last sub:  ${lastActive ? new Date(lastActive).toISOString().slice(0, 16).replace("T", " ") : "never"}`,
    "",
    `<code>${escapeHtml(p.id)}</code>`,
  ].join("\n"));
}

async function handleBan(chatId: number | string, arg: string, ban: boolean) {
  if (!arg) {
    await sendMessage(chatId, `Usage: /${ban ? "ban" : "unban"} @handle`);
    return;
  }
  const p = await profileByHandle(arg);
  if (!p) {
    await sendMessage(chatId, `No user found for ${escapeHtml(arg)}`);
    return;
  }
  const newStatus = ban ? "banned" : "active";
  const { error } = await supabase.rpc("set_user_account_status", {
    p_user_id: p.id,
    p_status: newStatus,
  });
  if (error) {
    await sendMessage(chatId, `Failed: ${escapeHtml(error.message)}`);
    return;
  }
  await sendMessage(
    chatId,
    `${ban ? "🚫 Banned" : "✅ Restored"} <b>@${escapeHtml(p.username ?? "")}</b>`,
  );
}

async function handleQuest(chatId: number | string, arg: string) {
  const sub = arg.trim().toLowerCase();
  if (sub === "spotlight") {
    await handleQuestSpotlight(chatId);
    return;
  }
  if (sub === "add") {
    await startQuestAdd(chatId);
    return;
  }
  await sendMessage(chatId, "Usage: /quest spotlight | /quest add");
}

async function handleQuestSpotlight(chatId: number | string) {
  // Pick a random active quest as today's spotlight.
  const { data, error } = await supabase
    .from("quests")
    .select("id, title, description")
    .eq("is_active", true)
    .limit(50);
  if (error || !data?.length) {
    await sendMessage(chatId, "No active quests to spotlight.");
    return;
  }
  const quest = data[Math.floor(Math.random() * data.length)];
  const title = `⭐ Today's Spotlight: ${quest.title}`;
  const body = (quest.description ?? "").slice(0, 200) ||
    "Tap in and take it on.";
  await sendMessage(chatId, `Pushing spotlight…\n<b>${escapeHtml(quest.title)}</b>`);
  try {
    const r = await broadcastToAll(title, body);
    await sendMessage(
      chatId,
      `Done. sent=${r.sent} failed=${r.failed} stale=${r.stale}`,
    );
  } catch (e) {
    await sendMessage(chatId, `Spotlight push failed: ${(e as Error).message}`);
  }
}

async function handleAudit(chatId: number | string, arg: string) {
  let query = supabase
    .from("admin_audit_log")
    .select("created_at, admin_id, action, target_id, details")
    .order("created_at", { ascending: false })
    .limit(10);

  let header = "<b>📜 AUDIT · last 10</b>";
  if (arg) {
    const p = await profileByHandle(arg);
    if (!p) {
      await sendMessage(chatId, `No admin found for ${escapeHtml(arg)}`);
      return;
    }
    query = query.eq("admin_id", p.id);
    header = `<b>📜 AUDIT · @${escapeHtml(p.username ?? "")}</b>`;
  }

  const { data, error } = await query;
  if (error) {
    await sendMessage(chatId, `Audit failed: ${escapeHtml(error.message)}`);
    return;
  }
  if (!data?.length) {
    await sendMessage(chatId, `${header}\n\n(no entries)`);
    return;
  }

  // Resolve admin handles in one round-trip.
  const adminIds = [...new Set(data.map((r: any) => r.admin_id).filter(Boolean))];
  const handles = new Map<string, string>();
  if (adminIds.length) {
    const { data: profs } = await supabase
      .from("profiles")
      .select("id, username, display_name")
      .in("id", adminIds);
    for (const p of profs ?? []) {
      handles.set(p.id, p.display_name || (p.username ? `@${p.username}` : p.id));
    }
  }

  const lines: string[] = [header, ""];
  for (const row of data as any[]) {
    const when = new Date(row.created_at).toISOString().replace("T", " ").slice(0, 16);
    const who = handles.get(row.admin_id) ?? row.admin_id ?? "(system)";
    lines.push(`• <code>${when}</code> ${escapeHtml(who)} → ${escapeHtml(row.action)}`);
  }
  await sendMessage(chatId, lines.join("\n"));
}

async function handleLeaderboard(chatId: number | string) {
  // Top 5 by approved submissions in the last 7 days. (`submissions.xp_awarded`
  // is a boolean idempotency flag, not an XP amount, so we count approvals.)
  const since = new Date(Date.now() - 7 * 86_400_000).toISOString();
  const { data: weekly } = await supabase
    .from("submissions")
    .select("user_id")
    .eq("status", "approved")
    .gte("reviewed_at", since);

  const totals = new Map<string, number>();
  for (const r of (weekly ?? []) as any[]) {
    if (!r.user_id) continue;
    totals.set(r.user_id, (totals.get(r.user_id) ?? 0) + 1);
  }

  const top = [...totals.entries()]
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5);

  if (!top.length) {
    await sendMessage(
      chatId,
      "<b>🏆 LEADERBOARD · this week</b>\n\n(no approvals yet)",
    );
    return;
  }

  const ids = top.map(([id]) => id);
  const { data: profs } = await supabase
    .from("profiles")
    .select("id, username, display_name")
    .in("id", ids);
  const nameById = new Map<string, string>();
  for (const p of profs ?? []) {
    nameById.set(p.id, p.display_name || (p.username ? `@${p.username}` : "(?)"));
  }

  const lines = [
    "<b>🏆 LEADERBOARD · this week</b>",
    "<i>(approved submissions)</i>",
    "",
  ];
  top.forEach(([id, n], i) => {
    const medal = ["🥇", "🥈", "🥉", "4.", "5."][i];
    lines.push(
      `${medal} ${escapeHtml(nameById.get(id) ?? id)} — <b>${n}</b>`,
    );
  });
  await sendMessage(chatId, lines.join("\n"));
}

// ---------- FSM: /quest add ----------
//
// Telegram is stateless, so per-chat state lives in the
// telegram_command_state table (see migration 0106). A row exists only
// while a multi-step command is mid-flight — completion or /cancel
// removes it.
//
// Steps (command = "quest_add"):
//   awaiting_title       → 3..100 chars
//   awaiting_description → 10..500 chars
//   awaiting_category    → fitness | creativity | social | learning | adventure
//   awaiting_difficulty  → easy | medium | hard
//   awaiting_xp          → integer 5..100
//   awaiting_confirm     → "yes" inserts; anything else asks again

type FsmRow = {
  chat_id: number;
  command: string;
  step: string;
  data: Record<string, unknown>;
};

async function getFsmState(chatId: number | string): Promise<FsmRow | null> {
  const { data } = await supabase
    .from("telegram_command_state")
    .select("chat_id, command, step, data")
    .eq("chat_id", chatId)
    .maybeSingle();
  return (data as FsmRow | null) ?? null;
}

async function setFsmState(
  chatId: number | string,
  command: string,
  step: string,
  data: Record<string, unknown>,
): Promise<void> {
  await supabase.from("telegram_command_state").upsert({
    chat_id: chatId,
    command,
    step,
    data,
    updated_at: new Date().toISOString(),
  });
}

async function clearFsmState(chatId: number | string): Promise<void> {
  await supabase.from("telegram_command_state").delete().eq("chat_id", chatId);
}

const QUEST_CATEGORIES = ["fitness", "creativity", "social", "learning", "adventure"];
const QUEST_DIFFICULTIES = ["easy", "medium", "hard"];

async function startQuestAdd(chatId: number | string): Promise<void> {
  await setFsmState(chatId, "quest_add", "awaiting_title", {});
  await sendMessage(
    chatId,
    [
      "<b>➕ NEW QUEST</b>",
      "",
      "Send the <b>title</b> (3–100 chars).",
      "Send /cancel at any time to abort.",
    ].join("\n"),
  );
}

/** Returns true iff the input was consumed by an in-flight FSM. */
async function routeFsmInput(
  chatId: number | string,
  text: string,
): Promise<boolean> {
  const state = await getFsmState(chatId);
  if (!state) return false;
  if (state.command !== "quest_add") {
    // Unknown command in state — clean it up so we don't get stuck.
    await clearFsmState(chatId);
    return false;
  }
  await stepQuestAdd(chatId, state, text);
  return true;
}

async function stepQuestAdd(
  chatId: number | string,
  state: FsmRow,
  input: string,
): Promise<void> {
  const data = { ...(state.data ?? {}) };

  switch (state.step) {
    case "awaiting_title": {
      if (input.length < 3 || input.length > 100) {
        await sendMessage(chatId, "Title must be 3–100 chars. Try again or /cancel.");
        return;
      }
      data.title = input;
      await setFsmState(chatId, "quest_add", "awaiting_description", data);
      await sendMessage(chatId, "Send the <b>description</b> (10–500 chars).");
      return;
    }
    case "awaiting_description": {
      if (input.length < 10 || input.length > 500) {
        await sendMessage(
          chatId,
          "Description must be 10–500 chars. Try again or /cancel.",
        );
        return;
      }
      data.description = input;
      await setFsmState(chatId, "quest_add", "awaiting_category", data);
      await sendMessage(
        chatId,
        `Pick a <b>category</b>: ${QUEST_CATEGORIES.join(" | ")}`,
      );
      return;
    }
    case "awaiting_category": {
      const cat = input.toLowerCase();
      if (!QUEST_CATEGORIES.includes(cat)) {
        await sendMessage(
          chatId,
          `Unknown category. Pick one of: ${QUEST_CATEGORIES.join(" | ")}`,
        );
        return;
      }
      data.category = cat;
      await setFsmState(chatId, "quest_add", "awaiting_difficulty", data);
      await sendMessage(
        chatId,
        `Pick a <b>difficulty</b>: ${QUEST_DIFFICULTIES.join(" | ")}`,
      );
      return;
    }
    case "awaiting_difficulty": {
      const d = input.toLowerCase();
      if (!QUEST_DIFFICULTIES.includes(d)) {
        await sendMessage(
          chatId,
          `Unknown difficulty. Pick one of: ${QUEST_DIFFICULTIES.join(" | ")}`,
        );
        return;
      }
      data.difficulty = d;
      await setFsmState(chatId, "quest_add", "awaiting_xp", data);
      await sendMessage(chatId, "Send the <b>XP reward</b> (5–100).");
      return;
    }
    case "awaiting_xp": {
      const xp = Number.parseInt(input, 10);
      if (!Number.isFinite(xp) || xp < 5 || xp > 100) {
        await sendMessage(chatId, "XP must be an integer 5–100. Try again or /cancel.");
        return;
      }
      data.xp_reward = xp;
      await setFsmState(chatId, "quest_add", "awaiting_confirm", data);
      await sendMessage(
        chatId,
        [
          "<b>Preview</b>",
          "",
          `<b>Title:</b> ${escapeHtml(String(data.title))}`,
          `<b>Description:</b> ${escapeHtml(String(data.description))}`,
          `<b>Category:</b> ${escapeHtml(String(data.category))}`,
          `<b>Difficulty:</b> ${escapeHtml(String(data.difficulty))}`,
          `<b>XP:</b> ${xp}`,
          "",
          "Reply <b>YES</b> to create, or /cancel to abort.",
        ].join("\n"),
      );
      return;
    }
    case "awaiting_confirm": {
      if (input.trim().toLowerCase() !== "yes") {
        await sendMessage(chatId, "Reply YES to create, or /cancel.");
        return;
      }
      const { data: inserted, error } = await supabase
        .from("quests")
        .insert({
          title: data.title,
          description: data.description,
          category: data.category,
          difficulty: data.difficulty,
          xp_reward: data.xp_reward,
          is_active: true,
        })
        .select("id")
        .single();
      await clearFsmState(chatId);
      if (error || !inserted) {
        await sendMessage(
          chatId,
          `❌ Insert failed: ${escapeHtml(error?.message ?? "unknown")}`,
        );
        return;
      }
      await sendMessage(
        chatId,
        `✅ Created.\n<code>${escapeHtml((inserted as any).id)}</code>`,
      );
      return;
    }
    default:
      // Unknown step — clear and tell the user.
      await clearFsmState(chatId);
      await sendMessage(chatId, "Lost track of the quest add flow — start over with /quest add.");
  }
}

// ---------- HTTP entry ----------

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("ok", { status: 200 });
  }
  // SEC-003: fail closed if the secret is unset (503 because that's a
  // server-misconfig, not a caller-auth issue) AND compare in constant
  // time so a remote attacker can't byte-step the secret via timing.
  // (PR #52 had a simpler `!==` compare — keeping constantTimeEqual.)
  if (!WEBHOOK_SECRET) {
    console.error("[telegram-webhook] TELEGRAM_WEBHOOK_SECRET not set");
    return new Response("not configured", { status: 503 });
  }
  const got = req.headers.get("x-telegram-bot-api-secret-token");
  if (!got || !constantTimeEqual(got, WEBHOOK_SECRET)) {
    return new Response("forbidden", { status: 403 });
  }
  let update: any;
  try {
    update = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }
  try {
    if (update.callback_query) {
      await handleCallback(update.callback_query);
    } else if (update.message) {
      await handleMessage(update.message);
    }
  } catch (e) {
    console.error("telegram-webhook error", e);
  }
  // Always 200 so Telegram doesn't retry.
  return new Response("ok", { status: 200 });
});
