#!/usr/bin/env bash
# Dump a schema-only baseline of the self-hosted database.
#
# Run ON the Contabo server (same box as server-deploy.sh):
#   bash dump_schema_baseline.sh > baseline_$(date +%Y%m%d).sql
# then copy it back into the repo:
#   scp root@<server>:/root/baseline_YYYYMMDD.sql supabase/schema/
#
# Purpose: with the 146 historical migrations frozen in
# supabase/migrations/applied/, a FRESH environment is rebuilt from this
# baseline + any top-level migrations, instead of replaying 146 files:
#   1. psql < supabase/schema/baseline_YYYYMMDD.sql
#   2. seed public._applied_migrations with every filename in applied/
#      (so server-deploy.sh never tries to re-run history):
#      for f in supabase/migrations/applied/*.sql; do
#        psql -c "insert into public._applied_migrations(filename)
#                 values ('$(basename "$f")') on conflict do nothing"
#      done
#   3. Let server-deploy.sh apply anything newer.
set -euo pipefail

docker exec supabase-db pg_dump \
  -U supabase_admin -d postgres \
  --schema-only --no-owner --no-privileges \
  --schema=public
