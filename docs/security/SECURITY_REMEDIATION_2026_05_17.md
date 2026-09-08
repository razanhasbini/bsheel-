# Security remediation — 2026-05-17 audit fix pass

> **Historical record.** This documents a fix pass against the *legacy*
> stack — self-hosted Supabase (SQL migrations, RLS policies, Postgres
> triggers, Deno edge functions) plus a Cloudflare R2 upload worker. That
> entire stack was removed from the repository when the NestJS backend in
> `backend/` replaced it. Every citation below that names a SQL migration
> (`0140`, `0141`, `0142`, `0143`), an edge function (`admin_manage_user`,
> `send-push`, `telegram-*`, `notify-on-insert`), an R2 worker, or a
> `Supabase*Repository` Dart class refers to code that is no longer in the
> tree; it is readable only in git history. The findings and the reasoning
> are kept because they are the audit trail. The file paths are not
> navigable and the steps are not runnable.

Companion to the 2026-05-17 full security audit. Every finding has
either been fixed in code (cited below with the file and audit ID),
deferred with a note, or marked owner-action.

## How this was deployed

> ⚠️ **The deploy procedure this audit shipped against no longer exists.**
> It targeted Supabase Cloud, then a self-hosted Supabase box: SQL migrations,
> Deno edge functions, and a Cloudflare R2 upload worker. All three were
> removed from the repository when the NestJS backend replaced them, along
> with the `deploy-server.yml` workflow that pushed them.
>
> There is nothing here to re-run. For how the project ships today — and for
> the fact that there is currently no production pipeline at all — see
> `docs/DEPLOYMENT.md`. Mobile releases are in `docs/PUBLISHING.md`.

## Fix matrix

### Critical

| ID | Finding | Status | Where |
|---|---|---|---|
| C1 | Profile xp/level self-mint | ✅ Fixed | `0140` BEFORE-UPDATE trigger `guard_profile_owner_update` |
| C2 | Reroll farm (client-side limit) | ✅ Fixed | `0140` — 5/24h cap moved into `enforce_assign_quest_cooldown` |
| C3 | Submission timeline replay | ✅ Fixed | `0140` BEFORE-INSERT trigger `guard_submission_insert_timing` |
| C4 | Deep-link UUID validation + autoVerify | ✅ Fixed (code) / 🔶 Owner deploys AASA+assetlinks | `app_router.dart` + `AndroidManifest.xml`; templates in `docs/deep_links/` |
| C5 | Deleted-submission appeal | ✅ Fixed | `0140` `appeal_submission()` checks `visibility != 'deleted'` |
| C6 | Telegram timing-attack | ✅ Fixed | `telegram-webhook/index.ts` `constantTimeEqual` |
| C7 | Admin password reset no email confirm | ✅ Fixed | `admin_manage_user/index.ts` — new `request_password_reset` action + `confirm: true` flag on force-reset + victim notification |
| C8 | RLS off on `private.profile_tokens` | ✅ Fixed | `0140` ENABLE RLS + deny-all policy |
| C9 | Public reads on follows / app_config | ✅ Fixed | `0140` policies restricted to `authenticated` |

### High

