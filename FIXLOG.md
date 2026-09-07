# Fix log

One entry per fix: the symptom, what actually caused it, what changed, and the commit.
Newest first. Check here before debugging anything — if it has happened before, the answer
is already written down.

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
