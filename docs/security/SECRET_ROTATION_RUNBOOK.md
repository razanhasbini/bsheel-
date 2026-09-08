# Secret rotation runbook

> Use this when (a) a key is suspected of being leaked, (b) a contributor
> with key access leaves the team, or (c) on the routine rotation cadence
> (every 6 months).

> **Scope: the legacy stack.** Every secret inventoried below belongs to the
> self-hosted Supabase deployment and the Cloudflare R2 workers — anon and
> service-role JWTs, `JWT_SECRET`/`JWT_JWKS`, edge-function secrets, and the
> R2 media signing secret. That stack's *source* is no longer in this
> repository: the `supabase` and `cloudflare` trees were deleted when the
> NestJS backend in `backend/` replaced them, and no shipped client reaches
> any of it any more.
>
> The runbook is kept because those secrets may still be live on the Contabo
> box and in the Cloudflare account, and a leaked one still has to be rotated
> there. Do all of it against the running infrastructure — server-side files,
> the Cloudflare dashboard, the `wrangler` CLI pointed at a config you supply
> yourself. Nothing below can be driven from a file in this repo. Secrets for
> the current backend live in `backend/.env.example`.

## Inventory

| Secret | Where it lives | Who can rotate | Rotation cost |
|---|---|---|---|
| **Supabase anon key (JWT, `eyJ…`)** | Mobile/admin clients via `--dart-define=SUPABASE_ANON_KEY`; same JWT pasted into the Cloudflare worker secret `SUPABASE_ANON_KEY`. Long-lived JWT signed by the self-host `JWT_SECRET` — public/embeddable, like the old publishable key. | Self-host admin (holds `JWT_SECRET` on Contabo) | Re-mint JWT + app release + worker secret update. Truly killing a leaked key needs a `JWT_SECRET` rotation (below). |
| **Supabase service-role key** (JWT, `eyJ…`) | Self-host Edge Functions (`send-push`, `notify-on-insert`, `telegram-*`). Never in client. Also a JWT signed by `JWT_SECRET`. | Self-host admin (Contabo server) | Re-mint JWT + edge-function secret rotation |
| **Supabase JWT secret** (`JWT_SECRET`, `/root/supabase-docker/.env`) | Signs user sessions AND the anon/service-role JWTs. Rotating invalidates ALL active sessions and both keys. | Self-host admin (Contabo server) | Re-mint anon+service keys, recreate auth/rest/storage/realtime containers, every user re-logs in |
| **`MEDIA_SIGNING_SECRET`** | Cloudflare worker `quest-media-upload` (only). Used to HMAC-sign R2 media URLs. | laythayache5 (CF account) | Worker secret swap; all in-flight signed URLs become invalid (15-min window) |
| **Admin dashboard Basic Auth** (`DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`) | Caddy `basic_auth` fronting `admin.bsheel.app`. Plaintext lives in `/root/supabase-docker/.env` on Contabo; Caddy hashes it at container start. | tayseerlaz (Contabo server) | Recreate the `caddy` container; whoever uses the dashboard needs the new value |
| **`TELEGRAM_BOT_TOKEN`** | Supabase Edge Functions only. | Telegram bot owner | Edge-function secret swap |
| **`TELEGRAM_WEBHOOK_SECRET`** | Telegram webhook + edge function. | Telegram bot owner | Both sides must update together |
| **Firebase Cloud Messaging server credentials** | `send-push` edge function (service account JSON). | Firebase project owner | Edge-function secret swap |
| **Mixpanel project token** | Mobile build (`--dart-define=MIXPANEL_TOKEN`). | Mixpanel project owner | App release |

## Routine rotation (every 6 months)

1. **Supabase anon key (JWT)**
   - The anon key is a JWT signed by the self-host `JWT_SECRET` — there is no
     hosted "reset publishable key" button anymore. Mint a fresh anon JWT on the
     server, signed with the current `JWT_SECRET`, payload
     `{"role":"anon","iss":"supabase","iat":<now>,"exp":<far-future>}`.
   - Update the repo-root `.env` `SUPABASE_ANON_KEY` (and any CI secret / build define of the same name).
   - Bump the version in `apps/mobile_app/pubspec.yaml`, ship a release IPA + APK, push the admin web build.
   - Update the worker secret `SUPABASE_ANON_KEY` on the `quest-media-upload`
     worker. The `wrangler` config that used to live in this repo was deleted
     with the legacy stack, so do this from the Cloudflare dashboard, or with
     `wrangler secret put` against a config you reconstruct locally.
   - Caveat: minting a new anon JWT does NOT disable the old one — JWTs aren't
     individually revocable, so the old key works until its `exp`. To actually
     invalidate a leaked anon key, rotate `JWT_SECRET` (emergency step 3).