| ID | Finding | Status | Where |
|---|---|---|---|
| H1 | Profile cascade destroys evidence | ✅ Fixed (via H5) | `0140` `reserve_username_on_profile_delete` turns DELETE into a tombstone UPDATE, so referenced rows survive |
| H2 | Firebase key not cached | ✅ Fixed | `send-push/index.ts` `getCachedKey`/`cachedToken` |
| H3 | No rate limits on admin/send-push | ✅ Fixed | sliding-minute buckets in `admin_manage_user` + `send-push` |
| H4 | Self-reaction | ✅ Fixed | `0140` `reactions_insert_own` policy now excludes own submissions |
| H5 | Username takeover | ✅ Fixed | `0140` `reserve_username_on_profile_delete` |
| H6 | No CAPTCHA on signup | 🔶 Owner action | Needs Cloudflare Turnstile site key. Hook point: `signup_page.dart::_signup` |
| H7 | debugPrint in release | ✅ Fixed | 18 calls wrapped in `if (kDebugMode)` across 9 files |
| H8 | iOS APS = development | ✅ Fixed | `Runner.entitlements` → `production` |
| H9 | No screenshot protection | ✅ Fixed | `MainActivity.kt` MethodChannel + `secure_screen.dart` mixin applied to login/signup/reset |
| H10 | Quest-assignment race | ✅ Fixed | `0140` `pg_advisory_xact_lock` per user |
| H11 | Floating Deno imports | ✅ Fixed (code since removed) | all 10 edge functions pinned to `supabase-js` 2.47.10 |
| H12 | GH Actions tag-pinned | ✅ Fixed | SHA-pinned + `permissions: contents: read` on both workflows |

### Medium

| ID | Finding | Status | Where |
|---|---|---|---|
| M1 | R2 MIME header trust | ✅ Fixed | `worker-r2-upload.js` `matchesMagic` |
| M2 | R2 overwrite / quota | ✅ Fixed | per-user object cap + path-component sanitizer |
| M3 | EXIF leakage | ✅ Fixed | `core/security/exif_stripper.dart` wired into avatar + gallery picks |
| M4 | R2 CORS `*` | ✅ Fixed | env-driven allow-list, defaults to `null` |
| M6 | Admin self-demote | ✅ Fixed | explicit block (already there for super_admin, comment expanded) |
| M7 | Account-delete queue SLA | 🔶 Owner action | Add monitor to alert if `account_delete_requests` rows are >24h old |
| M8 | Leaderboard `p_limit` uncapped | ✅ Fixed | `0140` `get_leaderboard` clamps to 100 |
| M9 | FCM token 4096-byte cap | ✅ Fixed | `0140` CHECK constraint 100..300 bytes |
| M10 | Profile `.select('*')` | ✅ Fixed (code since removed) | column allow-list in the legacy `SupabaseProfileRepository` |
| M11 | vote_collab loose rate limit | 🔶 Partial (`0149`) | Cap is now 60/h, **not** the 10/h this item asked for — 10/h assumed one vote per *group*, but the real model is one vote per group *member*, so 10/h throttles normal browsing. Note that `0149` also had to repair a 42P10 defect introduced by `0120` that made **every** `vote_collab` call fail. Still unresolved: `unvote_collab` deletes rows, so the counter is resettable, and no per-user cap stops a multi-account ring. |
| M12 | broadcast 50/user/day | ✅ Fixed | `0149` — global 10/day cap across all admins alongside the per-admin 5/day, plus a real UTC day boundary (`0120` compared a timestamptz against a bare timestamp) |
| M13 | gitignore `*.p8`/`.pem` | ✅ Fixed | added `*.p12 *.pem *.cer *.mobileprovision AuthKey_*.p8` |
| M14 | iOS Firebase delegate proxy | 🔶 Verify | `Info.plist:40` — confirm `bootstrap.dart::initDeferredServices` is wiring FCM manually |
| M15 | `.env.test` real creds | 🔶 Owner action | Rotate test password + move to CI secrets |
| M16 | No Dependabot | ✅ Fixed | `.github/dependabot.yml` added |
| M17 | No obfuscation flag | ✅ Fixed | `CLAUDE.md` build command updated |
| M18 | No GDPR export | ✅ Fixed | `0141` `export_my_data()` RPC |

### Low / Info

| Item | Status | Where |
|---|---|---|
| Age gate at signup | ✅ Fixed | `0142` `age_verified` column + `signup_page.dart` checkbox + `handle_new_user` trigger pass-through |
| Analytics consent | ✅ Fixed (DB) / 🔶 UI | `0142` `analytics_consent_at` column added. Wire `AnalyticsService.init()` to gate on this column. |
| Tamper-proof audit log | ✅ Fixed | `0142` deny-update + deny-delete RLS policies on `admin_audit_log` |
| Privacy policy MENA / Saudi PDPL | 🔶 Owner action | Legal copy; needs review |
| Password regex / disposable email | 🔶 Owner action | Mixed feature/policy choice |
| Mixpanel raw user-id | 🔶 Acceptable | Standard first-party analytics pattern. Can salt-hash if desired |

