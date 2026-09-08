-- Performance indexes.
--
-- Every index below was chosen from an EXPLAIN (ANALYZE, BUFFERS) plan
-- captured against a seeded dataset of 20k users / 2k quests / 60k
-- user_quests / 40k submissions / 150k reactions / 80k comments / 100k
-- follows on PostgreSQL 16.13 (shared_buffers 128MB, work_mem 4MB).
-- Timings are the median of 5 runs of the same query on the same data with
-- these indexes dropped vs. present. Full plans, the seeding method and the
-- findings that could NOT be fixed with an index are in backend/PERFORMANCE.md.
-- Nothing speculative is included: every statement here changed a real plan.
--
-- LOCKING NOTE. scripts/migrate.mjs wraps every migration file in a single
-- BEGIN/COMMIT, so CREATE INDEX CONCURRENTLY *cannot* be used here — it is
-- forbidden inside a transaction block. Plain CREATE INDEX takes a SHARE lock
-- and therefore blocks writes to each table while the index builds (all 22
-- built in ~0.6 s total on the 40k-row test set; expect roughly linear
-- growth with table size). Total index size on the test set: 14 MB.
--
-- To deploy against a live database with no write downtime, run the
-- CONCURRENTLY variants listed in PERFORMANCE.md ("Zero-downtime deployment")
-- from a psql session FIRST. Every statement below uses IF NOT EXISTS, so
-- this migration then records its checksum and does nothing.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. submissions.user_quest_id — the only general index on this foreign key
-- ---------------------------------------------------------------------------
-- submissions_one_pending_per_quest_idx covers (user_quest_id) but is partial
-- (WHERE status = 'pending'), so it can serve neither an unqualified lookup
-- nor the ON DELETE CASCADE referential-integrity probe.
--
-- feed.repository.ts:34 — the collab_members correlated subquery joins
--   submissions on user_quest_id. It ran as a Seq Scan over all 40k rows
--   *once per row the feed returns*: 1350 shared buffers x 520 loops =
--   702k buffer hits for one LIMIT 20 OFFSET 500 page.
--   Global hot feed, offset 500: 3629 ms -> 619 ms.
--   Following hot feed, offset 0: 189 ms -> 53 ms.
-- Probe `SELECT 1 FROM submissions WHERE user_quest_id = $1`:
--   6.04 ms (Seq Scan, 1350 buffers) -> 0.19 ms (Index Scan).
-- submissions_user_quest_id_fkey trigger on a cascading user delete:
--   8.001 ms / 3 calls -> 0.232 ms / 3 calls.
CREATE INDEX IF NOT EXISTS submissions_user_quest_idx
  ON submissions (user_quest_id);

-- ---------------------------------------------------------------------------
-- 2. Admin / moderation list ordering
-- ---------------------------------------------------------------------------
-- submissions.repository.ts:298 listForAdmin() with status=all has no WHERE
-- clause at all and orders by (submitted_at, id). Without an index it
-- seq-scanned submissions, profiles, user_quests and quests, built three hash
-- tables and top-N sorted 40k rows.
--   status=all, order=asc, offset 0: 48.8 ms -> 0.47 ms
--   visibility<>'visible', offset 0:  8.68 ms -> 1.86 ms
-- The order=desc variant is served by an Incremental Sort over this same
-- index (0.33 ms), so a separate DESC index is NOT needed — measured, not
-- assumed. Deep offsets still fall back to a disk-spilling sort; that is an
-- offset-pagination problem, see PERFORMANCE.md.
CREATE INDEX IF NOT EXISTS submissions_admin_list_idx
  ON submissions (submitted_at, id);

