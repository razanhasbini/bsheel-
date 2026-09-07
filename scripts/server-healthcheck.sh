#!/usr/bin/env bash
# ============================================================
# BSHEEL server healthcheck.
#
# Runs ON the Contabo box from root's crontab. Detects the class of
# silent failure that went unnoticed for months because nothing watched
# anything:
#
#   * expire-overdue-quests failed 2016x/week -> 14 users soft-locked
#     from 2026-05-04 and unable to roll any new quest
#   * send_pending_review_reminders failed 168x/week -> never ran once
#   * TELEGRAM_BOT_TOKEN empty since the self-host cutover -> 165
#     submissions never reached the moderation channel
#   * SMTP never configured -> 5 password-reset attempts, 0 emails sent
#
# Every one of those was visible in data the whole time. Nobody looked.
#
# Install:
#   scp scripts/server-healthcheck.sh contabo:/root/monitoring/healthcheck.sh
#   chmod +x /root/monitoring/healthcheck.sh
#   crontab -e   ->   */15 * * * * /root/monitoring/healthcheck.sh >/dev/null 2>&1
#
# Alerting: Telegram if TELEGRAM_BOT_TOKEN + TELEGRAM_ADMIN_CHAT_ID are
# set in the stack .env; otherwise findings are written to STATE_DIR only.
# Alerts are DEDUPED — a given problem notifies once, then stays quiet
# until it clears and recurs. A monitor that pages every 15 minutes gets
# muted, and a muted monitor is worse than none.
# ============================================================
set -uo pipefail

STACK=/root/supabase-docker
STATE_DIR=/root/monitoring
STATE_FILE="$STATE_DIR/last_alert_state"
LOG="$STATE_DIR/healthcheck.log"
mkdir -p "$STATE_DIR"

PROBLEMS=()
add() { PROBLEMS+=("$1"); }
DB() { docker exec -i supabase-db psql -U supabase_admin -d postgres -tAc "$1" 2>/dev/null; }

# ── 1. Failing cron jobs in the last hour ───────────────────────────
# The single highest-value check: this alone would have caught the two
# broken jobs on day one instead of month three.
FAILED=$(DB "
  SELECT string_agg(DISTINCT j.jobname, ', ')
  FROM cron.job_run_details d JOIN cron.job j USING (jobid)
  WHERE d.status = 'failed' AND d.start_time > now() - interval '1 hour';")
[ -n "$FAILED" ] && add "CRON FAILING: $FAILED"

# ── 2. Backups: fresh locally AND present off-site ──────────────────
# Both halves matter. A local-only backup dies with the disk it is on;
# an off-site copy that stopped uploading is not a backup either.
NEWEST=$(find /root/backups/db -name 'bsheel_*.dump' -mmin -1560 2>/dev/null | wc -l)
[ "$NEWEST" -eq 0 ] && add "BACKUP STALE: no local dump in the last 26h"

if command -v rclone >/dev/null 2>&1 && rclone listremotes 2>/dev/null | grep -q '^r2backup:'; then
  R2_RECENT=$(rclone lsjson r2backup:bsheel-db-backups 2>/dev/null \
    | grep -c "$(date -u +%Y%m%d)" )
  [ "${R2_RECENT:-0}" -eq 0 ] && add "BACKUP OFFSITE: nothing uploaded to R2 today"
else
  add "BACKUP OFFSITE: rclone remote 'r2backup' missing — backups are local-only"
fi

# ── 3. Containers not running ───────────────────────────────────────
for c in supabase-db supabase-auth supabase-rest supabase-kong \
         supabase-edge-functions supabase-caddy supabase-storage; do
  st=$(docker inspect -f '{{.State.Status}}' "$c" 2>/dev/null || echo missing)
  [ "$st" != "running" ] && add "CONTAINER $c is '$st'"
done

# ── 4. Disk ─────────────────────────────────────────────────────────
USE=$(df --output=pcent / | tail -1 | tr -dc '0-9')
[ "${USE:-0}" -ge 85 ] && add "DISK at ${USE}%"

# ── 5. TLS expiry (Caddy auto-renews; alert only if renewal stalls) ──
END=$(echo | openssl s_client -servername api.bsheel.app \
        -connect api.bsheel.app:443 2>/dev/null \
      | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
if [ -n "$END" ]; then
  DAYS=$(( ( $(date -d "$END" +%s) - $(date +%s) ) / 86400 ))
  [ "$DAYS" -lt 14 ] && add "TLS cert expires in ${DAYS}d"
fi

# ── 6. Moderation queue actually being worked ───────────────────────
STALE=$(DB "SELECT count(*) FROM public.submissions
            WHERE status='pending' AND submitted_at < now() - interval '48 hours';")
[ "${STALE:-0}" -gt 0 ] && add "MODERATION: $STALE submissions pending >48h"

# ── 7. GDPR deletion queue (30-day legal clock) ─────────────────────
STUCK=$(DB "SELECT count(*) FROM public.account_delete_requests
            WHERE processed_at IS NULL AND requested_at < now() - interval '24 hours';")
[ "${STUCK:-0}" -gt 0 ] && add "GDPR: $STUCK deletion requests unprocessed >24h"

# ── 8. Regression detector for the 0150 bug ─────────────────────────
# If expire_overdue_quests silently breaks again, this catches it by its
# effect rather than its logs — users stuck holding a dead quest.
OVERDUE=$(DB "SELECT count(*) FROM public.user_quests
              WHERE status='assigned' AND expires_at < now() - interval '1 hour';")
[ "${OVERDUE:-0}" -gt 0 ] && add "QUESTS: $OVERDUE past expiry but still 'assigned' (expiry job regressed?)"

# ── 9. Self-check: can this monitor actually reach anyone? ───────────
BOT=$(grep -E '^TELEGRAM_BOT_TOKEN=' "$STACK/.env" 2>/dev/null | cut -d= -f2-)
CHAT=$(grep -E '^TELEGRAM_ADMIN_CHAT_ID=' "$STACK/.env" 2>/dev/null | cut -d= -f2-)
[ -z "$BOT" ] && add "ALERTING: TELEGRAM_BOT_TOKEN empty — moderation pushes AND these alerts go nowhere"

# ── Report ──────────────────────────────────────────────────────────
TS=$(date '+%F %T')
if [ ${#PROBLEMS[@]} -eq 0 ]; then
  echo "[$TS] OK" >> "$LOG"
  [ -f "$STATE_FILE" ] && rm -f "$STATE_FILE"   # clears -> next issue re-alerts
  exit 0
fi

BODY=$(printf '%s\n' "${PROBLEMS[@]}")
echo "[$TS] PROBLEMS:" >> "$LOG"
printf '  %s\n' "${PROBLEMS[@]}" >> "$LOG"

# Dedupe: only notify when the set of problems changes.
HASH=$(printf '%s' "$BODY" | sha256sum | cut -c1-32)
[ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE")" = "$HASH" ] && exit 0
printf '%s' "$HASH" > "$STATE_FILE"

if [ -n "$BOT" ] && [ -n "$CHAT" ]; then
  curl -s --max-time 15 -X POST \
    "https://api.telegram.org/bot${BOT}/sendMessage" \
    -d "chat_id=${CHAT}" \
    --data-urlencode "text=🚨 BSHEEL healthcheck ${TS}
${BODY}" >/dev/null 2>&1 \
    && echo "[$TS] alert sent" >> "$LOG" \
    || echo "[$TS] ALERT DELIVERY FAILED" >> "$LOG"
else
  echo "[$TS] no alert channel configured — see $LOG" >> "$LOG"
fi
exit 1
