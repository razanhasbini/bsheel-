# Deploying `quest-media-upload` worker

The worker code (`worker-r2-upload.js`) and its config (`wrangler-upload.toml`)
are in this directory. Deploy this from the Cloudflare account that owns
`https://quest-media-upload.laythayache5.workers.dev` (i.e. **laythayache5's**
Cloudflare account). It's not deployable from `tayseerlaz`'s machine because
the existing worker lives on a different CF account.

## Prerequisites

- Node.js 22+ (Wrangler 4.x dropped Node 20 support)
  - On Node 20: `npx wrangler@3 ...` works for now
- Cloudflare account access to `laythayache5`
- The R2 bucket `quest-media` already exists with the bucket-name binding
  set in `wrangler-upload.toml`

## Deploy steps

```bash
# 1. Log in to Cloudflare (opens a browser).
npx wrangler@latest login

# 2. Deploy the worker.
npx wrangler@latest deploy --config cloudflare/wrangler-upload.toml

# 3. Set the secrets (paste each value when prompted).
#    MEDIA_SIGNING_SECRET — see SECRETS_2026-06-02.txt at the repo root.
npx wrangler@latest secret put MEDIA_SIGNING_SECRET \
  --config cloudflare/wrangler-upload.toml

# 4. (Required if not already set) Supabase auth pair so the worker
#    can validate uploader tokens.
npx wrangler@latest secret put SUPABASE_URL \
  --config cloudflare/wrangler-upload.toml
# Value: https://api.bsheel.app

npx wrangler@latest secret put SUPABASE_ANON_KEY \
  --config cloudflare/wrangler-upload.toml
# Value: the self-host anon JWT — copy SUPABASE_ANON_KEY from the repo-root .env
#        (starts "eyJhbGciOiJIUzI1NiI…"; it's the public anon key the apps use,
#         safe to embed in the worker). NOT the old hosted sb_publishable_ key —
#         that Supabase Cloud project is decommissioned.

# 5. (Required for browser uploads) CORS allow list.
npx wrangler@latest secret put ALLOWED_UPLOAD_ORIGINS \
  --config cloudflare/wrangler-upload.toml
# Value: https://admin.bsheel.app

# 6. (Optional) Override the signed-URL lifetime.
npx wrangler@latest secret put MEDIA_URL_TTL_SECONDS \
  --config cloudflare/wrangler-upload.toml
# Value: 900   (= 15 minutes, the default)
```

## Verify

```bash
# Anonymous upload should now be rejected (was permitted before):
curl -i -X PUT https://quest-media-upload.laythayache5.workers.dev/avatars/test/foo.jpg
# Expect 401

# Signed-URL exchange should work for a real Bearer token:
curl -s -X POST https://quest-media-upload.laythayache5.workers.dev/sign \
  -H "Authorization: Bearer <a-real-supabase-jwt>" \
  -H "Content-Type: application/json" \
  -d '{"urls":["avatars/<user-id>/avatar.jpg"]}'
# Expect { "urls": { "avatars/...": "https://.../media/...?exp=...&sig=..." } }
```

## After deploy

- Sanity-check that an existing user's avatar still renders in the mobile
  app (post-deploy clients call `/sign` first).
- Once you're satisfied, **disable the public `pub-c5cc3a25...r2.dev` bucket
  URL** in the Cloudflare R2 dashboard so leaked legacy URLs stop working.
- Remove `PUBLIC_URL` from `wrangler-upload.toml` once no client falls
  back to it.