## Owner action items

Items the codebase can't fix on its own — the owner must take action.

1. **Deploy AASA + assetlinks files** to `https://admin.bsheel.app/.well-known/`. See `docs/deep_links/README.md` for the exact steps.
2. **Rotate the local `.env` service-role key** (Supabase dashboard) if there's any concern the key may have leaked while it was sitting in cleartext on disk. The file is gitignored so the rotation may be precautionary.
3. **Wire Cloudflare Turnstile** on the signup page (H6).
4. **Add a Settings → Privacy toggle** for analytics consent that writes to `profiles.analytics_consent_at` (Low/Info).
5. **Add a monitor** for the `account_delete_requests` queue (M7) — alert if any row has been pending more than 24h.
6. **Translate the privacy policy** into Lebanese Arabizi and add Saudi PDPL / Lebanese DPA clauses.
7. **Move `.env.test` credentials** out of the repo to a CI secret and rotate the password (M15).

Items 8 and 9 of the original list have lapsed. They asked the owner to set
`ALLOWED_UPLOAD_ORIGINS` on the Cloudflare R2 upload worker (M4) and
`ADMIN_ALLOWED_ORIGINS` on the `send-push` and `admin_manage_user` edge
functions. All three components were deleted with the legacy stack; the CORS
allow-list they configured is now the NestJS API's own configuration.

## What changed in the repo (file inventory)

The first group below landed in the legacy `supabase` and `cloudflare` trees,
which have since been deleted from the repository. Those files exist only in
git history — the names are kept so the audit trail is complete, not as
pointers to anything you can open.

```
— removed with the legacy stack —
migration 0140_security_audit_2026_05_17.sql            (new)
migration 0141_gdpr_export.sql                          (new)
migration 0142_age_gate_and_consent.sql                 (new)

edge function admin_manage_user                         (M)
edge function send-push                                 (M)
edge function telegram-webhook                          (M)
edge functions telegram-* and notify-on-insert          (M — pinned imports)

Cloudflare R2 upload worker                             (M — magic bytes, quota, CORS)

— still in the tree —
apps/mobile_app/ios/Runner/Runner.entitlements          (M — APS production)
apps/mobile_app/android/app/src/main/AndroidManifest.xml (M — autoVerify=true)
apps/mobile_app/android/app/src/main/kotlin/.../MainActivity.kt (M — FLAG_SECURE channel)

apps/mobile_app/lib/core/router/app_router.dart         (M — UUID guards on deep-link params)
apps/mobile_app/lib/core/security/secure_screen.dart    (new — mixin)
apps/mobile_app/lib/core/security/exif_stripper.dart    (new — helper)
apps/mobile_app/lib/features/auth/presentation/pages/{login,signup,reset_password}_page.dart (M)
apps/mobile_app/lib/features/profile/presentation/pages/edit_profile_page.dart (M — EXIF strip)
apps/mobile_app/lib/features/submissions/presentation/pages/submit_proof_page.dart (M — EXIF strip)
apps/mobile_app/lib/features/{feed,follows,comments,leaderboard,profile,notifications}/... (M — debugPrint guards)
(legacy) SupabaseProfileRepository                       (M — column allow-list; class removed)

.github/workflows/{ci,format_and_analyze}.yml           (M — SHA-pin + permissions)
.github/dependabot.yml                                  (new)
.gitignore                                              (M — *.p12 *.pem *.cer *.mobileprovision)

docs/deep_links/{README.md,assetlinks.json.template,apple-app-site-association.template} (new)
docs/SECURITY_REMEDIATION_2026_05_17.md                 (new — this file)

CLAUDE.md                                               (M — --obfuscate)
```
