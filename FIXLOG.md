# Fix log

One entry per fix: the symptom, what actually caused it, what changed, and the commit.
Newest first. Check here before debugging anything — if it has happened before, the answer
is already written down.

---

## 2026-09-09 — Four first-step CI failures, and a proof agent that asked incoherent questions

**Commits:** `fix/ci-green` (PR #52), `feat/47-ai-proof-verification` (PR #54).

**Symptom.** `main` looked plausible and both CI jobs were red. Every gate
after the first step of each job had never run.

**Root cause.** Four independent first-step failures, which is why they hid:

| Job | Step | Failure |
|---|---|---|
| `backend` | 1. `npm ci` | lockfile missing the transitive `@types/*` closure of `@types/express@5.0.6` |
| `backend` | `db:types:check` | `database.types.ts` drifted for migrations 0023-0024 |
| `analyze-and-test` | 1. `check_secrets.sh` | **false positive** on a documentation placeholder in `legacy-import/ACCESS.md` |
| `analyze-and-test` | `melos run analyze` | 4 lint infos in `map_test.dart` |

Plus 9 files not `dart format` clean. Because `npm ci` and
`check_secrets.sh` are each the *first* step of their job, the two gates
that would have caught the rest were never reached.

**Lesson worth keeping.** Same shape as the 2026-08-30 billing outage below:
a first-step failure makes a whole job's worth of green look like red. Check
*which* step failed before concluding anything about the code. After the four
fixes the tree was fully green — 689 tests.

**The `check_secrets.sh` hit was documentation, and the fix was the document.**
`FIXLOG` already records this exact trap from 2026-09-01, when the guard
caught `FIXLOG.md` itself. The precedent held: fix the illustration, never
loosen the scanner. A guard that fails on documentation teaches people to
skip it, and the last real leak survived in exactly such a window.

### The type-drift gate has now earned its place three times

Migrations 0017-0020 (recorded in `HANDOFF.md`), then 0023-0024, then 0027 —
where it caught me regenerating types *before* adding the migration in the
same session. `database.types.ts` is generated: fix drift with
`npm run db:types`, never by editing it.

### AI proof verification: the design error was asking an unanswerable question

The first implementation was one vision call with a generic prompt. The
defect was not prompt quality. Read the quest catalogue and ask of each
whether a photograph can establish it:

- "Watch the sunrise" — yes, and the capture time corroborates it.
- "Read 20 pages of something difficult" — no. A photo of a book shows no page count.
- **"Spend an hour with no phone" — no. The phone took the photograph.**

Roughly a third of the catalogue cannot be checked from an image at all. A
model asked to verify one of those answers anyway, with a confidence score
attached — which is how an automated reviewer confidently rejects an honest
player. Prompt tuning cannot fix an incoherent question.

The fix is a per-quest verification contract, so the agent is told what its
evidence can settle, and for the unverifiable third no vision call is made.
Writing the seed data caught a live instance of the same error in my own
work: I had marked `fitness` auto-rejectable, which would have let the agent
reject "take a 30 minute walk somewhere new" for failing to prove a duration
no photograph can show.

**Two traps in the forensics layer, both of which would have hurt real users.**
EXIF `DateTimeOriginal` is local wall-clock with **no timezone**: a truthful
player in Apia (UTC+13) writes a capture time that reads as ten hours before
a UTC assignment. A naive comparison accuses honest players across half the
world, so the window is widened by the maximum UTC offset unless EXIF carries
one — deliberately trading sensitivity, because missing a lazy cheat is far
cheaper than calling a truthful player a liar. And `etag` is not a content
hash: S3/R2 set it to the body MD5 only for single-part uploads, so comparing
etags would silently stop matching on exactly the large files most likely to
be recycled. Hence `media_objects.content_md5`.

**Also found:** `seed-local.mjs` uploaded proof bytes to storage and never
created the `media_objects` rows the real upload flow creates, so the table
was empty locally and everything reading media metadata — forensics, the
media quota, the orphan reclaim — saw nothing and silently did nothing.

**Trap for whoever writes the next capability-gated suite.** `it.runIf` is
evaluated at collection time, before `beforeAll` runs, so a flag set in a
hook is still false when the guard reads it and every case silently skips. A
suite that skips itself looks exactly like a suite that passes.

---

## 2026-09-08 — Supabase removed from both clients; six latent defects surfaced

**Commit:** this session.

**What changed.** The applications now talk to exactly one backend. The
dual-mode strangler machinery is gone: 60 `BackendConfig.usesNest` branches
across 36 files, 16 `Supabase*Repository` implementations (1,634 lines), both
`supabase_provider.dart` files, the override lists, and the
`supabase_flutter` dependency itself. All 61 files that reached Supabase
directly were ported to the API. All seven packages analyse with zero issues.

**The load-bearing piece was the auth contract.** `AuthRepository` — the
*interface* — was typed entirely in Supabase types (`AuthState`,
`AuthResponse`, `UserResponse`, `User`), so `ApiAuthRepository` was
fabricating Supabase objects out of our own JSON just to satisfy it. That is
why the dependency could not simply be dropped. It was replaced with a plain
Dart auth model (`AuthUser`, `AuthSession`, `AuthState`, `AuthResult`,
`AuthException`) whose member names match what the UI already read, so most
call sites needed only an import change.

### Defects found on the way, none of them visible from the code alone

| Defect | Why nobody saw it |
|---|---|
| `npm run test:e2e` could not run: `vitest.config.e2e.ts` imported `vite-tsconfig-paths`, which is declared nowhere — not in `package.json`, not in the lockfile | `ci.yml` ran lint, test and build, but never `test:e2e`. The suite it would have run was still the Nest scaffold's `GET / → "Hello World!"`, which this app could never answer |
| The env schema rejected an empty optional variable, so the documented `cp backend/.env.example backend/.env` produced a config the app refused to boot with | `.env.example` ships `EMAIL_DELIVERY_WEBHOOK_URL=` empty, and `z.string().url().optional()` rejects `''` — `.optional()` only permits `undefined` |
| `admin_web` did not compile: `repositories.profile` where the bundle exposes `profiles` | The last recorded checkpoint claimed "admin analysis with zero issues". It was stale |
| Registration collapsed both conflicts into one `ACCOUNT_CONFLICT`, so the signup form could not tell which field to blame | Legacy routed a taken username and an already-registered email to *different* inputs. Now `EMAIL_TAKEN` / `USERNAME_TAKEN`, distinguished by the violated constraint name |
| `app_config` was created but **never seeded**, so `GET /config` returned nothing: the force-update gate had no row to read and the social-login kill switch defaulted to ON when absent | The rotation runbook had already flagged this as "wired up and disconnected", and as fail-open on a kill switch. Migration `0014` seeds the six public keys; the client now requires an explicit `'true'` |
| 109 of 258 Dart files were not `dart format` clean, so `format_and_analyze.yml` could not have passed | Consistent with the Actions-billing history below — nobody saw it fail. The `require_trailing_commas` lint also *contradicts* the formatter that CI enforces, so no tree could satisfy both. The lint is now removed and the formatter owns comma placement |

**CI now runs what it claimed to.** The backend job gained Postgres 17 and
Redis 7.4 service containers, a migration replay from an empty database, the
checksum ledger check, and the integration suite.

**Lesson worth keeping.** `flutter analyze` passing is not the same as
compiling. Leftover `RealtimeChannel?` field declarations analysed clean and
failed the moment `flutter test` actually built the app, because the analyzer
was resolving against a cached package graph. Run the tests, not just the
analyzer.

**Second lesson, the same trap the migration docs warn about.** While checking
whether `quest_suggestions` was missing its `category` column, reading only
`0001_initial_domain_schema.sql` said yes. Migration `0005` adds it. Never
conclude from the first definition of a table or function — read every later
one.

---

## 2026-09-01 — Six production bugs sat fixed-but-unmerged for four weeks

**Commit:** `b15697d` (merge of PR #56, branch `fix/prod-repairs-and-secret-guard`)

**Symptom.** Nothing looked wrong. `main` was green-ish, the app was up, and the repo tip
carried no obvious defect. The bugs were all in live database state, and the fixes existed —
on a branch, opened 2026-08-04, never merged.

**Root cause of the *delay* (the real bug here).** GitHub Actions ran out of budget on
2026-08-30 at 14:26 UTC. From then on every workflow was refused a runner: `conclusion:
failure`, 2-4 seconds, `steps: []` — a red X that looks exactly like a failing test. Because
`deploy-server.yml` is the only automated path to `api.bsheel.app`, the deploy had been dead for
two days and nobody could tell from the check mark alone. The budget reset on 2026-09-01 (Actions
minutes reset on the 1st), which is the only reason the merge deployed itself.

**What the merge actually fixed, verified against the live database after deploy:**

| Bug | Before | After |
|---|---|---|
| `expire_overdue_quests` guard used `current_user`, which `SECURITY DEFINER` rewrites to the owner | 287 failed cron runs; last failures 10:40/10:45/10:50 `ERROR: Not authorized` | succeeded 10:55 and 11:00 |
| 14 users stuck on one assigned quest since 2026-05-04 | could not roll a new quest | `0 still stuck`; backfilled silently — only 4 notifications since, all admin reminders, no 3-month-late expiry spam |
| `send_pending_review_reminders` queried `submissions.created_at`, which does not exist | failed every hour for 24h, had never once succeeded | succeeded 11:00 — first successful run ever |
| `app_config` SELECT restricted to `authenticated` in 0140, client never updated | RLS-denied SELECT returns `200 []`, so logged-out clients read every flag as absent and **failed open** — social-login kill-switch inert, force-update gate bypassable by signing out | logged-out HTTPS call to `api.bsheel.app` now returns `social_login_enabled: false` |
| `PUBLIC`/`anon` still held EXECUTE on `expire_overdue_quests` | an anonymous caller could mass-expire everyone's quests | `permission denied for function expire_overdue_quests`; grantees are now `postgres, service_role` only |
| Live `service_role` JWT (exp 2036) committed in `docs/api/…postman_collection.json` since `6520808` | on `origin/main`, bypassing all RLS over the public internet | removed from the tip — **still in git history, still compromised until `JWT_SECRET` is rotated** |

**Lesson worth keeping.** A CI failure caused by billing is indistinguishable at a glance from a
CI failure caused by code. The tell is the shape: every workflow failing, in seconds, with zero
steps executed. Check `steps: []` before debugging the code.

**Related:** rotation plan in `docs/security/SECRET_ROTATION_RUNBOOK.md` (`b2f3bbe`).

---

## 2026-09-01 — The secret guard was never proven to catch anything

**Commit:** none — no code change needed. Recorded so it is not re-litigated.

**Symptom.** `scripts/check_secrets.sh` arrived with PR #56 and printed
`OK — no privileged JWT` against the merged tree. That proves nothing: a scanner that always
prints OK also prints OK.

**What was done.** Fed it a synthetic (fake, self-signed) `service_role` JWT, a
`supabase_admin` one, and a remote Postgres connection URI carrying an inline password.
All three were caught, exit 1. Removed them; it returned to exit 0 while still holding
the public `anon` key, which it correctly ignores. Both halves proven — it blocks the bad case and allows the good one.

**A trap for whoever tests it next.** The first attempt reported a false failure. `base64`
wraps at 76 columns, so a synthetic token built with plain `base64` is split across two lines
and the guard's single-line regex never matches it — the guard was fine, the test was not.
Use `base64 -w0`.

**It then caught this very file.** The first draft of the entry above quoted a literal example
connection URI, and CI run 33501175014 failed on `FIXLOG.md`. The guard cannot tell an
illustration from a leak, and should not try to - write about credential formats without
reproducing them.

**Still open:** the guard runs only as a CI step, so it is inert whenever Actions is out of
budget — which is exactly the window in which the last leak survived.