-- admin.repository.ts:26 stats() subquery 4:
--   count(*) FROM submissions
--   WHERE status = 'approved' AND submitted_at >= now() - interval '24 hours'
-- was a Seq Scan (1350 buffers, 4.72 ms of the statement's total).
-- submissions_feed_idx cannot serve it: that index additionally requires
-- show_in_feed AND visibility = 'visible' AND deleted_at IS NULL.
-- Now an Index Only Scan (0.07 ms). stats(): 10.15 ms -> 7.47 ms.
CREATE INDEX IF NOT EXISTS submissions_approved_recent_idx
  ON submissions (submitted_at DESC)
  WHERE status = 'approved';

-- admin.repository.ts:725 notifications(): Seq Scan on notifications, a full
-- hash join against all 20k profiles, then a top-N sort of 20k rows.
-- 11.08 ms -> 0.198 ms (Index Scan for 50 rows + 50 pkey lookups).
CREATE INDEX IF NOT EXISTS notifications_admin_feed_idx
  ON notifications (created_at DESC);

-- admin.repository.ts:41 users(): ORDER BY p.created_at DESC, p.id DESC over
-- a seq scan of profiles hash-joined to all of users.
-- 16.56 ms -> 0.349 ms.
-- This fixes the unfiltered listing only. The ILIKE search path keeps an
-- identical plan (verified by diffing the plans) because its OR spans
-- profiles and users — see PERFORMANCE.md "Recommendations requiring source
-- changes".
CREATE INDEX IF NOT EXISTS profiles_created_idx
  ON profiles (created_at DESC, id DESC);

-- admin.repository.ts:501 reports(): ORDER BY r.created_at DESC, r.id DESC.
-- Together with the two expression indexes below: 20.36 ms -> 2.42 ms.
CREATE INDEX IF NOT EXISTS reports_created_idx
  ON reports (created_at DESC, id DESC);

-- reports.reported_id is text, so admin.repository.ts:501 joins with
--   reported_submission.id::text = r.reported_id
--   reported_user.id::text       = r.reported_id
-- Casting the indexed side defeats submissions_pkey / profiles_pkey, so the
-- planner seq-scanned all 40k submissions and all 20k profiles (twice) and
-- built three hash tables. These expression indexes restore nested loops:
-- Index Scan using submissions_id_text_idx (0.012 ms x 50 loops) and
-- profiles_id_text_idx (0.014 ms x 50 loops).
CREATE INDEX IF NOT EXISTS submissions_id_text_idx ON submissions ((id::text));
CREATE INDEX IF NOT EXISTS profiles_id_text_idx ON profiles ((id::text));

-- admin.repository.ts:700 xpAudit() aggregates every approved assignment:
-- Seq Scan on user_quests (829 buffers, 3.45 ms) -> Index Only Scan (1.18 ms).
-- Statement 20.44 ms -> 17.11 ms; the remainder is the whole-table
-- reconciliation the query is defined as, see PERFORMANCE.md.
-- The same index serves submissions.repository.ts:192 (adminDetail's
-- is_retake EXISTS on user_id + quest_id + status = 'approved').
CREATE INDEX IF NOT EXISTS user_quests_approved_xp_idx
  ON user_quests (user_id, quest_id)
  WHERE status = 'approved';

-- ---------------------------------------------------------------------------
-- 3. Outbox publisher claim query — the largest single win here
-- ---------------------------------------------------------------------------
-- outbox.publisher.ts:54 orders its claim candidates by occurred_at, but the
-- existing outbox_events_pending_idx leads with available_at and therefore
-- cannot supply that ordering. The claim read and sorted the *entire* pending
-- set on every poll. Measured with a 200k-event backlog — the exact condition
-- under which outbox throughput matters:
--   before: Seq Scan 201k rows + Sort Method: external merge  Disk: 7880kB
--           -> 79.2 / 79.9 / 90.8 / 113.8 / 136.0 ms
--   after:  Index Scan using outbox_events_claim_idx, 50 rows, no sort
--           -> 0.72 / 0.88 / 0.94 / 1.01 / 1.49 ms
-- At the ordinary 5k-row / 1k-pending steady state: 3.75 ms -> 1.55 ms.
-- The `available_at <= now()` predicate stays a cheap filter on the ordered
-- scan and LIMIT 50 terminates it after a few index entries.
CREATE INDEX IF NOT EXISTS outbox_events_claim_idx
  ON outbox_events (occurred_at)
  WHERE processed_at IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Unindexed foreign keys
-- ---------------------------------------------------------------------------
-- PostgreSQL indexes the *referenced* side of a foreign key automatically but
-- never the referencing side, so every ON DELETE CASCADE / SET NULL /
-- RESTRICT probe below was a sequential scan. The per-constraint trigger
-- timings come from EXPLAIN (ANALYZE) DELETE FROM users WHERE id = $1 — the
-- statement the account-deletion worker runs
-- (domain-events.repository.ts:186), which fires 40 FK triggers.

-- reactions_user_id_fkey trigger: 6.798 ms -> 1.110 ms.
-- Probe `SELECT 1 FROM reactions WHERE user_id = $1`:
--   14.34 ms (Seq Scan, 1705 buffers, 150k rows) -> 0.128 ms.
CREATE INDEX IF NOT EXISTS reactions_user_idx ON reactions (user_id);

-- comments_user_id_fkey trigger: 4.403 ms -> 0.992 ms.
-- Probe `SELECT 1 FROM comments WHERE user_id = $1`:
--   5.26 ms (Seq Scan, 1550 buffers, 80k rows) -> 0.049 ms.
CREATE INDEX IF NOT EXISTS comments_user_idx ON comments (user_id);

-- user_quests_quest_id_fkey — ON DELETE CASCADE since 0012, fired by
-- quests.repository.ts delete()/deleteAll().
-- Probe `SELECT 1 FROM user_quests WHERE quest_id = $1`:
--   8.54 ms (Seq Scan, 829 buffers, 60k rows) -> 0.123 ms.
CREATE INDEX IF NOT EXISTS user_quests_quest_idx ON user_quests (quest_id);

-- submissions_reviewed_by_fkey trigger: 3.841 ms -> 0.141 ms.
-- Partial: reviewed_by is NULL for every unreviewed submission and NULL is
-- never the probe target, so those rows do not belong in the index.
CREATE INDEX IF NOT EXISTS submissions_reviewed_by_idx
  ON submissions (reviewed_by)
  WHERE reviewed_by IS NOT NULL;

-- notifications_actor_id_fkey trigger: 1.935 ms -> 0.079 ms.
CREATE INDEX IF NOT EXISTS notifications_actor_idx
  ON notifications (actor_id)
  WHERE actor_id IS NOT NULL;

-- saved_posts_submission_id_fkey trigger: 0.779 ms / 2 calls
--   -> 0.130 ms / 2 calls.
CREATE INDEX IF NOT EXISTS saved_posts_submission_idx
  ON saved_posts (submission_id);

-- saved_quests_quest_id_fkey — quests delete()/deleteAll().
-- Probe `SELECT 1 FROM saved_quests WHERE quest_id = $1`:
--   1.053 ms (Seq Scan) -> 0.093 ms (Index Only Scan).
CREATE INDEX IF NOT EXISTS saved_quests_quest_idx ON saved_quests (quest_id);

-- collab_groups_quest_id_fkey is ON DELETE RESTRICT: quests.delete() must
-- probe it to decide between success and the QUEST_IN_USE conflict.
-- Probe `SELECT 1 FROM collab_groups WHERE quest_id = $1`:
--   0.460 ms (Seq Scan) -> 0.080 ms (Index Only Scan).
CREATE INDEX IF NOT EXISTS collab_groups_quest_idx ON collab_groups (quest_id);

-- admin_quest_injections_quest_id_fkey (ON DELETE CASCADE) — quests.delete().
-- Probe `SELECT 1 FROM admin_quest_injections WHERE quest_id = $1`:
--   0.745 ms (Seq Scan) -> 0.136 ms (Bitmap Index Scan).
-- This index does NOT speed up pickerOptions' NOT EXISTS on the same column:
-- measured 6.28 ms vs 6.76 ms with and without, because the planner uses a
-- Hash Anti Join over the whole table either way. It is here for the cascade
-- probe only.
CREATE INDEX IF NOT EXISTS admin_quest_injections_quest_idx
  ON admin_quest_injections (quest_id);

-- The last three tables are small enough (2k quests, 3k collab_groups, 5k
-- reports) that the trigger timings below are close to measurement noise at
-- the test volume: 0.805 -> 0.642, 2.085 -> 1.015 and 0.332 -> 0.058 ms
-- respectively. They are included because the probe is O(rows) without an
-- index and these tables only grow — quests and reports are append-mostly.
CREATE INDEX IF NOT EXISTS collab_groups_creator_idx
  ON collab_groups (creator_id);

CREATE INDEX IF NOT EXISTS quests_created_by_idx
  ON quests (created_by)
  WHERE created_by IS NOT NULL;

CREATE INDEX IF NOT EXISTS reports_reviewed_by_idx
  ON reports (reviewed_by)
  WHERE reviewed_by IS NOT NULL;

COMMIT;
