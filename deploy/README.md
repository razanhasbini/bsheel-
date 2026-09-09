# Deploying the Bsheel backend to the Contabo VPS

## Read this first

`169.58.16.247` is **not a blank server.** It runs the live self-hosted
Supabase stack that serves quest-app in the App Store:

| Path on `api.bsheel.app` | Component |
|---|---|
| `/auth/v1/*` | GoTrue |
| `/rest/v1/*` | PostgREST |
| `/storage/v1/*` | Supabase Storage 1.60.4 |
| `/functions/v1/*` | Edge functions runtime |
| `/api/v1/*` | **unused** — a catch-all returning the string `Bsheel API` |

Bsheel slots into that unused `/api/v1` prefix. Nothing else moves. Caddy
already terminates TLS with a Let's Encrypt certificate for `api.bsheel.app`,
so there is no DNS change and **no app rebuild** — the TestFlight build already
points at `https://api.bsheel.app/api/v1`.

Two rules follow, and both are enforced by scripts here:

1. **Bsheel gets its own Postgres.** Its migrations are forward-only and
   checksummed against their own ledger; run against Supabase's 146-file
   history they would collide. `preflight.sh` refuses to deploy if
   `DATABASE_URL` points at this host.
2. **Caddy is edited by hand.** A bad reload takes the live app offline, so
   `deploy.sh` never touches it.

## Files

| File | Role |
|---|---|
| `docker-compose.prod.yml` | postgres, redis, migrate, api, worker (+ optional minio). Own project/network/volumes, no published datastore ports, memory caps. |
| `.env.prod.example` | Full env template. `__PLACEHOLDER__` values are generated; `REPLACE_ME` values are yours. |
| `gen-secrets.sh` | Generates the four independent crypto secrets. Refuses to overwrite. |
| `preflight.sh` | Read-only. Resources, ports, live-stack baseline, the database-isolation check. |
| `deploy.sh` | Sync, secrets, preflight, build, start. Run from your Mac. |
| `verify.sh` | Post-deploy: Bsheel is live **and** quest-app is intact. |
| `caddy-apply.sh` | Publishes it through Caddy: backup, edit, validate, reload, verify, **auto-rollback**. |
| `caddy_insert.py` | The Caddyfile editor `caddy-apply.sh` calls. Refuses ambiguous configs rather than guessing. 18 unit-tested shapes. |
| `caddy-bsheel.caddy` | The same routes as a reference snippet, if you prefer to paste by hand. |

## Steps

### 0. Get SSH access

The server accepts **publickey only** — password auth is disabled, so the root
password from the Contabo email will not work over SSH. A key is generated at
`~/.ssh/bsheel_deploy`; add its public half to the server's
`/root/.ssh/authorized_keys` either through **Contabo's VNC console** (works
without SSH) or by asking whoever provisioned the box.

```bash
cat ~/.ssh/bsheel_deploy.pub
ssh -i ~/.ssh/bsheel_deploy root@169.58.16.247 'echo ok'
```

### 1. Look before touching

```bash
./deploy/deploy.sh --preflight-only
```

Reports CPU, memory, disk, what is listening, and records the live Supabase
baseline. Changes nothing.

### 2. Secrets

`deploy.sh` runs `gen-secrets.sh` on the server on first use, then stops and
asks for the two things it cannot invent:

- **`FIREBASE_SERVICE_ACCOUNT`** — the one-line JSON already working in your
  local `backend/.env`. Without it push is off, and per `CLAUDE.md` tapping a
  notification is the *primary* route to the appeal flow.
- **Object storage.** Required for the core loop: submitting photo/video proof
  writes here. Either the MinIO pair (Option A, self-hosted on the box, needs
  a `media.bsheel.app` A record) or Cloudflare R2 credentials (Option B,
  recommended — no disk pressure, and you already have an R2 account). Create
  a **new** bucket; do not reuse quest-app's.

### 3. Deploy and publish — one command

```bash
./deploy/deploy.sh --apply-caddy --admin
```

That syncs, preflights, builds, starts, edits Caddy and verifies. The Caddy
step protects itself: it records what the live quest-app endpoints return
*before* touching anything, backs up the Caddyfile, validates, reloads, then
re-checks those endpoints — and **restores the backup and reloads again** if
any of them changed or if Bsheel is not answering.

It refuses to edit rather than guess when the `api.bsheel.app` block has a
bare top-level `reverse_proxy`/`respond`/`file_server`, because such a
directive matches every path and the new handles would never be reached.
Wrap the existing one in `handle { ... }` and re-run.

Without `--apply-caddy` the stack comes up bound to `127.0.0.1` only, nothing
is public, and you can paste the snippet from `caddy-bsheel.caddy` by hand.

### 4. Verify

```bash
./deploy/verify.sh
```

Checks the NestJS app answers `/api/v1` (not the old catch-all), Postgres and
Redis are up, bad credentials are rejected properly, the Socket.IO handshake
reaches the gateway, `/docs` is not public — **and** that GoTrue, PostgREST,
Storage and edge functions still return exactly what they returned before.

### 5. Create your account

The production database starts empty. `seed-local.mjs` refuses to run against
anything resembling production, by design — so register through the app.
`AUTH_EMAIL_CONFIRMATION_REQUIRED=false` in the template because no email
provider is wired; with it `true` a signup could never confirm and nobody
could log in. To make yourself an admin:

```bash
docker compose --env-file .env.prod -f docker-compose.prod.yml exec postgres \
  psql -U bsheel -d bsheel_prod -c \
  "INSERT INTO admins (user_id, role) SELECT id, 'super_admin' FROM users WHERE email='you@example.com';"
```

## Rollback

```bash
cd /opt/bsheel/deploy
docker compose --env-file .env.prod -f docker-compose.prod.yml stop api worker
```

Then remove the two handles from Caddy and reload. `/api/v1` returns to the
catch-all and quest-app is unaffected — it never depended on any of this.

Never `down -v`: that destroys `bsheel_postgres_data`.

## Known gaps after this deploy

- **Password reset is inert.** No email provider; `EMAIL_DELIVERY_WEBHOOK_URL`
  is empty. Both webhook vars must be set together or the schema rejects boot.
- **Admin panel lives at `/v2/`** while quest-app's occupies `/`. Move it at
  cutover.
- **Deep links already work** — the live `assetlinks.json`
  (`com.questapp.mobile_app`) and `apple-app-site-association`
  (`JMDKX9TYX6.com.questapp.mobileApp`, covering `/post/*`, `/user/*`,
  `/join/*`) are correct for Bsheel. Do not overwrite them.
- **The two inherited credentials** — the `service_role` JWT (exp 2036) and
  `AuthKey_V5L2554CT7.p8` — are still valid until rotated. See
  `docs/security/SECRET_ROTATION_RUNBOOK.md`.
