#!/usr/bin/env bash
# ============================================================
# Wire up the Telegram moderation bot from scratch.
#
# WHY THIS EXISTS: at the 2026-07-14 self-host cutover, TELEGRAM_BOT_TOKEN,
# TELEGRAM_ADMIN_CHAT_ID and TELEGRAM_ALLOWED_CHAT_IDS were never carried
# over — they exist in .env as EMPTY strings. Only TELEGRAM_WEBHOOK_SECRET
# made it. Result: every Telegram call returned 404, and 165 of 329
# submissions never reached the moderation channel. Nothing alerted,
# because nothing watched.
#
# RUN THIS ON THE SERVER (the token never touches a chat log):
#   ssh contabo
#   bash /root/setup-telegram.sh <BOT_TOKEN>
#
# BEFORE RUNNING, in Telegram:
#   1. @BotFather -> /newbot -> copy the token
#   2. Create a PRIVATE group for moderation
#   3. Add your bot to it, then promote it to ADMIN
#      (a non-admin bot cannot read group messages or post reliably)
#   4. Send any message in that group, e.g. "hello"  <- REQUIRED, this is
#      how the script discovers the chat id
#
# What it does: validates the token, auto-discovers the chat id, mints a
# fresh webhook secret, updates .env (with a timestamped backup), restarts
# the functions runtime, registers the webhook, and sends a test message.
# Safe to re-run.
# ============================================================
set -uo pipefail

STACK=/root/supabase-docker
ENVF="$STACK/.env"
TOKEN="${1:-}"

red()  { printf '\033[0;31m%s\033[0m\n' "$*"; }
grn()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
ylw()  { printf '\033[1;33m%s\033[0m\n' "$*"; }

[ -z "$TOKEN" ] && { red "Usage: bash setup-telegram.sh <BOT_TOKEN>"; exit 1; }
[ -f "$ENVF" ]  || { red "No $ENVF — are you on the right box?"; exit 1; }

# ── 1. Validate the token before touching anything ──────────────────
echo "==> Validating bot token"
ME=$(curl -s --max-time 15 "https://api.telegram.org/bot${TOKEN}/getMe")
if ! printf '%s' "$ME" | grep -q '"ok":true'; then
  red "Token rejected by Telegram:"; printf '  %s\n' "$ME"
  red "Get a valid token from @BotFather (/mybots -> API Token)."
  exit 1
fi
BOT_USERNAME=$(printf '%s' "$ME" | grep -oE '"username":"[^"]+"' | cut -d'"' -f4)
grn "    OK — bot is @${BOT_USERNAME}"

# ── 2. Discover the chat id from recent messages ────────────────────
echo "==> Discovering chat id (needs a message in the group)"
UPD=$(curl -s --max-time 15 "https://api.telegram.org/bot${TOKEN}/getUpdates")
CHAT_IDS=$(printf '%s' "$UPD" | grep -oE '"chat":\{"id":-?[0-9]+' | grep -oE '\-?[0-9]+$' | sort -u)

if [ -z "$CHAT_IDS" ]; then
  red "    No chats found."
  ylw "    Send a message in the moderation group, then re-run."
  ylw "    Note: if the bot has Group Privacy ON it cannot see normal group"
  ylw "    messages — @BotFather -> /setprivacy -> Disable, then try again."
  exit 1
fi

COUNT=$(printf '%s\n' "$CHAT_IDS" | wc -l)
if [ "$COUNT" -gt 1 ]; then
  ylw "    Multiple chats seen:"; printf '      %s\n' $CHAT_IDS
  ylw "    Using the first negative (group) id if present, else the first."
fi
# Groups/supergroups have negative ids; prefer those over 1:1 DMs.
CHAT_ID=$(printf '%s\n' $CHAT_IDS | grep -m1 '^-' || printf '%s\n' $CHAT_IDS | head -1)
grn "    Using chat id: $CHAT_ID"

# ── 3. Fresh webhook secret ─────────────────────────────────────────
SECRET=$(openssl rand -hex 32)
echo "==> Minted a new webhook secret (64 hex chars)"

# ── 4. Update .env, with a backup and an integrity check ────────────
BAK="$ENVF.bak.$(date +%Y%m%d_%H%M%S)"
cp -a "$ENVF" "$BAK"
BEFORE=$(wc -l < "$ENVF")

set_kv() {  # replace in place if the key exists, else append
  local k="$1" v="$2"
  if grep -qE "^${k}=" "$ENVF"; then
    awk -v k="$k" -v v="$v" 'BEGIN{FS=OFS="="} $1==k {print k "=" v; next} {print}' "$ENVF" > "$ENVF.tmp" \
      && mv "$ENVF.tmp" "$ENVF"
  else
    printf '%s=%s\n' "$k" "$v" >> "$ENVF"
  fi
}

set_kv TELEGRAM_BOT_TOKEN        "$TOKEN"
set_kv TELEGRAM_WEBHOOK_SECRET   "$SECRET"
set_kv TELEGRAM_ADMIN_CHAT_ID    "$CHAT_ID"
set_kv TELEGRAM_ALLOWED_CHAT_IDS "$CHAT_ID"

AFTER=$(wc -l < "$ENVF")
echo "==> .env updated (backup: $BAK)"
echo "    lines before=$BEFORE after=$AFTER"
if [ "$AFTER" -lt "$BEFORE" ]; then
  red "    LINE COUNT DROPPED — restoring backup and aborting."
  cp -a "$BAK" "$ENVF"; exit 1
fi

# ── 5. Restart the functions runtime to pick up the new env ─────────
# force-recreate, not restart: a plain restart keeps the stale environment.
echo "==> Recreating the edge-functions container"
( cd "$STACK" && docker compose up -d --force-recreate functions >/dev/null 2>&1 )
sleep 8
STATE=$(docker inspect -f '{{.State.Status}}' supabase-edge-functions 2>/dev/null)
echo "    container: $STATE"
[ "$STATE" != "running" ] && { red "    functions container is not running — check: docker logs supabase-edge-functions"; exit 1; }

# ── 6. Register the webhook ─────────────────────────────────────────
echo "==> Registering webhook"
WH=$(curl -s --max-time 20 "https://api.telegram.org/bot${TOKEN}/setWebhook" \
      -d url="https://api.bsheel.app/functions/v1/telegram-webhook" \
      -d secret_token="$SECRET" \
      -d 'allowed_updates=["message","callback_query"]')
printf '%s' "$WH" | grep -q '"ok":true' && grn "    webhook registered" || { red "    setWebhook failed:"; printf '  %s\n' "$WH"; }

# ── 7. Verify + smoke test ──────────────────────────────────────────
echo "==> Webhook status"
curl -s --max-time 15 "https://api.telegram.org/bot${TOKEN}/getWebhookInfo" \
 | tr ',' '\n' | grep -E '"url"|pending_update_count|last_error_message' | sed 's/^/    /'

echo "==> Sending test message"
TEST=$(curl -s --max-time 15 -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
  -d "chat_id=${CHAT_ID}" \
  --data-urlencode "text=✅ BSHEEL moderation bot reconnected $(date -u '+%F %T')Z — submissions and healthcheck alerts will arrive here.")
printf '%s' "$TEST" | grep -q '"ok":true' \
  && grn "    test message delivered — check the group" \
  || { red "    sendMessage failed:"; printf '  %s\n' "$TEST"; }

echo
grn "Done. The healthcheck (*/15) will now deliver alerts to this chat too."
ylw "If you ever rotate the bot token, re-run this script — it re-registers"
ylw "the webhook with a fresh secret."
