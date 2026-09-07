#!/usr/bin/env bash
# Repoint the Cloudflare R2 media workers at the self-hosted backend (api.bsheel.app).
# The R2 bucket `quest-media` is UNCHANGED — only the Supabase URL/keys the workers
# use to verify auth tokens are updated.
#
# Run once:
#   npx wrangler login        # (or: export CLOUDFLARE_API_TOKEN=...)
#   bash cloudflare/repoint-workers-to-selfhost.sh
set -euo pipefail
cd "$(dirname "$0")"

# Pull the new backend URL + keys from the repo-root .env (already updated).
set -a; source ../.env; set +a
: "${SUPABASE_URL:?}" "${SUPABASE_ANON_KEY:?}" "${SUPABASE_SERVICE_ROLE_KEY:?}"
echo "Repointing R2 workers to: $SUPABASE_URL"

echo "== quest-media-upload =="
printf '%s' "$SUPABASE_URL"      | npx wrangler secret put SUPABASE_URL      --config wrangler-upload.toml
printf '%s' "$SUPABASE_ANON_KEY" | npx wrangler secret put SUPABASE_ANON_KEY --config wrangler-upload.toml

echo "== quest-media-cleanup =="
printf '%s' "$SUPABASE_URL"              | npx wrangler secret put SUPABASE_URL              --config wrangler-cleanup.toml
printf '%s' "$SUPABASE_ANON_KEY"         | npx wrangler secret put SUPABASE_ANON_KEY         --config wrangler-cleanup.toml
printf '%s' "$SUPABASE_SERVICE_ROLE_KEY" | npx wrangler secret put SUPABASE_SERVICE_ROLE_KEY --config wrangler-cleanup.toml

echo "== redeploy both workers =="
npx wrangler deploy --config wrangler-upload.toml
npx wrangler deploy --config wrangler-cleanup.toml

echo "Done. R2 workers now verify tokens against $SUPABASE_URL. Bucket quest-media unchanged."
