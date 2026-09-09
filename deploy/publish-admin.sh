#!/usr/bin/env bash
# Publishes the Bsheel admin dashboard at admin.bsheel.app/v2/. Runs ON THE
# SERVER as root.
#
# Same discipline as caddy-apply.sh: record what the live host serves, back the
# config up, edit, validate inside the Caddy container, reload, verify, and roll
# back if the legacy admin or the Supabase routes change behaviour.
set -uo pipefail
cd "$(dirname "$0")"

STAGED="${STAGED:-/home/tayseer/bsheel-api/admin-v2}"
DOC_ROOT_HOST="${DOC_ROOT_HOST:-/root/supabase-docker/volumes/admin}"
CADDYFILE="${CADDYFILE:-/root/supabase-docker/volumes/proxy/caddy/Caddyfile}"
CADDY_CONTAINER="${CADDY_CONTAINER:-supabase-caddy}"
CADDY_CONFIG="${CADDY_CONFIG:-/etc/caddy/Caddyfile}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${CADDYFILE}.bak.${STAMP}"

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\033[31merror: %s\033[0m\n" "$1" >&2; exit 1; }
caddy_in() { docker exec "$CADDY_CONTAINER" caddy "$@"; }

[ -d "$STAGED" ] || fail "$STAGED not found — upload the bundle first"
[ -f "$STAGED/index.html" ] || fail "$STAGED/index.html missing — not a Flutter web build"
[ -d "$DOC_ROOT_HOST" ] || fail "$DOC_ROOT_HOST not found"
docker inspect "$CADDY_CONTAINER" >/dev/null 2>&1 || fail "container $CADDY_CONTAINER not found"

step "Baseline: what the live host serves today"
declare -A BASE
for u in "https://admin.bsheel.app/" "https://admin.bsheel.app/.well-known/assetlinks.json" \
         "https://api.bsheel.app/auth/v1/health" "https://api.bsheel.app/api/v1/health/live"; do
  BASE[$u]=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$u" 2>/dev/null)
  echo "  $u -> ${BASE[$u]}"
done

step "Copy the bundle into Caddy's document root"
mkdir -p "$DOC_ROOT_HOST/v2"
rsync -a --delete "$STAGED/" "$DOC_ROOT_HOST/v2/" || fail "copy failed"
echo "  $(find "$DOC_ROOT_HOST/v2" -type f | wc -l) files, $(du -sh "$DOC_ROOT_HOST/v2" | cut -f1)"

step "Backup the Caddyfile"
cp -p "$CADDYFILE" "$BACKUP" || fail "could not write $BACKUP"
echo "  $BACKUP"

restore() {
  printf "\n\033[33mrolling back to %s\033[0m\n" "$BACKUP"
  cp -p "$BACKUP" "$CADDYFILE"
  caddy_in reload --config "$CADDY_CONFIG" 2>&1 | tail -2 || true
}

step "Insert the /v2 route"
python3 caddy_insert_admin.py "$CADDYFILE" || { restore; fail "edit refused"; }

step "Validate"
caddy_in validate --config "$CADDY_CONFIG" >/dev/null 2>&1 \
  || { caddy_in validate --config "$CADDY_CONFIG" 2>&1 | tail -5; restore; fail "invalid config — restored"; }
echo "  config is valid"

step "Reload"
caddy_in reload --config "$CADDY_CONFIG" >/dev/null 2>&1 || { restore; fail "reload failed — restored"; }
echo "  reloaded"

step "Verify — legacy first, then the new panel"
sleep 2
BROKE=0
for u in "${!BASE[@]}"; do
  now=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$u" 2>/dev/null)
  if [ "$now" = "${BASE[$u]}" ]; then printf "  \033[32mOK\033[0m    %s -> %s (unchanged)\n" "$u" "$now"
  else printf "  \033[31mBROKE\033[0m %s -> %s, was %s\n" "$u" "$now" "${BASE[$u]}"; BROKE=1; fi
done
[ "$BROKE" -eq 0 ] || { restore; fail "the live host changed behaviour — rolled back"; }

for path in "/v2/" "/v2/login" "/v2/main.dart.js"; do
  code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' "https://admin.bsheel.app$path" 2>/dev/null)
  case "$code" in
    200) printf "  \033[32mOK\033[0m    %s -> 200\n" "$path" ;;
    *)   printf "  \033[31mFAIL\033[0m  %s -> %s\n" "$path" "$code"; BROKE=1 ;;
  esac
done
[ "$BROKE" -eq 0 ] || { restore; fail "the panel is not serving — rolled back"; }

printf "\n\033[32mAdmin dashboard published at https://admin.bsheel.app/v2/\033[0m\n"
printf "Backup kept at %s\n" "$BACKUP"
