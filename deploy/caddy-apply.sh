#!/usr/bin/env bash
# Add the Bsheel routes to Caddy, safely. Runs ON THE SERVER.
#
# A bad Caddy reload takes the LIVE quest-app offline, so this script is built
# to fail backwards:
#
#   backup -> edit -> validate -> reload -> verify -> (rollback if anything broke)
#
# It edits only the api.bsheel.app site block, and REFUSES rather than guesses
# when the block's shape is ambiguous.
set -uo pipefail
cd "$(dirname "$0")"

# Host path of the file, and the container that actually runs Caddy. On this
# host Caddy is a container (supabase-caddy) with /etc/caddy bind-mounted, so
# validate and reload must run *inside* it -- there is no caddy binary on the
# host, and its 127.0.0.1 is not the host's.
CADDYFILE="${CADDYFILE:-/root/supabase-docker/volumes/proxy/caddy/Caddyfile}"
CADDY_CONTAINER="${CADDY_CONTAINER:-supabase-caddy}"
CADDY_CONFIG_IN_CONTAINER="${CADDY_CONFIG_IN_CONTAINER:-/etc/caddy/Caddyfile}"
API_UPSTREAM="${API_UPSTREAM:-bsheel-api:3000}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${CADDYFILE}.bak.${STAMP}"

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\033[31merror: %s\033[0m\n" "$1" >&2; exit 1; }

[ -f "$CADDYFILE" ] || fail "$CADDYFILE not found — set CADDYFILE=/path/to/Caddyfile"
docker inspect "$CADDY_CONTAINER" >/dev/null 2>&1 \
  || fail "container $CADDY_CONTAINER not found — set CADDY_CONTAINER"

caddy_in_container() { docker exec "$CADDY_CONTAINER" caddy "$@"; }

step "Backup"
cp -p "$CADDYFILE" "$BACKUP" || fail "could not write $BACKUP"
echo "$BACKUP"

restore() {
  printf "\n\033[33mrolling back to %s\033[0m\n" "$BACKUP"
  cp -p "$BACKUP" "$CADDYFILE"
  caddy_in_container reload --config "$CADDY_CONFIG_IN_CONTAINER" 2>&1 | tail -3 || true
}

step "Record the live baseline (before touching anything)"
declare -A BASE
for p in /auth/v1/health /rest/v1/ /storage/v1/version /functions/v1/; do
  BASE[$p]=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://api.bsheel.app$p" 2>/dev/null)
  echo "  $p -> ${BASE[$p]}"
  [ "${BASE[$p]}" = "000" ] && fail "quest-app endpoint $p is already unreachable — fix that first"
done

step "Edit the api.bsheel.app block"
API_UPSTREAM="$API_UPSTREAM" python3 caddy_insert.py "$CADDYFILE" || { restore; fail "edit refused or failed"; }

step "Validate"
if ! caddy_in_container validate --config "$CADDY_CONFIG_IN_CONTAINER" 2>&1 | tail -5; then
  restore; fail "caddy validate failed — config restored, quest-app untouched"
fi
echo "config is valid"

step "Reload (zero downtime)"
if ! caddy_in_container reload --config "$CADDY_CONFIG_IN_CONTAINER" 2>&1 | tail -5; then
  restore; fail "caddy reload failed — config restored"
fi

step "Verify — quest-app first, then Bsheel"
sleep 2
BROKE=0
for p in /auth/v1/health /rest/v1/ /storage/v1/version /functions/v1/; do
  now=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "https://api.bsheel.app$p" 2>/dev/null)
  if [ "$now" = "${BASE[$p]}" ]; then
    printf "  \033[32mOK\033[0m    %s -> %s (unchanged)\n" "$p" "$now"
  else
    printf "  \033[31mBROKE\033[0m %s -> %s, was %s\n" "$p" "$now" "${BASE[$p]}"; BROKE=1
  fi
done
[ "$BROKE" -eq 0 ] || { restore; fail "the live quest-app stack changed behaviour — rolled back"; }

code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' https://api.bsheel.app/api/v1/health/ready 2>/dev/null)
body=$(curl -s -m 15 https://api.bsheel.app/api/v1/health/ready 2>/dev/null | head -c 200)
if [ "$code" = 200 ] && printf '%s' "$body" | grep -q '"postgres":"up"'; then
  printf "  \033[32mOK\033[0m    /api/v1/health/ready -> %s\n" "$body"
else
  printf "  \033[31mFAIL\033[0m  /api/v1/health/ready -> %s  body: %s\n" "$code" "$body"
  restore; fail "Bsheel is not answering through Caddy — rolled back"
fi

printf "\n\033[32mDone.\033[0m Backup kept at %s\n" "$BACKUP"
printf "Run deploy/verify.sh from your Mac for the full check.\n"
