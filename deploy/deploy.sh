#!/usr/bin/env bash
# Ship the Bsheel backend to the Contabo VPS.
#
#   ./deploy.sh --preflight-only      # inspect the box, change nothing
#   ./deploy.sh                       # sync + build + start + verify
#   ./deploy.sh --seed                # also seed the curated quest catalogue
#   ./deploy.sh --admin               # also build and upload the admin panel
#   ./deploy.sh --apply-caddy         # also publish it through Caddy (with rollback)
#
# Deliberately NOT idempotent-by-force: it never runs `down -v`, never drops a
# volume and never touches Caddy's config. The Caddy edit is manual and
# reviewed, because a bad reload takes the live quest-app offline.
set -euo pipefail
cd "$(dirname "$0")"

SERVER="${BSHEEL_SERVER:-root@169.58.16.247}"
KEY="${BSHEEL_SSH_KEY:-$HOME/.ssh/bsheel_deploy}"
REMOTE_DIR="${BSHEEL_REMOTE_DIR:-/opt/bsheel}"
PREFLIGHT_ONLY=0
WITH_ADMIN=0
WITH_SEED=0
APPLY_CADDY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --preflight-only) PREFLIGHT_ONLY=1; shift ;;
    --admin)          WITH_ADMIN=1; shift ;;
    --seed)           WITH_SEED=1; shift ;;
    --apply-caddy)    APPLY_CADDY=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

step() { printf "\n\033[1m==> %s\033[0m\n" "$1"; }
fail() { printf "\033[31merror: %s\033[0m\n" "$1" >&2; exit 1; }

[ -f "$KEY" ] || fail "no ssh key at $KEY — generate one and add it to the server's authorized_keys"
SSH="ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=15"

step "Connectivity"
$SSH "$SERVER" 'echo ok' >/dev/null 2>&1 \
  || fail "cannot reach $SERVER with $KEY.
       The server accepts publickey auth only (password auth is disabled), so
       the public half must be in its authorized_keys. Add it through
       Contabo's VNC console, or get the existing key from whoever set the
       box up. Public key to paste:
$(cat "$KEY.pub" 2>/dev/null | sed 's/^/         /')"
echo "connected to $SERVER"

step "Sync source to $REMOTE_DIR"
$SSH "$SERVER" "mkdir -p $REMOTE_DIR"
# --delete keeps the remote tree honest, but .env.prod lives only on the
# server and must survive: it is generated there and never committed.
rsync -az --delete \
  -e "$SSH" \
  --exclude '.git/' --exclude 'build/' --exclude 'node_modules/' \
  --exclude '.dart_tool/' --exclude '*.log' \
  --exclude 'backend/.env' --exclude 'deploy/.env.prod' \
  --exclude 'apps/mobile_app/ios/' --exclude 'apps/mobile_app/android/' \
  ../backend ../deploy "$SERVER:$REMOTE_DIR/"
echo "synced"

step "Secrets"
if $SSH "$SERVER" "[ -f $REMOTE_DIR/deploy/.env.prod ]"; then
  echo ".env.prod already present on the server (left untouched)"
else
  echo "generating .env.prod on the server"
  $SSH "$SERVER" "cd $REMOTE_DIR/deploy && ./gen-secrets.sh"
  printf "\n\033[33mSTOP.\033[0m .env.prod now needs values only you have:\n"
  printf "  * FIREBASE_SERVICE_ACCOUNT  (copy the one-line JSON from your local backend/.env)\n"
  printf "  * object storage keys       (MinIO pair, or Cloudflare R2 credentials)\n"
  printf "\nEdit it:  ssh -i %s %s 'nano %s/deploy/.env.prod'\n" "$KEY" "$SERVER" "$REMOTE_DIR"
  printf "Then run this script again.\n"
  exit 3
fi

