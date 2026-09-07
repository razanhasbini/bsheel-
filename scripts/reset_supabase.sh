#!/bin/bash
# LOCAL DEV ONLY — rebuilds the local database from the full migration
# history + seeds. Production (api.bsheel.app) is never touched by this;
# prod migrations are applied by scripts/server-deploy.sh.
#
# Note: migration history lives in supabase/migrations/applied/ (frozen)
# plus any pending top-level files — `supabase db reset` alone would only
# replay the top-level files, so this script replays everything itself.
set -e

DB_URL="${SUPABASE_DB_URL:-postgresql://postgres:postgres@127.0.0.1:54322/postgres}"

echo "Wiping local public schema..."
psql "$DB_URL" -v ON_ERROR_STOP=1 -q -c \
  "drop schema if exists public cascade;
   create schema public;
   grant usage on schema public to postgres, anon, authenticated, service_role;
   grant all on schema public to postgres, service_role;"

echo "Replaying migration history (applied/ then pending)..."
for f in supabase/migrations/applied/*.sql supabase/migrations/*.sql; do
  [ -e "$f" ] || continue
  echo "  $f"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$f"
done

echo "Applying seed data..."
for seed_file in supabase/seed/*.sql; do
  echo "  $seed_file"
  psql "$DB_URL" -v ON_ERROR_STOP=1 -q -f "$seed_file"
done

echo "Local reset complete."
