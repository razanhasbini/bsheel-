// Posts a "yesterday at a glance" admin summary to Telegram once a day.
// Triggered by pg_cron at 06:00 UTC (≈ 9 AM Beirut summer / 8 AM winter)
// via pg_net.http_post — see migration 0107.
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
const ADMIN_CHAT_ID = Deno.env.get("TELEGRAM_ADMIN_CHAT_ID") ?? "";
// SEC-030: same shared-secret pattern as telegram-webhook so an attacker
// can't trigger expensive aggregate queries unauthenticated.
const SUMMARY_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";

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

async function buildSummary(): Promise<string> {
  const since = new Date(Date.now() - 86_400_000).toISOString();

  const [subs, approved, rejected, signups, pendingSubs, pendingAppeals,
    pendingReports, activeRows] = await Promise.all([
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .gte("created_at", since),
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .eq("status", "approved").gte("reviewed_at", since),
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .eq("status", "rejected").gte("reviewed_at", since),
    supabase.from("profiles").select("id", { count: "exact", head: true })
      .gte("created_at", since),
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .eq("status", "pending").eq("appealed", false),
    supabase.from("submissions").select("id", { count: "exact", head: true })
      .eq("status", "pending").eq("appealed", true),
    supabase.from("reports").select("id", { count: "exact", head: true })
      .eq("status", "pending"),
    supabase.from("submissions").select("user_id").gte("created_at", since),
  ]);

  const distinctActive = new Set(
    ((activeRows.data ?? []) as any[]).map((r) => r.user_id).filter(Boolean),
  ).size;

  // Top 3 quests by approved submissions yesterday — useful "what's
  // resonating" signal.
  const { data: topRows } = await supabase
    .from("submissions")
    .select("user_quest_id")
    .eq("status", "approved")
    .gte("reviewed_at", since);
  const questCounts = new Map<string, number>();
  for (const r of (topRows ?? []) as any[]) {
    if (!r.user_quest_id) continue;
    questCounts.set(r.user_quest_id, (questCounts.get(r.user_quest_id) ?? 0) + 1);
  }
  let topLines: string[] = [];
  if (questCounts.size) {
    const topUserQuestIds = [...questCounts.entries()]
      .sort((a, b) => b[1] - a[1]).slice(0, 3).map(([id]) => id);
    const { data: uqs } = await supabase
      .from("user_quests")
      .select("id, quests:quest_id (title)")
      .in("id", topUserQuestIds);
    const titleByUq = new Map<string, string>();
    for (const u of (uqs ?? []) as any[]) {
      titleByUq.set(u.id, u.quests?.title ?? "(unknown)");
    }
    topLines = topUserQuestIds.map((uqid) => {
      const t = titleByUq.get(uqid) ?? "(unknown)";
      const n = questCounts.get(uqid) ?? 0;
      return `   • ${esc(t)} — ${n}`;
    });
  }

  const lines: string[] = [
    "<b>☀️ DAILY SUMMARY</b>",
    "<i>last 24h</i>",
    "",
    "<b>Activity</b>",
    `• Submissions:  <b>${subs.count ?? 0}</b>`,
    `• Approved:     <b>${approved.count ?? 0}</b>`,
    `• Rejected:     <b>${rejected.count ?? 0}</b>`,
    `• Signups:      <b>${signups.count ?? 0}</b>`,
    `• Submitters:   <b>${distinctActive}</b>`,
    "",
    "<b>Queue</b>",
    `• Pending subs:    ${pendingSubs.count ?? 0}`,
    `• Pending appeals: ${pendingAppeals.count ?? 0}`,
    `• Pending reports: ${pendingReports.count ?? 0}`,
  ];
  if (topLines.length) {
    lines.push("", "<b>Top quests</b>", ...topLines);
  }
  return lines.join("\n");
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });

  // SEC-030: require the shared secret. Fail-closed if unset so a
  // misconfigured deploy never accepts unauthenticated triggers.
  if (!SUMMARY_SECRET) {
    console.error("[telegram-daily-summary] TELEGRAM_WEBHOOK_SECRET not set");
    return new Response("not configured", { status: 503 });
  }
  const got = req.headers.get("x-webhook-secret")
    ?? req.headers.get("x-telegram-bot-api-secret-token");
  if (got !== SUMMARY_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  if (!ADMIN_CHAT_ID) {
    return new Response("missing admin chat id", { status: 500 });
  }

  try {
    const text = await buildSummary();
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
      console.error("daily-summary send failed", res.status, await res.text());
      return new Response("send failed", { status: 500 });
    }
    return new Response("ok", { status: 200 });
  } catch (e) {
    console.error("telegram-daily-summary", e);
    return new Response("error", { status: 500 });
  }
});