step "Preflight (read-only)"
$SSH "$SERVER" "cd $REMOTE_DIR/deploy && ./preflight.sh" || fail "preflight failed — nothing was changed"

[ "$PREFLIGHT_ONLY" -eq 1 ] && { echo; echo "preflight only — stopping here."; exit 0; }

step "Build and start (this takes ~3-4 minutes)"
# No --force-recreate and no -v: existing data volumes are preserved.
$SSH "$SERVER" "cd $REMOTE_DIR/deploy && docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build"

step "Wait for readiness on the container port"
$SSH "$SERVER" '
  PORT=$(grep -E "^API_BIND_PORT=" '"$REMOTE_DIR"'/deploy/.env.prod | cut -d= -f2); PORT=${PORT:-3010}
  # NestFactory.create takes ~52s; allow generously before calling it failed.
  for i in $(seq 1 60); do
    if curl -sf -m 4 "http://127.0.0.1:$PORT/api/v1/health/ready" >/dev/null 2>&1; then
      echo "API ready after ~$((i*3))s"; curl -s "http://127.0.0.1:$PORT/api/v1/health/ready"; echo; exit 0
    fi
    sleep 3
  done
  echo "API did not become ready in 180s. Recent logs:"
  cd '"$REMOTE_DIR"'/deploy && docker compose --env-file .env.prod -f docker-compose.prod.yml logs --tail=60 api
  exit 1
' || fail "the API did not come up; Caddy was not touched, so quest-app is unaffected"

if [ "$WITH_SEED" -eq 1 ]; then
  step "Seed the curated quest catalogue"
  # Idempotent on `seed_key`, so re-running only updates what changed and a
  # second run is a no-op. Deliberately opt-in and AFTER the readiness check:
  # migrations are part of every deploy because the schema must match the
  # code, but content is a decision, and it is not one to make while the API
  # is still coming up.
  #
  # No --prune. Pruning deletes seeded rows no longer in the files, which on
  # a live database can take content out from under players mid-quest.
  $SSH "$SERVER" "cd $REMOTE_DIR/deploy && docker compose --env-file .env.prod -f docker-compose.prod.yml \
    run --rm --no-deps api node scripts/seed-quests.mjs" \
    || fail "seeding failed — the API is up and serving whatever it had before"
fi

if [ "$WITH_ADMIN" -eq 1 ]; then
  step "Build the admin dashboard for /v2/"
  ( cd ../apps/admin_web && flutter build web --release \
      --base-href=/v2/ \
      --dart-define=API_URL=https://api.bsheel.app/api/v1 )
  $SSH "$SERVER" "mkdir -p /srv/bsheel-admin/v2"
  rsync -az --delete -e "$SSH" ../apps/admin_web/build/web/ "$SERVER:/srv/bsheel-admin/v2/"
  echo "uploaded to /srv/bsheel-admin/v2 — serve it with the Caddy block in caddy-bsheel.caddy"
fi

if [ "$APPLY_CADDY" -eq 1 ]; then
  step "Publish through Caddy (backed up, validated, verified, auto-rollback)"
  $SSH "$SERVER" "cd $REMOTE_DIR/deploy && ./caddy-apply.sh" \
    || fail "Caddy step failed and rolled itself back — quest-app is unaffected"

  step "Full verification from here"
  ./verify.sh || fail "verification failed; see output above"
  printf "\n\033[32mDeployed.\033[0m The TestFlight build points at\n"
  printf "https://api.bsheel.app/api/v1 and should now sign in.\n"
else
  step "Caddy — not applied"
  cat <<'MSG'
The container is up and answering on 127.0.0.1 only. Nothing is public yet,
and quest-app is untouched.

To publish it, either re-run with --apply-caddy (backs up the Caddyfile,
validates, reloads, re-checks the live quest-app endpoints, and rolls back
automatically if anything regresses), or paste the handles from
caddy-bsheel.caddy in by hand and then run ./verify.sh.
MSG
fi
