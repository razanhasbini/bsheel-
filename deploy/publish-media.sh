#!/usr/bin/env bash
# Publishes the MinIO object store behind TLS so presigned URLs work from a
# phone. Runs ON THE SERVER as root.
#
# The hostname is an sslip.io name that already resolves to this box, so no DNS
# record is needed to get media working today. Point MEDIA_HOST at
# media.bsheel.app once that A record exists.
set -uo pipefail
cd "$(dirname "$0")"

MEDIA_HOST="${MEDIA_HOST:-media.169-58-16-247.sslip.io}"
UPSTREAM="${UPSTREAM:-bsheel-minio:9000}"
CADDYFILE="${CADDYFILE:-/root/supabase-docker/volumes/proxy/caddy/Caddyfile}"
CADDY_CONTAINER="${CADDY_CONTAINER:-supabase-caddy}"
CADDY_CONFIG="${CADDY_CONFIG:-/etc/caddy/Caddyfile}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="${CADDYFILE}.bak.${STAMP}"

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\033[31merror: %s\033[0m\n" "$1" >&2; exit 1; }
caddy_in() { docker exec "$CADDY_CONTAINER" caddy "$@"; }

[ -f "$CADDYFILE" ] || fail "$CADDYFILE not found"
docker inspect "$CADDY_CONTAINER" >/dev/null 2>&1 || fail "no $CADDY_CONTAINER container"

if grep -q "^${MEDIA_HOST} {" "$CADDYFILE"; then
  echo "  ${MEDIA_HOST} block already present — nothing to do"
  exit 0
fi

step "Baseline"
declare -A BASE
for u in "https://api.bsheel.app/auth/v1/health" "https://api.bsheel.app/api/v1/health/live" \
         "https://admin.bsheel.app/" "https://admin.bsheel.app/v2/"; do
  BASE[$u]=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$u" 2>/dev/null)
  echo "  $u -> ${BASE[$u]}"
done

step "Backup"
cp -p "$CADDYFILE" "$BACKUP" || fail "could not write $BACKUP"
echo "  $BACKUP"

restore() {
  printf "\n\033[33mrolling back to %s\033[0m\n" "$BACKUP"
  cp -p "$BACKUP" "$CADDYFILE"
  caddy_in reload --config "$CADDY_CONFIG" 2>&1 | tail -2 || true
}

step "Append the media site block"
cat >> "$CADDYFILE" <<EOF

# ---- Bsheel object storage (added by deploy/publish-media.sh) ----
${MEDIA_HOST} {
	# Media is private and delivered through presigned URLs. The SigV4
	# signature covers the Host header, so it MUST arrive at MinIO unchanged
	# or every signature fails to verify. Caddy v2 passes the incoming Host
	# through by default; set explicitly so a later edit cannot break signing.
	reverse_proxy ${UPSTREAM} {
		header_up Host {host}
	}

	# Submissions are capped at 50MB by MEDIA_MAX_SUBMISSION_BYTES.
	request_body {
		max_size 60MB
	}
}
EOF
echo "  appended ${MEDIA_HOST} -> ${UPSTREAM}"

step "Validate"
caddy_in validate --config "$CADDY_CONFIG" >/dev/null 2>&1 \
  || { caddy_in validate --config "$CADDY_CONFIG" 2>&1 | tail -6; restore; fail "invalid config — restored"; }
echo "  valid"

step "Reload"
caddy_in reload --config "$CADDY_CONFIG" >/dev/null 2>&1 || { restore; fail "reload failed — restored"; }
echo "  reloaded"

step "Verify — existing hosts first, then the media host"
sleep 3
BROKE=0
for u in "${!BASE[@]}"; do
  now=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$u" 2>/dev/null)
  if [ "$now" = "${BASE[$u]}" ]; then printf "  \033[32mOK\033[0m    %s -> %s (unchanged)\n" "$u" "$now"
  else printf "  \033[31mBROKE\033[0m %s -> %s, was %s\n" "$u" "$now" "${BASE[$u]}"; BROKE=1; fi
done
[ "$BROKE" -eq 0 ] || { restore; fail "an existing host changed — rolled back"; }

# Caddy provisions the certificate on first request, which can take a few
# seconds. Poll rather than declaring failure on the first attempt.
for attempt in $(seq 1 12); do
  code=$(curl -s -o /dev/null -m 15 -w '%{http_code}' "https://${MEDIA_HOST}/minio/health/live" 2>/dev/null)
  [ "$code" = "200" ] && break
  sleep 5
done
if [ "$code" = "200" ]; then
  printf "  \033[32mOK\033[0m    https://%s/minio/health/live -> 200\n" "$MEDIA_HOST"
else
  printf "  \033[31mFAIL\033[0m  https://%s/minio/health/live -> %s\n" "$MEDIA_HOST" "$code"
  restore; fail "media host not serving — rolled back"
fi

printf "\n\033[32mObject storage published at https://%s\033[0m\n" "$MEDIA_HOST"
printf "Backup kept at %s\n" "$BACKUP"