2. **`MEDIA_SIGNING_SECRET`**
   - Generate a new value: `openssl rand -hex 32`.
   - Update the worker secret (`MEDIA_SIGNING_SECRET`). Old signed URLs stop validating immediately — but expiry is only 15 minutes so users won't notice anything beyond a single retry.

3. **Admin dashboard Basic Auth** (`DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`)
   - Auth is enforced by **Caddy** (`basic_auth`) on the Contabo server, not by
     the app and not by the "Deploy to server" workflow. The dashboard is a
     static Flutter web build; publishing it never touches auth — rotating the
     password is a server-side change.
   - Generate: `openssl rand -base64 18 | tr -d '/+=' | head -c 24`.
   - SSH to the server and edit `/root/supabase-docker/.env`: set
     `DASHBOARD_PASSWORD=<new>` (and `DASHBOARD_USERNAME` too if rotating the
     user). Caddy consumes these as `PROXY_AUTH_USERNAME` / `PROXY_AUTH_PASSWORD`
     (see `docker-compose.caddy.yml`) and hashes the password at startup via
     `caddy hash-password`.
   - Recreate the Caddy container so it re-reads the env and re-hashes:
     ```
     cd /root/supabase-docker
     docker compose up -d --force-recreate caddy   # COMPOSE_FILE is preset in .env
     ```
     A plain `docker restart supabase-caddy` is NOT enough — it keeps the old
     baked-in env. Verify:
     `curl -sI https://admin.bsheel.app/ | grep -i www-authenticate` still returns
     a `401` challenge, and the new credentials log you in.
   - Share new password with whoever needs admin access via your secrets-sharing channel (1Password / Vaultwarden, NOT Slack).

4. **Mixpanel token** — only needed if you rotate the Mixpanel project entirely. Otherwise leave it.

## Emergency rotation (key suspected compromised)

> Do these in the order below. Each step is non-destructive on its own.

1. **Disable the admin panel access first** — rotate the admin dashboard Basic Auth (set a new `DASHBOARD_PASSWORD` in `/root/supabase-docker/.env`, then `docker compose up -d --force-recreate caddy` — see routine step 3). This buys you breathing room (any attacker who has the previous password can no longer get in).
2. **Rotate the `MEDIA_SIGNING_SECRET`** — invalidates every signed R2 URL the attacker may have collected within the last 15 min.
3. **Rotate `JWT_SECRET`** on the server (`/root/supabase-docker/.env`) — this is what actually kills a leaked anon/service key, since JWTs aren't individually revocable. Re-mint the anon + service JWTs with the new secret, update the repo `.env` / CI / the worker `SUPABASE_ANON_KEY` secret, then recreate the affected containers (`cd /root/supabase-docker && docker compose up -d --force-recreate auth rest storage realtime`). Ship the new APK + push the admin web build. **Until `JWT_SECRET` is rotated the old anon JWT keeps working — there's no revocation without this step.**
4. **Force-logout all users** — this is a side effect of the `JWT_SECRET` rotation in step 3 (it invalidates every issued session). There is no separate hosted "Reset JWT secret" button on the self-host; the rotation above IS that operation.
5. **Audit the admin_audit_log** for the rotation window (migration 0098/0121 created this table). Filter for any `admin_*` operation in the suspected compromise window — those are the actions the attacker could have performed.

## Audit

After ANY rotation, document in the rotation commit message:
- The date/time
- Which secret was rotated
- Reason (routine vs incident)
- Who did it
- Old key prefix (first 6 chars) for paper trail

Never commit the new value to git. The current values live in:
- Repo-root `SECRETS_<date>.txt` (gitignored, local-only)
- 1Password / team-vault entry named "BSHEEL — <secret name>"

## What ROTATION does NOT fix

- A leaked APK still has the OLD key embedded forever. RLS is what makes the key safe — keep migration 0143's policies in place.
- A Supabase service-role key that leaked into client code is a CATASTROPHE — service-role bypasses RLS. There's no in-app rotation that helps; you must rotate the service-role key AND audit every row for tampering.
- Telegram bot tokens, if leaked, allow message posting to the moderation channel. Rotate immediately + check the channel for unauthorized posts.

