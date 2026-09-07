# Deployment Policy — Bit Sheel?

**One rule: you deploy by pushing to `main`. Nobody edits the server by hand.**

The backend is self-hosted on our Contabo box (`api.bsheel.app`). All server-side
changes are shipped automatically by GitHub Actions
([`.github/workflows/deploy-server.yml`](../.github/workflows/deploy-server.yml)) when
`main` changes. Manually SSHing in to rsync files, run migrations, rebuild the admin
dashboard, or `caddy reload` is **not allowed** — it drifts the server out of sync with
git, skips migration tracking, and has broken admin login before.

## How to deploy

1. Branch off `main`, make your change, open a **Pull Request**.
2. CI runs automatically on the PR: `analyze`, `test`, and `dart format` must pass.
3. Get it reviewed and **merge to `main`**.
4. The **Deploy to server** workflow fires on the merge and does everything below.
   Watch it under the repo's **Actions** tab; the run is green when it's live.

That's it. No terminal, no SSH, no manual build.

## What a push to `main` deploys automatically

| Part | Where it lands |
|------|----------------|
| Edge functions (`supabase/functions/`) | rsynced to the server's functions runtime |
| New DB migrations (`supabase/migrations/*.sql`) | applied to Postgres, tracked by filename (idempotent — safe to re-run) |
| Admin dashboard (`apps/admin_web`) | rebuilt as Flutter web, served at https://admin.bsheel.app |

## What is NOT deployed by this (important)

- **The mobile app.** The iOS/Android binary ships through the App Store / Play Store,
  built with `flutter build ipa` (see `CLAUDE.md`). Pushing to `main` does **not** put a
  new app in users' hands — that's a separate store release.

## Rules that keep deploys safe

- **Never deploy by hand on the server.** No manual `rsync`, `scp`, `docker` file copies,
  or migration runs. Push to `main` and let CI do it.
- **New migration = next number at the TOP LEVEL** of `supabase/migrations/`
  (e.g. `0148_...`). **Never** rename, renumber, re-apply, or edit anything in
  `supabase/migrations/applied/` — that's frozen, already-applied history.
- **Never run `caddy reload`** on the server. Its Basic-Auth password is hashed once at
  container start; a reload breaks admin login (HTTP 401). Caddyfile changes require a full
  `docker compose restart caddy`.
- **Secrets never go in git.** Server/CI secrets live in GitHub → Settings → Secrets and
  in the server's `.env`. Client build values are the client-safe `--dart-define`s only.

## Need to re-run a deploy without a new commit?

Use the manual trigger — still no server edits:
**Actions → "Deploy to server" → Run workflow** (`workflow_dispatch`).

## Who can push / merge to `main`

If you want stronger enforcement than convention, turn on a branch protection rule on
`main` (require PR + passing CI before merge) so a hand-deploy simply isn't possible.
