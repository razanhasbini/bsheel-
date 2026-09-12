#!/usr/bin/env bash
# Post-deploy verification. Runs from anywhere (it uses public URLs).
#
# Two jobs, and the second matters as much as the first:
#   1. prove the Bsheel API is actually live behind /api/v1
#   2. prove the LIVE quest-app Supabase stack is still intact
#
# A deploy that brings Bsheel up and takes quest-app down is a failed deploy.
set -uo pipefail

HOST="${1:-https://api.bsheel.app}"
PASS=0; FAIL=0
ok()  { printf "  \033[32mPASS\033[0m %s\n" "$1"; PASS=$((PASS+1)); }
bad() { printf "  \033[31mFAIL\033[0m %s\n" "$1"; FAIL=$((FAIL+1)); }
hdr() { printf "\n\033[1m== %s\033[0m\n" "$1"; }

# curl already prints 000 when it cannot connect, and also exits non-zero.
# `|| echo 000` on top of that produced "000000" and broke the case match.
get() {
  local c
  c=$(curl -s -m 15 -o /tmp/vf.$$ -w '%{http_code}' "$1" 2>/dev/null)
  printf '%s' "${c:-000}"
}

hdr "Bsheel API behind $HOST/api/v1"

code=$(get "$HOST/api/v1/health/live"); body=$(head -c 200 /tmp/vf.$$ 2>/dev/null)
# The pre-deploy catch-all answered every path with the literal "Bsheel API".
# Seeing that string here means Caddy never routed to the container.
if [ "$code" = 200 ] && printf '%s' "$body" | grep -q '"success"'; then
  ok "health/live -> 200 JSON (NestJS is answering)"
elif printf '%s' "$body" | grep -qx 'Bsheel API'; then
  bad "health/live still returns the catch-all string \"Bsheel API\" — the Caddy route is not in effect"
else
  bad "health/live -> $code  body: $body"
fi

code=$(get "$HOST/api/v1/health/ready"); body=$(cat /tmp/vf.$$ 2>/dev/null)
if [ "$code" = 200 ] && printf '%s' "$body" | grep -q '"postgres":"up"' && printf '%s' "$body" | grep -q '"redis":"up"'; then
  ok "health/ready -> postgres up, redis up"
else
  bad "health/ready -> $code  body: $(head -c 200 <<<"$body")"
fi

# A wrong password must come back as a structured API error. If this returns
# 200 with "Bsheel API", the route is wrong; if it 500s, the app is broken.
code=$(curl -s -m 15 -o /tmp/vf.$$ -w '%{http_code}' -X POST "$HOST/api/v1/auth/login" \
  -H 'Content-Type: application/json' -d '{"email":"preflight@invalid.test","password":"wrong-on-purpose"}' 2>/dev/null || echo 000)
body=$(head -c 200 /tmp/vf.$$ 2>/dev/null)
case "$code" in
  400|401|403|404|422) ok "auth/login rejects bad credentials -> $code (real API, not the catch-all)" ;;
  200)                 bad "auth/login -> 200 for a bogus account. body: $body" ;;
  *)                   bad "auth/login -> $code  body: $body" ;;
esac

# The gateway is declared `transports: ['websocket']`, so Engine.IO answers a
# polling handshake with 400 "Transport unknown" by design. That response is
# itself the proof the route is mounted and reaching our app — a proxy that
# never routed /socket.io would 404 or serve the catch-all instead. Checking
# for the polling handshake failed a perfectly healthy deploy.
code=$(get "$HOST/socket.io/?EIO=4&transport=polling"); body=$(head -c 80 /tmp/vf.$$ 2>/dev/null)
if printf '%s' "$body" | grep -q '^0{'; then ok "socket.io handshake reaches the realtime gateway"
elif printf '%s' "$body" | grep -q 'Transport unknown'; then
  ok "socket.io route reaches the gateway (polling refused by design; websocket only)"
else bad "socket.io/ -> $code  body: $body"; fi

# Root-level paths, outside /api/v1. Number Verification lands the browser on
# /phone-signin-callback and iOS fetches the association file from the domain
# root, so both need their own Caddy route (@bsheel_root). Without it the
# catch-all answers "Bsheel API" — 200, and completely wrong: iOS never learns
# the app owns the link, and a verified tester dead-ends on that string.
code=$(get "$HOST/.well-known/apple-app-site-association"); body=$(head -c 300 /tmp/vf.$$ 2>/dev/null)
if [ "$code" = 200 ] && printf '%s' "$body" | grep -q '"applinks"'; then
  ok "apple-app-site-association -> JSON with applinks (root route in effect)"
elif printf '%s' "$body" | grep -qx 'Bsheel API'; then
  bad "apple-app-site-association returns the catch-all string — the @bsheel_root Caddy route is missing"
else
  bad "apple-app-site-association -> $code  body: $(head -c 80 <<<"$body")"
fi

code=$(get "$HOST/phone-signin-callback?error=INVALID_PHONE_SIGNIN_STATE"); body=$(head -c 300 /tmp/vf.$$ 2>/dev/null)
if [ "$code" = 200 ] && printf '%s' "$body" | grep -qi '<!doctype html>'; then
  ok "phone-signin-callback -> the landing page (HTML)"
else
  bad "phone-signin-callback -> $code  body: $(head -c 80 <<<"$body")"
fi

# /docs: Swagger's exposure is a deliberate operator choice (SWAGGER_ENABLED),
# reported rather than judged. Public docs enumerate the API's routes; every
# route still enforces its own authentication.
code=$(get "$HOST/docs")
[ "$code" = 200 ] && printf '%s' "$(head -c 200 /tmp/vf.$$)" | grep -qi swagger \
  && ok "/docs serves Swagger publicly (SWAGGER_ENABLED=true — intentional; routes still authenticate)" \
  || ok "/docs is not serving a public API explorer"

hdr "REGRESSION GUARD — live quest-app Supabase stack"
check_sb() {
  local path="$1" want="$2" label="$3"
  local c; c=$(get "$HOST$path")
  if [ "$c" = "$want" ]; then ok "$label $path -> $c (unchanged)"
  else bad "$label $path -> $c, expected $want — THE LIVE APP MAY BE BROKEN"; fi
}
check_sb /auth/v1/health      401 "GoTrue"
check_sb /rest/v1/            401 "PostgREST"
check_sb /storage/v1/version  200 "Storage"
check_sb /functions/v1/       400 "Edge functions"

hdr "Media host (skip if using Cloudflare R2)"
mcode=$(get "https://media.bsheel.app/minio/health/live")
case "$mcode" in
  200) ok "media.bsheel.app MinIO healthy" ;;
  000) printf "  \033[33mSKIP\033[0m media.bsheel.app not configured (expected when using R2)\n" ;;
  *)   printf "  \033[33mWARN\033[0m media.bsheel.app -> %s\n" "$mcode" ;;
esac

rm -f /tmp/vf.$$
printf "\n\033[1m== Result ==\033[0m\n  %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || { printf "\n\033[31mDeploy is NOT healthy.\033[0m\n"; exit 1; }
printf "\n\033[32mBsheel is live and quest-app is intact.\033[0m\n"
printf "The TestFlight build should now sign in — it already points at %s/api/v1\n" "$HOST"