---

# Rotating `JWT_SECRET` without bricking every shipped app

> Added 2026-09-01, after the live `service_role` JWT was found committed on `main`
> (`6520808` → removed in the PR #56 merge). The key is **still in git history**, so it stays
> compromised until this rotation happens.
>
> The "Emergency rotation" section above says to rotate `JWT_SECRET` and "ship the new APK".
> That understates the cost, and this project is iOS-first: **the anon key is compiled into
> every shipped IPA via `--dart-define`. The moment `JWT_SECRET` changes, every already-installed
> app stops being able to talk to the API at all** — not "users must log in again", but a dead
> app until the user updates from the App Store. Read this section instead of that one line.

## What is actually configured (verified on the box, 2026-09-01)

| Variable | State | Consequence |
|---|---|---|
| `JWT_SECRET` | set, 64 chars (HS256) | signs the anon + service-role JWTs and every user session |
| `JWT_JWKS` | set, 417 chars — a JWKS holding one **oct** (symmetric) key | **`PGRST_JWT_SECRET` is `${JWT_JWKS:-$JWT_SECRET}`, so PostgREST validates against a JWKS, and a JWKS can hold MORE THAN ONE KEY** |
| `JWT_KEYS`, `ANON_KEY_ASYMMETRIC`, `SERVICE_ROLE_KEY_ASYMMETRIC` | **empty** | no asymmetric signing configured |
| `GET /auth/v1/.well-known/jwks.json` | `{"keys":[]}` | GoTrue publishes no public key; it signs with the single `GOTRUE_JWT_SECRET` |

The important consequence: **PostgREST can accept two keys at once; GoTrue can only sign with
one.** That is enough for an overlap rotation at the data layer, which is where the leaked
service-role key does its damage. It is not enough to avoid a single forced re-login.

## Prerequisite: arm the force-update gate first

`apps/mobile_app/lib/core/widgets/app_prompts_listener.dart` already honours
`update_required_min_build`, `update_required_force` and `update_required_message`, and migration
0149 already lets signed-out clients read them. **But none of those three rows exist in
`app_config` yet** — the lever is wired up and disconnected. Insert them (admin/super-admin only)
before you start, or you have no way to push users onto the new build.

Note while you are there: `socialLoginEnabledProvider` reads
`config['social_login_enabled'] != 'false'`, so an **absent** row means social login is ON. That is
fail-open on a kill-switch. It is currently harmless only because 0149 made the row readable.

## The rotation, in order

1. **Rehearse it somewhere that is not production.** Nothing below has been executed. It is
   derived from the live configuration, not from a completed run.
2. **Arm the force-update rows** (above) and confirm on a real device that an old build shows
   the non-dismissable overlay.
3. **Mint the new secret and add it to the JWKS *alongside* the old one.** `JWT_JWKS` is a JSON
   `{"keys":[…]}` — add the new `oct` key with a distinct `kid`, keep the old entry. Recreate
   `supabase-rest` only. Both old and new anon keys now validate. **Verify all six hostnames
   afterwards, not just bsheel's two** — `supabase-rest` shares the box.
4. **Mint new anon + service-role JWTs signed with the new key.** Update
   `apps/mobile_app/dart_defines.release.json`, the CI secret, and the Cloudflare worker secret
   `SUPABASE_ANON_KEY`. Rotate the edge-function service-role secret in the same pass.
5. **Ship the iOS build** carrying the new anon key, and only then set
   `update_required_min_build` to that build number.
6. **Wait for adoption.** Until the old key leaves the JWKS, both builds work — this is the whole
   point of the overlap and the only window where nothing is broken.
7. **Remove the old key from `JWT_JWKS`** and rotate `GOTRUE_JWT_SECRET` to the new value.
   This is the moment every existing session is invalidated and every user re-logs in, and the
   moment the leaked service-role key finally stops working. Recreate `auth rest storage realtime`
   — not `caddy`, and not `hood-api`.
8. **Verify:** the leaked key must now fail. Confirm with a request carrying the OLD service-role
   JWT — it must return 401. If it still returns data, the rotation did not take.
9. **Audit `admin_audit_log`** for the whole window the key was public (since `6520808`,
   2026-07-14), not just the rotation window.

## What this does NOT fix

The old key stays in git history forever. Rotation is what makes that harmless. Removing the file
from the tip — which is what the PR #56 merge did — is not rotation.
