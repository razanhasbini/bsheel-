#!/usr/bin/env bash
# Runs ON the Contabo server (invoked by .github/workflows/deploy-server.yml).
# Applies any not-yet-applied DB migrations (idempotent, tracked) and restarts
# the edge-functions runtime so freshly-rsynced function code is picked up.
set -uo pipefail
STACK=/root/supabase-docker
MIG=/root/deploy/migrations
DB(){ docker exec -i supabase-db psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres "$@"; }

echo "== migration tracking table =="
DB -c "create table if not exists public._applied_migrations(filename text primary key, applied_at timestamptz default now());" >/dev/null

echo "== apply new migrations =="
applied=0
for f in $(ls "$MIG"/*.sql 2>/dev/null | sort); do
  b=$(basename "$f")
  seen=$(DB -Atc "select 1 from public._applied_migrations where filename = '$b'")
  if [ -z "$seen" ]; then
    echo "  applying $b ..."
    if DB < "$f"; then
      DB -c "insert into public._applied_migrations(filename) values ('$b') on conflict do nothing" >/dev/null
      applied=$((applied+1))
    else
      echo "  !! FAILED: $b — aborting deploy (fix the migration, then re-run)"; exit 1
    fi
  fi
done
echo "  applied $applied new migration(s)"

echo "== admin bootstrap =="
# Creates/rotates the super_admin account. Password is NEVER in git — it
# arrives here as $NEW_ADMIN_PASSWORD (SSH-forwarded from a GitHub secret).
# No-op when unset, so ordinary deploys skip it.
if [ -n "${NEW_ADMIN_PASSWORD:-}" ] && [ -f /root/deploy/admin_bootstrap.sql ]; then
  if docker exec -i supabase-db psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres \
       -v admin_email="${NEW_ADMIN_EMAIL:-layth@bsheel.app}" \
       -v admin_username="${NEW_ADMIN_USERNAME:-layth}" \
       -v admin_pw="$NEW_ADMIN_PASSWORD" \
       < /root/deploy/admin_bootstrap.sql; then
    echo "  admin bootstrap ok"
  else
    echo "  !! admin bootstrap failed (non-fatal)"
  fi
else
  echo "  (NEW_ADMIN_PASSWORD unset — skipping)"
fi

echo "== restart edge functions runtime =="
cd "$STACK" && docker compose up -d functions >/dev/null 2>&1 && echo "  edge-functions restarted"
echo "== server-deploy done =="
