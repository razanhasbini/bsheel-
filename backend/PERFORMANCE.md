# Database performance and scalability audit

Every number in this document was measured with `EXPLAIN (ANALYZE, BUFFERS)`
against a seeded database. Nothing is estimated, extrapolated, or copied from
general advice. Where a finding could not be fixed with an index, the required
source change is written out in SQL; no files under `src/` were touched.

- **Migration added:** `migrations/0015_performance_indexes.sql` — 22 indexes.
- **Seed script added:** `scripts/perf-seed.mjs` — deterministic, re-runnable.
- **Measured on:** PostgreSQL 16.13 (Homebrew, aarch64-apple-darwin),
  `shared_buffers` 128 MB, `work_mem` 4 MB, `maintenance_work_mem` 64 MB,
  `effective_cache_size` 4 GB, `max_connections` 100,
  `superuser_reserved_connections` 3, `random_page_cost` 4, JIT on,
  `max_parallel_workers_per_gather` 2, `track_io_timing` off.
- **Method:** each query run 5 times; the table reports the **median**. The
  test machine was shared with other work, so individual runs contain
  outliers (up to 4x); medians are stable, single samples are not. Any figure
  below where before and after are within ~0.5 ms of each other is noise, and
  is called out as such rather than claimed as a win.

---

## 1. Top findings, ranked by impact

1. **The feed is O(all approved submissions) per page, for every sort mode
   including the default.** `feed.repository.ts:11` joins `profiles`,
   `quests`, a `reactions` aggregate and a two-directional `blocked_users`
   anti-join for **all 22,258** feed-eligible rows before sorting and taking
   20. One page: **587 ms median, 433,614 shared buffer hits**. The
   `ORDER BY` opens with four `CASE WHEN $4 = …` expressions, so even
   `sort=recent` — the DTO default — cannot use the existing
   `submissions_feed_idx (submitted_at DESC, id DESC)` and still top-N sorts
   22,258 rows (392 ms). **No index can fix this**; it needs a source change
   (§5.1). At 20 pool connections this caps one API replica at ~34 feed
   pages/second.

2. **`submissions.user_quest_id`, a foreign key, had no general index.** The
   only index on that column is partial (`WHERE status = 'pending'`). The
   feed's `collab_members` subquery therefore sequentially scanned all 40,000
   submissions *once per returned row*: a `LIMIT 20 OFFSET 500` page did
   702,000 buffer hits in that subplan alone. Fixed: **3,629 ms → 619 ms**
   (5.9x). The following-feed page also improved **189 ms → 53 ms**.

3. **The outbox claim query could not use any index for its ordering.**
   `outbox.publisher.ts:54` orders by `occurred_at`, but
   `outbox_events_pending_idx` leads with `available_at`. Under a 200k-event
   backlog the claim read and sorted the whole pending set —
   `Sort Method: external merge  Disk: 7880kB` — taking **79–136 ms every
   poll**. With `outbox_events_claim_idx`: **0.72–1.49 ms** (>100x). This is
   the highest-leverage index in the set because it protects exactly the
   condition (backlog) in which outbox throughput matters.

4. **Twelve foreign keys had no index on the referencing side**, so every
   `ON DELETE CASCADE`/`SET NULL`/`RESTRICT` probe was a sequential scan.
   `SELECT 1 FROM reactions WHERE user_id = $1` took **14.3 ms**;
   `user_quests WHERE quest_id` **8.5 ms**. Account deletion
   (`domain-events.repository.ts:186`) fires 40 such triggers. Now 0.05–0.19 ms.

5. **Three admin list endpoints scanned and sorted entire tables to return 50
   rows.** `listForAdmin(status=all)` **48.8 ms → 0.47 ms** (104x),
   `admin.users()` **16.6 ms → 0.35 ms** (47x), `admin.notifications()`
   **11.1 ms → 0.20 ms** (56x).

6. **`admin.reports()` joined `submissions.id::text = r.reported_id`.** The
   cast on the indexed side defeated the primary key, forcing a seq scan of
   40k submissions and two of 20k profiles. Expression indexes on `(id::text)`:
   **20.4 ms → 2.4 ms**.

7. **Every list endpoint except notifications uses `LIMIT/OFFSET`.**
   Measured degradation on `listForAdmin`: 0.93 ms at offset 0 → **153.9 ms at
   offset 39,000** (166x), with a disk-spilling `external merge` sort. The feed:
   639 ms at offset 0 → **1,405 ms at offset 10,000** (§8).

8. **`addComment` issues two statements per thread participant.** On a
   100-participant thread that is **200 sequential statements taking 64.4 ms**
   inside one transaction. The equivalent single batched statement:
   **6.28 ms** (10x) (§9).

9. **Connection pool defaults cap the deployment at 2 API + 2 worker
   replicas**, and pool exhaustion queues indefinitely because
   `connectionTimeoutMillis` is not set (§6).

10. **The outbox ceiling is 50 events/s per *API* replica, not per worker** —
    `MessagingModule` is imported by `app.module.ts`, not `worker.module.ts`,
    so scaling workers does not raise drain throughput (§7).

---

## 2. Every query measured

Median of 5 runs, same seeded data, `0015` indexes dropped vs. present.
"Plan after" names the decisive node.

| Query (file:line) | Serves | Plan before | Plan after | Before | After |
|---|---|---|---|---|---|
| `feed.repository.ts:11` `sort=hot scope=all off=0` | Global feed page | Seq Scan submissions → 22,258-row nested loops → top-N heapsort; 319,254 buffers | same shape; subplan seq scan replaced by index scan | 668.53 ms | 586.65 ms |
| `feed.repository.ts:11` `sort=hot scope=all off=500` | Global feed page 26 | + subplan Seq Scan submissions x 520 loops (702k buffers) | Index Scan `submissions_user_quest_idx` in subplan | **3629.30 ms** | **619.41 ms** |
| `feed.repository.ts:11` `sort=recent scope=all` | Default feed page | top-N heapsort over 22,258 rows (index unusable, §5.1) | unchanged shape | 443.46 ms | 391.85 ms |
| `feed.repository.ts:11` `sort=hot scope=following` | Following feed | plan unstable across `ANALYZE` runs: 28.7–328.8 ms | stable Index Scan drive | **188.58 ms** | **53.09 ms** |
| `submissions.repository.ts:298` `status=all off=0` | Admin submissions list | Seq Scan x4 + 3 hash joins + top-N sort of 40k | Index Scan `submissions_admin_list_idx` + 3 pkey loops | **48.82 ms** | **0.47 ms** |
| `submissions.repository.ts:298` `status=all off=20000` | Deep admin page | Gather Merge + `external merge Disk: 5912kB` | same (planner declines index at depth, §8) | 129.71 ms | 99.66 ms |
| `submissions.repository.ts:298` `visibility<>'visible'` | Removed-content view | Seq Scan + hash joins | Index Scan + filter | 8.68 ms | 1.85 ms |
| `submissions.repository.ts:298` `status=pending` | Moderation list | Index Scan `submissions_review_queue_idx` | unchanged | 0.66 ms | 0.84 ms |
| `submissions.repository.ts:216` `reviewQueue` | Review queue + dup detect | Index Scan review_queue + 3 CTEs | + `submissions_user_idx` for stats CTE | 1.43 ms | 1.60 ms |
| `submissions.repository.ts:183` `adminDetail` | One submission for review | all pkey Index Scans | unchanged | 0.22 ms | 0.25 ms |
| `submissions.repository.ts:161` `listUser` | A user's own posts | Index Scan `submissions_user_idx` | unchanged | 0.08 ms | 0.10 ms |
| `social.repository.ts:59` `listComments off=0` | Comment thread (102 rows) | Index Scan `comments_submission_created_idx` | unchanged | 0.99 ms | 0.84 ms |
| `social.repository.ts:59` `listComments off=100` | Thread page 3 | same, 100 rows discarded | same | 1.97 ms | 2.11 ms |
| `social.repository.ts:165` `connections` | Followers list | Index Scan `follows_following_idx` | unchanged | 0.32 ms | 0.20 ms |
| `social.repository.ts:176` `followCounts` | Follower/following counts | Bitmap OR on both follows indexes | unchanged | 0.32 ms | 0.28 ms |
| `social.repository.ts:300` `savedPosts` | Saved posts | Index Scan `saved_posts_user_created_idx` | unchanged | 0.32 ms | 0.48 ms |
| `quests.repository.ts:176` `findActiveForUser` | Home hero zone | Index Scan `user_quests_user_history_idx` | unchanged | 0.09 ms | 0.14 ms |
| `quests.repository.ts:191` `history` | Quest history | Index Scan `user_quests_user_history_idx` | unchanged | 0.15 ms | 0.26 ms |
| `quests.repository.ts:318` `pickerOptions` | Quest roll | Seq Scan quests + Hash Anti Join injections | unchanged (§4, note) | 6.28 ms | 6.75 ms |
| `quests.repository.ts:357` `followingActive` (has follows) | Friend activity | CTE short-circuit, `follows` index-only scan | unchanged | 0.31 ms | 0.48 ms |
| `quests.repository.ts:357` `followingActive` (no follows) | Friend activity fallback | Bitmap `user_quests_expiration_idx` | unchanged | 0.31 ms | 0.44 ms |
| `quests.repository.ts:380` `rerollsRemaining` | Reroll counter | Index Scan `quest_reroll_log_user_time_idx` | unchanged | 0.12 ms | 0.20 ms |
| `leaderboard.repository.ts:10` `scope=global off=0` | Global leaderboard | Seq Scan profiles → full sort 20k → WindowAgg → Sort | unchanged (§5.4) | 19.63 ms | 19.07 ms |
| `leaderboard.repository.ts:10` `scope=global off=10000` | Deep leaderboard | identical (already O(N)) | identical | 16.90 ms | 17.25 ms |
| `leaderboard.repository.ts:10` `scope=following` | Friends leaderboard | Seq Scan profiles + per-row EXISTS | Index Scan `profiles_leaderboard_idx` (pre-existing; planner flip, §3.2) | 5.25 ms | 10.36 ms |
| `admin.repository.ts:29` `stats()` | Admin dashboard | 6 index-only scans + 1 Seq Scan submissions (4.72 ms) | 7 index-only/index scans | 10.15 ms | 7.47 ms |
| `admin.repository.ts:47` `users()` no search | Admin user list | Seq Scan profiles + Seq Scan users + top-N sort | Index Scan `profiles_created_idx` + 50 pkey loops | **16.56 ms** | **0.35 ms** |
| `admin.repository.ts:47` `users()` ILIKE | Admin user search | Hash Join + cross-table OR Join Filter | **plan byte-identical** (§5.3) | 18.93 ms | 22.59 ms |
| `admin.repository.ts:504` `reports()` | Report queue | 3 Seq Scans (40k + 20k + 20k) + 3 hash joins + top-N | Index Scan `reports_created_idx` + `*_id_text_idx` loops | **20.36 ms** | **2.42 ms** |
| `admin.repository.ts:703` `xpAudit()` | XP reconciliation | Seq Scan user_quests + HashAggregate 20k + hash join | Index Only Scan `user_quests_approved_xp_idx` | 20.44 ms | 17.11 ms |
| `admin.repository.ts:728` `notifications()` | Notification log | Seq Scan notifications + hash join 20k profiles + top-N | Index Scan `notifications_admin_feed_idx` | **11.08 ms** | **0.20 ms** |
| `outbox.publisher.ts:54` claim, 1k pending | Outbox drain | Seq Scan + quicksort of 1,000 rows | Index Scan `outbox_events_claim_idx` | 3.75 ms | 1.55 ms |
| `outbox.publisher.ts:54` claim, 200k backlog | Outbox drain under load | Seq Scan 201k + `external merge Disk: 7880kB` | Index Scan, 50 rows, no sort | **86.45 ms** | **0.58 ms** |
| `notifications.repository.ts:16` first page | Notification list | Index Scan `notifications_user_created_idx` | unchanged | 0.03 ms | 0.04 ms |
| `notifications.repository.ts:16` with cursor | Notification page 2+ | same index, keyset seek | unchanged | 0.08 ms | 0.10 ms |
| `notifications.repository.ts:35` `unreadCount` | Bell badge | Index Only Scan `notifications_user_unread_idx` | unchanged | 0.13 ms | 0.27 ms |
| `profiles.repository.ts:68` `xpStats` | Profile rank | Seq Scan profiles for the rank subquery | unchanged (§5.5) | 5.49 ms | 7.49 ms |
| `search.repository.ts:20` users | Search — people | Bitmap `profiles_*_search_idx` (trigram) | unchanged | 1.68 ms | 0.63 ms |
| `search.repository.ts:47` posts | Search — posts | Seq Scan submissions + Seq Scan user_quests + 28k anti-joins | **plan identical** (§5.6) | 156.79 ms | 164.20 ms |
| FK probe `submissions WHERE user_quest_id` | cascade / feed subplan | Seq Scan, 1350 buffers | Index Scan | **6.04 ms** | **0.19 ms** |
| FK probe `reactions WHERE user_id` | cascade on user delete | Seq Scan, 1705 buffers, 150k rows | Index Scan | **14.34 ms** | **0.13 ms** |
| FK probe `comments WHERE user_id` | cascade on user delete | Seq Scan, 1550 buffers, 80k rows | Index Scan | **5.26 ms** | **0.05 ms** |
| FK probe `user_quests WHERE quest_id` | cascade on quest delete | Seq Scan, 829 buffers, 60k rows | Index Scan | **8.54 ms** | **0.12 ms** |
| FK probe `collab_groups WHERE quest_id` | RESTRICT on quest delete | Seq Scan | Index Only Scan | 0.46 ms | 0.08 ms |
| FK probe `saved_quests WHERE quest_id` | cascade on quest delete | Seq Scan | Index Only Scan | 1.05 ms | 0.09 ms |
| FK probe `admin_quest_injections WHERE quest_id` | cascade on quest delete | Seq Scan | Bitmap Index Scan | 0.75 ms | 0.14 ms |

### `DELETE FROM users` (`domain-events.repository.ts:186`), by FK trigger

The account-deletion worker's single statement fires 40 referential-integrity
triggers. Per-trigger times from `EXPLAIN (ANALYZE)` on a representative,
uncontended run:

| Trigger | Before | After |
|---|---|---|
| `submissions_user_quest_id_fkey` (3 calls) | 8.001 ms | 0.232 ms |
| `reactions_user_id_fkey` | 6.798 ms | 1.110 ms |
| `comments_user_id_fkey` | 4.403 ms | 0.992 ms |
| `submissions_reviewed_by_fkey` | 3.841 ms | 0.141 ms |
| `notifications_actor_id_fkey` | 1.935 ms | 0.079 ms |
| `saved_posts_submission_id_fkey` (2 calls) | 0.779 ms | 0.130 ms |
| `reports_reviewed_by_fkey` | 0.332 ms | 0.058 ms |
| `quests_created_by_fkey` | 0.479 ms | 0.590 ms (noise, 2k-row table) |
| `collab_groups_creator_id_fkey` | 0.294 ms | 0.576 ms (noise, 3k-row table) |

Whole-statement totals were too noisy on this shared machine to quote a single
figure: before, 5 runs gave 30.2–123.1 ms (median 32.6); after, 9 runs gave
15.7–103.5 ms (median 24.5). The per-trigger breakdown above is the reliable
evidence — the sequential scans are gone.

---

## 3. Indexes added, and the evidence for each

All 22 are in `migrations/0015_performance_indexes.sql`, each with its
justification in a comment beside it. Total size on the test set: **14 MB**
(largest: `submissions_id_text_idx` 2.3 MB, `reactions_user_idx` 1.7 MB,
`submissions_admin_list_idx` 1.6 MB).

Every one was verified to be *actually chosen by the planner*: after
`pg_stat_reset()` and one pass of the measurement suite plus the cascade
probes, all 22 had `idx_scan > 0` in `pg_stat_user_indexes`
(`submissions_user_quest_idx` alone: 653,125 scans).

### 3.1 Indexes that changed a plan and a timing

| Index | Query it serves | Before → after |
|---|---|---|
| `submissions_user_quest_idx (user_quest_id)` | feed collab subplan; FK cascade | 3629 → 619 ms (feed off500); 6.04 → 0.19 ms (probe) |
| `submissions_admin_list_idx (submitted_at, id)` | `listForAdmin` status=all | 48.82 → 0.47 ms |
| `submissions_approved_recent_idx (submitted_at DESC) WHERE status='approved'` | `stats()` "approved today" | 4.72 → 0.07 ms (subquery) |
| `notifications_admin_feed_idx (created_at DESC)` | `admin.notifications()` | 11.08 → 0.20 ms |
| `profiles_created_idx (created_at DESC, id DESC)` | `admin.users()` | 16.56 → 0.35 ms |
| `reports_created_idx (created_at DESC, id DESC)` + `submissions_id_text_idx ((id::text))` + `profiles_id_text_idx ((id::text))` | `admin.reports()` | 20.36 → 2.42 ms |
| `user_quests_approved_xp_idx (user_id, quest_id) WHERE status='approved'` | `xpAudit()`, `adminDetail` is_retake | 3.45 → 1.18 ms (scan node) |
| `outbox_events_claim_idx (occurred_at) WHERE processed_at IS NULL` | outbox claim | 86.45 → 0.58 ms at 200k backlog |
| `reactions_user_idx (user_id)` | user-delete cascade | 14.34 → 0.13 ms |
| `comments_user_idx (user_id)` | user-delete cascade | 5.26 → 0.05 ms |
| `user_quests_quest_idx (quest_id)` | quest-delete cascade | 8.54 → 0.12 ms |
| `submissions_reviewed_by_idx (reviewed_by) WHERE NOT NULL` | user-delete `SET NULL` | 3.841 → 0.141 ms |
| `notifications_actor_idx (actor_id) WHERE NOT NULL` | user-delete `SET NULL` | 1.935 → 0.079 ms |
| `saved_posts_submission_idx (submission_id)` | submission-delete cascade | 0.779 → 0.130 ms |
| `saved_quests_quest_idx (quest_id)` | quest-delete cascade | 1.05 → 0.09 ms |
| `collab_groups_quest_idx (quest_id)` | quest-delete `RESTRICT` | 0.46 → 0.08 ms |
| `admin_quest_injections_quest_idx (quest_id)` | quest-delete cascade | 0.75 → 0.14 ms |
| `collab_groups_creator_idx`, `quests_created_by_idx`, `reports_reviewed_by_idx` | user-delete cascade/`SET NULL` | within noise at this volume; included because the probe is O(rows) and these tables only grow |

### 3.2 Things I tested and deliberately did **not** add

- **`submissions (submitted_at DESC, id)`** — a DESC twin for
  `listForAdmin(order=desc)`. Not added: with only the ASC index present the
  planner produces an **Incremental Sort** over it and returns in 0.33 ms; the
  dedicated DESC index gave 0.34 ms. No measurable gain, so it is not worth
  the write cost.
- **A trigram index on `users.email`** for `admin.users()` search. Not added:
  the predicate is an `OR` spanning `profiles` and `users`, so PostgreSQL
  cannot reduce it to a single-relation bitmap regardless. Verified by
  diffing the before/after plans — they are byte-identical. This needs a
  source change (§5.3).
- **Anything for the feed's hot-score ordering.** No index can order by a
  runtime-computed expression over a join, and the four leading `CASE`
  expressions in the `ORDER BY` also block the existing
  `submissions_feed_idx`. Source change required (§5.1).
- **Dropping `outbox_events_pending_idx (available_at, occurred_at)`.** It now
  overlaps `outbox_events_claim_idx` and nothing in `src/` queries by
  `available_at` first, but it is cheap (40 kB at 1k pending rows) and
  dropping an index from an applied migration is a behaviour change, not a
  performance fix. Flagged, not done.

### 3.3 Honest regressions

- **`leaderboard following` 5.25 → 10.36 ms.** Not caused by any new index —
  verified by dropping `profiles_created_idx` and re-measuring (no change).
  The `ANALYZE` after index creation flipped the planner from a Seq Scan of
  `profiles` to an Index Scan on the **pre-existing**
  `profiles_leaderboard_idx`. Both plans read all 20,000 profiles; the query
  is O(all users) by construction and needs the rewrite in §5.4.
- **`admin.users()` ILIKE 18.93 → 22.59 ms** and **`search` posts
  156.79 → 164.20 ms**: plans are identical before and after (diffed). These
  are measurement noise on this shared machine, not regressions.
- **Sub-millisecond rows in the table** (`q_history`, `n_unreadCount`,
  `so_savedPosts`, …) move by 0.05–0.15 ms in both directions. Below the noise
  floor; the plans are unchanged.
- **The following feed's plan was unstable before this migration.** Across
  `ANALYZE` runs on identical data it produced anywhere from 28.7 ms to
  328.8 ms, because the planner estimates the collab
  `Filter: (gm.group_id IS NULL OR gm.user_id = g.creator_id)` at **7 rows
  when the actual is 54,000**. With `submissions_user_quest_idx` it settles on
  a stable 50–56 ms. The index bounds the worst case; it does not fix the
  estimate, which is a query-shape problem (§5.1).

---

## 4. Zero-downtime deployment

`scripts/migrate.mjs:52` wraps each migration in `BEGIN`/`COMMIT`, so
`CREATE INDEX CONCURRENTLY` **cannot** appear in `0015` — PostgreSQL forbids it
inside a transaction block. Plain `CREATE INDEX` takes a `SHARE` lock and
blocks writes to the table while it builds (all 22 built in ~0.6 s on the 40k
test set).

To avoid that on a live database, run these **before** deploying the
migration, from a plain `psql` session. `0015` uses `IF NOT EXISTS`
throughout, so it then only records its checksum.

```sql
CREATE INDEX CONCURRENTLY IF NOT EXISTS submissions_user_quest_idx ON submissions (user_quest_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS submissions_admin_list_idx ON submissions (submitted_at, id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS submissions_approved_recent_idx ON submissions (submitted_at DESC) WHERE status = 'approved';
CREATE INDEX CONCURRENTLY IF NOT EXISTS notifications_admin_feed_idx ON notifications (created_at DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS profiles_created_idx ON profiles (created_at DESC, id DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS reports_created_idx ON reports (created_at DESC, id DESC);
CREATE INDEX CONCURRENTLY IF NOT EXISTS submissions_id_text_idx ON submissions ((id::text));
CREATE INDEX CONCURRENTLY IF NOT EXISTS profiles_id_text_idx ON profiles ((id::text));
CREATE INDEX CONCURRENTLY IF NOT EXISTS user_quests_approved_xp_idx ON user_quests (user_id, quest_id) WHERE status = 'approved';
CREATE INDEX CONCURRENTLY IF NOT EXISTS outbox_events_claim_idx ON outbox_events (occurred_at) WHERE processed_at IS NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS reactions_user_idx ON reactions (user_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS comments_user_idx ON comments (user_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS user_quests_quest_idx ON user_quests (quest_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS submissions_reviewed_by_idx ON submissions (reviewed_by) WHERE reviewed_by IS NOT NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS notifications_actor_idx ON notifications (actor_id) WHERE actor_id IS NOT NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS saved_posts_submission_idx ON saved_posts (submission_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS saved_quests_quest_idx ON saved_quests (quest_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS collab_groups_quest_idx ON collab_groups (quest_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS collab_groups_creator_idx ON collab_groups (creator_id);
CREATE INDEX CONCURRENTLY IF NOT EXISTS quests_created_by_idx ON quests (created_by) WHERE created_by IS NOT NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS reports_reviewed_by_idx ON reports (reviewed_by) WHERE reviewed_by IS NOT NULL;
CREATE INDEX CONCURRENTLY IF NOT EXISTS admin_quest_injections_quest_idx ON admin_quest_injections (quest_id);
ANALYZE;
```

Then check for a failed build before deploying — a cancelled
`CREATE INDEX CONCURRENTLY` leaves an invalid index behind that `IF NOT EXISTS`
will happily keep:

```sql
SELECT c.relname FROM pg_class c JOIN pg_index i ON i.indexrelid = c.oid
WHERE NOT i.indisvalid;   -- must be empty; DROP INDEX and retry any row
```

### Write cost

Four of the 22 indexes are on write-hot tables and are the ones to revisit if
insert throughput becomes the constraint:

- `reactions_user_idx` — `reactions` is the highest-write table (every
  vote/unvote). One extra 16-byte index entry per insert.
- `comments_user_idx` — one extra entry per comment.
- `notifications_admin_feed_idx (created_at DESC)` — notifications fan out in
  bursts (`social.repository.ts:340` inserts one per thread participant), and
  every insert lands on the same right-edge index page. It buys 11.08 → 0.20 ms
  on an admin-only screen. If notification insert contention ever shows up in
  `pg_stat_activity`, this is the index to drop first.
- `submissions_admin_list_idx (submitted_at, id)` — submissions are
  low-volume, and `submitted_at` never changes after insert.

---

## 5. Recommendations requiring source changes

None of these were implemented — they are all in `src/`, which this audit did
not touch.

### 5.1 The feed does whole-table work for every page (highest impact)

`feed.repository.ts:11`. Two separate problems.

**(a) The `ORDER BY` blocks every index, including for the default sort.**

```sql
ORDER BY
  CASE WHEN $4 = 'top'  THEN … END DESC NULLS LAST,
  CASE WHEN $4 = 'hot'  THEN … END DESC NULLS LAST,
  CASE WHEN $4 = 'bottom' THEN … END ASC NULLS LAST,
  CASE WHEN $4 = 'graveyard' THEN … END ASC NULLS LAST,
  s.submitted_at DESC, s.id DESC
```

With `$4 = 'recent'` all four `CASE` arms are constant `NULL`, but the planner
cannot know that at plan time, so it cannot match
`submissions_feed_idx (submitted_at DESC, id DESC)`. Measured: 391.85 ms and a
top-N heapsort over 22,258 rows to return 20 recent posts.

Fix: branch in TypeScript on the already-validated `sort` value (the DTO
restricts it to five literals, `feed.dto.ts:7`) and emit one `ORDER BY` per
mode. For `recent` that alone should give an index scan with early
termination. Sketch:

```ts
const ordering = {
  recent:     'ORDER BY s.submitted_at DESC, s.id DESC',
  top:        'ORDER BY net_score DESC, s.submitted_at DESC, s.id DESC',
  bottom:     'ORDER BY net_score ASC,  s.submitted_at DESC, s.id DESC',
  hot:        'ORDER BY hot_score DESC, s.submitted_at DESC, s.id DESC',
  graveyard:  'ORDER BY hot_score ASC,  s.submitted_at DESC, s.id DESC',
}[query.sort];   // closed set, validated by FeedQueryDto — safe to interpolate
```

**(b) The score-ordered modes need denormalised counters.** `hot`, `top`,
`bottom` and `graveyard` must know every row's score before they can pick 20,
so they will always touch all eligible rows — 22,258 rows x (3 index lookups +
a two-branch anti-join) = 433,022 buffer hits, 587 ms. Indexes cannot help.

Fix: keep the counters on the row and index them. `social.repository.ts:15`
already writes reactions inside a transaction, so the counters can be
maintained there or by trigger:

```sql
ALTER TABLE submissions
  ADD COLUMN upvote_count   integer NOT NULL DEFAULT 0,
  ADD COLUMN downvote_count integer NOT NULL DEFAULT 0;

-- hot_score is a pure function of (net score, submitted_at), so it can be
-- generated and indexed:
ALTER TABLE submissions ADD COLUMN net_score integer
  GENERATED ALWAYS AS (upvote_count - downvote_count) STORED;

CREATE INDEX submissions_feed_top_idx
  ON submissions (net_score DESC, submitted_at DESC, id DESC)
  WHERE status = 'approved' AND show_in_feed
    AND visibility = 'visible' AND deleted_at IS NULL;
```

`hot` decays with age, so it cannot be a static index. The standard fix is to
rank a bounded recent window first and join the heavy columns afterwards:

```sql
WITH ranked AS (
  SELECT s.id
  FROM submissions s
  WHERE s.status = 'approved' AND s.show_in_feed
    AND s.visibility = 'visible' AND s.deleted_at IS NULL
    AND s.submitted_at > now() - interval '14 days'
  ORDER BY s.net_score::double precision
           / power(EXTRACT(EPOCH FROM (now() - s.submitted_at)) / 3600.0 + 2.0, 1.5) DESC
  LIMIT $2 OFFSET $3
)
SELECT … FROM ranked JOIN submissions s ON s.id = ranked.id JOIN profiles p … ;
```

That reduces the per-row join and anti-join work from 22,258 rows to `$2`.

**(c) The block anti-join costs two index probes per candidate row.**

```sql
AND NOT EXISTS (
  SELECT 1 FROM blocked_users bu
  WHERE (bu.blocker_id = $1 AND bu.blocked_id = s.user_id)
     OR (bu.blocker_id = s.user_id AND bu.blocked_id = $1))
```

Measured: `BitmapOr` of two `Bitmap Index Scan`s x 22,259 loops = 112,338
buffer hits (~26% of the query). A B-tree cannot satisfy an `OR` of two
composite equalities in one scan. Because the predicate is really "is the
unordered pair {viewer, author} blocked", it collapses to one probe if written
symmetrically:

```sql
-- migration
CREATE INDEX blocked_users_pair_idx ON blocked_users
  (least(blocker_id, blocked_id), greatest(blocker_id, blocked_id));

-- query
AND NOT EXISTS (
  SELECT 1 FROM blocked_users bu
  WHERE least(bu.blocker_id, bu.blocked_id)    = least($1, s.user_id)
    AND greatest(bu.blocker_id, bu.blocked_id) = greatest($1, s.user_id))
```

I did not add `blocked_users_pair_idx`: without the matching query rewrite it
would never be used, and "no speculative indexes" applies. The same pattern
appears in `search.repository.ts:25`, `:72` and
`leaderboard.repository.ts:16`.

**(d) The collab `LEFT JOIN` chain produces a 7,700x row mis-estimate.**
`Hash Left Join … Filter: (gm.group_id IS NULL OR gm.user_id = g.creator_id)`
estimates 7 rows, actual 54,000. That single error is why the following-feed
plan swung between 28 ms and 329 ms across `ANALYZE` runs. Restructuring the
collab lookup as a `LEFT JOIN LATERAL` scoped to `s.user_quest_id` (like the
`reactions` aggregate already is) both fixes the estimate and removes the need
for the `gm.user_id = g.creator_id` post-filter.

### 5.2 `listForAdmin` (and every other list) should use keyset pagination

`submissions.repository.ts:298`. `submissions_admin_list_idx` makes page 1
fast (0.47 ms) but the planner abandons it at depth. Measured curve:

| offset | median |
|---|---|
| 0 | 0.93 ms |
| 500 | 6.31 ms |
| 5,000 | 22.48 ms |
| 20,000 | 105.56 ms |
| 39,000 | **153.88 ms** |

At offset 20,000+ the plan is `Gather Merge → Sort Method: external merge
Disk: 5912kB` — it spills to disk because sorting 40,000 rows of `s.*`
(304 bytes wide) exceeds the 4 MB `work_mem`.

Fix: the same `ChronologicalCursor` already used by
`notifications.repository.ts:16` and `common/pagination/cursor.ts`:

```sql
WHERE ($cursorAt::timestamptz IS NULL
       OR (s.submitted_at, s.id) > ($cursorAt::timestamptz, $cursorId::uuid))
ORDER BY s.submitted_at, s.id
LIMIT $limit
```

This makes every page a fresh index seek — constant cost, no sort, no spill.

### 5.3 `admin.users()` search cannot use the trigram indexes

`admin.repository.ts:47`:

```sql
WHERE ($1::text IS NULL OR lower(p.username::text) LIKE lower($1) ESCAPE '\'
       OR lower(p.display_name)  LIKE lower($1) ESCAPE '\'
       OR lower(u.email::text)   LIKE lower($1) ESCAPE '\')
```

`profiles_username_search_idx` and `profiles_display_name_search_idx` (from
`0002`) are unused because the third disjunct is on a *different table*, so
the whole `OR` becomes a post-join `Join Filter`. Measured: `Rows Removed by
Join Filter: 19,985` — it evaluates the pattern against all 20,000 users.
Adding an index changed nothing (plans diffed identical).

Fix: give email its own trigram index and turn the cross-table `OR` into a
union of single-table searches, so each branch can use its index:

```sql
-- migration
CREATE INDEX users_email_search_idx ON users USING gin (lower(email::text) gin_trgm_ops);
```

```sql
-- repository
WITH matched AS (
  SELECT p.id FROM profiles p
  WHERE lower(p.username::text) LIKE lower($1) ESCAPE '\'
  UNION
  SELECT p.id FROM profiles p
  WHERE lower(p.display_name) LIKE lower($1) ESCAPE '\'
  UNION
  SELECT u.id FROM users u
  WHERE lower(u.email::text) LIKE lower($1) ESCAPE '\'
)
SELECT … FROM profiles p JOIN matched m ON m.id = p.id
JOIN users u ON u.id = p.id LEFT JOIN admins a ON a.user_id = p.id
ORDER BY p.created_at DESC, p.id DESC LIMIT $2 OFFSET $3
```

Note the trigram indexes need a pattern of at least 3 non-wildcard characters
to be selective; short queries will still scan.

### 5.4 The leaderboard ranks every profile to return 50 rows

`leaderboard.repository.ts:10`. Measured 19.07 ms at offset 0 and
17.25 ms at offset 10,000 — *identical*, because the cost is the full
`row_number() OVER (…)` over all 20,000 profiles, not the offset. Two
problems:

1. **The outer `ORDER BY rank` forces full materialisation.** The planner does
   not know `rank` is monotonic, so it adds `Sort (Sort Key: ranked.rank)`
   above the window, which cannot terminate early. Dropping it lets a
   `WindowAgg` over `profiles_leaderboard_idx` stream and stop at
   `OFFSET + LIMIT` — the index `(xp DESC, created_at ASC, id)` already
   matches the window's `ORDER BY` exactly.
2. **`scope=following` drives from `profiles`, not from `follows`.** With the
   index it walks 20,000 index entries to find 6 followed profiles. Inverting
   it (`FROM follows f JOIN profiles p ON p.id = f.following_id WHERE
   f.follower_id = $1`) reads 5 rows via `follows_follower_id_following_id_key`.
   The friends leaderboard then needs its rank computed over that small set,
   which is what the UI shows anyway.

```sql
-- 1: drop the redundant outer sort
SELECT * FROM ranked LIMIT $3 OFFSET $4;   -- was: ORDER BY rank LIMIT … OFFSET …
```

### 5.5 `profiles.xpStats` computes rank with a correlated count

`profiles.repository.ts:68`:

```sql
(SELECT count(*)::integer + 1 FROM profiles ranked
 WHERE ranked.xp > p.xp OR (ranked.xp = p.xp AND ranked.created_at < p.created_at))
```

Measured 7.49 ms — a Seq Scan of all 20,000 profiles for one user's rank, on a
per-profile-view endpoint. The `OR` prevents `profiles_leaderboard_idx` being
used. Splitting it into two index-driven counts fixes that without new
indexes:

```sql
(SELECT count(*) FROM profiles r WHERE r.xp > p.xp)
+ (SELECT count(*) FROM profiles r WHERE r.xp = p.xp AND r.created_at < p.created_at)
+ 1 AS rank
```

If exact rank is not required, cache it — this is the classic case for a
periodically refreshed materialised view.

### 5.6 `search` posts scans two whole tables

`search.repository.ts:47`. Measured 164.20 ms, plan unchanged by any index:
`Seq Scan on submissions` (29,575 rows) hash-joined to `Seq Scan on
user_quests` (60,000 rows), then a `Nested Loop Anti Join` over 28,084 rows for
the block check (112,338 buffers). The cause is the predicate shape:

```sql
AND (s.user_id = $1 OR (q.is_active AND (lower(q.title) LIKE … OR …)))
```

The `s.user_id = $1 OR …` disjunction spans `submissions` and `quests`, so
neither the `quests_*_search_idx` trigram indexes nor `submissions_feed_idx`
can be used. Fix: resolve the matching quest ids in their own CTE first — that
uses the trigram indexes — then join:

```sql
WITH matching_quests AS (
  SELECT id FROM quests
  WHERE is_active AND (lower(title) LIKE lower($2) ESCAPE '\'
                    OR lower(description) LIKE lower($2) ESCAPE '\'
                    OR lower(category) LIKE lower($2) ESCAPE '\')
)
SELECT … FROM submissions s
JOIN user_quests uq ON uq.id = s.user_quest_id
WHERE s.status = 'approved' AND s.visibility = 'visible' AND s.deleted_at IS NULL
  AND (s.user_id = $1 OR uq.quest_id IN (SELECT id FROM matching_quests))
  AND NOT EXISTS (…)
ORDER BY s.submitted_at DESC, s.id DESC LIMIT $3 OFFSET $4
```

### 5.7 `xpAudit` is a whole-table reconciliation

`admin.repository.ts:703`, 17.11 ms after indexing. `LIMIT 50` cannot help:
the `LEFT JOIN` subquery aggregates every approved `user_quest` and the outer
query scans every profile. That is what reconciliation means, so the fix is
operational rather than a query change — run it as a scheduled job writing to
a small `xp_audit_findings` table and have the admin screen read that, or add
`WHERE p.xp <> expected` so only mismatches are returned (it will still scan,
but returns a bounded, actionable set).

### 5.8 Pool and outbox source changes

See §6 and §7.

---

## 6. Connection pool sizing

**How pools are created.** `DatabaseService` (`database.service.ts:14`)
constructs exactly one `pg.Pool` per Nest application context, with
`max = DATABASE_POOL_MAX`. There are two contexts:

- the API process — `main.ts` → `app.module.ts` → `DatabaseModule`
- the worker process — `main.worker.ts` → `worker.module.ts` → `DatabaseModule`

So **each API replica and each worker replica opens its own pool of up to
`DATABASE_POOL_MAX` connections**. Pool size multiplies per process, not per
deployment.

**The arithmetic.** Measured on this server: `max_connections = 100`,
`superuser_reserved_connections = 3` → **97 connections available to the
`bsheel` role**. Defaults (`environment.ts:33-34`) are min 2 / max 20.

| Deployment | Peak connections | Fits in 97? |
|---|---|---|
| 1 API + 1 worker | 40 | yes (57 spare) |
| 2 API + 2 worker | 80 | yes (17 spare) |
| 3 API + 3 worker | 120 | **no** |

Reserve ~5 for `db:migrate` (`migrate.mjs:16` uses `max: 1`), operator `psql`
and monitoring. That leaves **92 usable**, so:

> **Maximum safe replica count at the defaults: 2 API + 2 worker processes.**
> A third pair exceeds `max_connections` and PostgreSQL starts refusing
> connections with `SQLSTATE 53300`.

**Why the failure is not graceful.** `database.service.ts:14` does not set
`connectionTimeoutMillis`, so `node-postgres` defaults to 0 = wait forever.
Once all 20 slot are busy, `pool.connect()` and `pool.query()` queue
indefinitely, with no bound on the queue. Combined with
`DATABASE_STATEMENT_TIMEOUT_MS = 15000` (`environment.ts:36`), a single
pathological query holds its slot for up to 15 s, and 20 such queries stall
every request on that replica for 15 s with no error surfaced to the client
until well past any sensible HTTP timeout.

**Concrete capacity, from the measurements.** The feed page costs 587 ms
median (1,405 ms at offset 10,000). A 20-connection pool therefore sustains
`20 / 0.587 ≈ 34` feed pages/second per API replica, and **14 concurrent feed
requests already occupy 70% of the pool**. The feed fix in §5.1 raises this
ceiling far more than any pool tuning can.

### Recommended values

```env
# API replica (app.module.ts) — HTTP concurrency bound
DATABASE_POOL_MIN=2
DATABASE_POOL_MAX=10

# worker replica (worker.module.ts) — must cover the BullMQ concurrency of 10
# declared at domain-events.processor.ts:18
DATABASE_POOL_MIN=2
DATABASE_POOL_MAX=12
```

22 connections per replica pair → **4 pairs within the 92-connection budget**,
double the current headroom. Then, in order of value:

1. **Set a connection acquisition timeout** in `database.service.ts:14`, below
   the statement timeout, so saturation fails fast as a 503 instead of
   queueing:
   ```ts
   connectionTimeoutMillis: 5_000,
   ```
   Add it to `environment.ts` as `DATABASE_CONNECTION_TIMEOUT_MS`
   (`z.coerce.number().int().positive().default(5_000)`).
2. **Raise `max_connections` to 200** on the server. At these pool sizes the
   per-backend memory cost is small and it buys 8 replica pairs.
3. **Front PostgreSQL with PgBouncer in transaction pooling mode** if replica
   count needs to grow further. This codebase is compatible with transaction
   pooling: no `LISTEN`/`NOTIFY`, no session-level `SET`, no named prepared
   statements, and the one advisory lock (`quests.repository.ts:414`,
   `pg_advisory_xact_lock`) is transaction-scoped by design. Pool sizes then
   stop multiplying with replica count.
4. `DATABASE_POOL_MIN=2` holds 2 connections per process permanently; at 4
   pairs that is 16 idle connections. Acceptable, but set the worker's min to
   0 if replicas are autoscaled aggressively.

---

## 7. Outbox throughput

**Confirmed from the code.** `OutboxPublisher.onApplicationBootstrap`
(`outbox.publisher.ts:27`) starts `setInterval(drain, OUTBOX_POLL_MS)`.
`drain()` (`:38`) is re-entrancy guarded by `this.draining`, claims one batch
via `claimBatch()` (`:51`, `LIMIT $1` = `OUTBOX_BATCH_SIZE`), and then
publishes **sequentially**: `for (const event of events) await this.publish(event)`.
Each `publish()` (`:69`) is one Redis `queue.add` plus one `UPDATE
outbox_events`. Defaults: `OUTBOX_POLL_MS = 1000`,
`OUTBOX_BATCH_SIZE = 50` (`environment.ts:43-44`; the schema allows
250–60000 ms and 1–500).

> **Implied ceiling: 50 events/second per publisher process.**

Two things sharpen that:

- **The publisher runs in the API process, not the worker.** `MessagingModule`
  — the only module providing `OutboxPublisher`
  (`messaging.module.ts:8`) — is imported by `app.module.ts:81`.
  `worker.module.ts` imports only `MessagingQueueModule`. So the aggregate
  ceiling is **50/s x number of API replicas**; scaling *workers* does not
  raise outbox drain throughput at all. `FOR UPDATE SKIP LOCKED`
  (`outbox.publisher.ts:58`) already makes concurrent publishers safe.
- **A slow drain silently lowers the rate below 50/s.** If a cycle exceeds the
  poll interval, the next tick returns immediately from the `draining` guard.
  Before this migration the claim query alone took 79–136 ms under a 200k
  backlog; the 50 sequential publishes add roughly 50 x (Redis round trip +
  one `UPDATE`) — measured at 0.322 ms per single-row statement over loopback,
  so ~30–60 ms. A drain cycle was ~110–200 ms; with
  `outbox_events_claim_idx` the claim is 0.6–1.5 ms, so ~35–65 ms.

### If more than 50/s is needed

In increasing order of change:

1. `OUTBOX_POLL_MS=250` → **200 events/s per replica**. Already permitted by
   the schema; no code change.
2. `OUTBOX_BATCH_SIZE=200` → **200/s at the 1 s interval**, 800/s at 250 ms.
   Also already permitted. `outbox_events_claim_idx` is what makes a larger
   batch cheap — without it, claiming 200 rows means sorting the whole pending
   set.
3. **Publish the batch concurrently** instead of one at a time
   (`outbox.publisher.ts:43`). BullMQ has `queue.addBulk`, and the per-event
   `UPDATE … SET processed_at` can be a single statement over an id array:
   ```ts
   await this.queue.addBulk(events.map((e) => ({
     name: e.event_type, data: e.payload,
     opts: { jobId: e.id, attempts: 8, backoff: { type: 'exponential', delay: 1000 } },
   })));
   await this.database.query(
     'UPDATE outbox_events SET processed_at = now(), last_error = NULL WHERE id = ANY($1::uuid[])',
     [events.map((e) => e.id)],
   );
   ```
   This turns 2N round trips into 2, the same 10x shape measured in §9.
4. **Move `OutboxPublisher` into `worker.module.ts`** so drain capacity scales
   with the worker tier rather than with HTTP capacity, and so a slow drain
   cannot compete with request handling for the API pool.

One caveat worth knowing: `claimBatch` sets `available_at = now() + interval
'30 seconds'` *before* publishing (`outbox.publisher.ts:61`). A claimed event
whose process dies is invisible for 30 s. That is correct for retries but it
means the effective ceiling during a crash-loop is much lower than 50/s.

---

## 8. Keyset vs offset pagination

**Only one endpoint uses a real keyset cursor:**
`notifications.repository.ts:16`, via `ChronologicalCursor`
(`common/pagination/cursor.ts`). Its plan is a bounded index seek —
0.04 ms on page 1 and 0.10 ms with a cursor 5 days deep.

**Every other list endpoint uses `LIMIT/OFFSET`.** Offenders, worst first:

| Endpoint | File:line | Measured degradation |
|---|---|---|
| Admin submissions list | `submissions.repository.ts:304` | 0.93 ms @0 → **153.88 ms @39,000** (166x), spills to disk from offset ~20,000 |
| Global feed | `feed.repository.ts:75` | 639 ms @0 → 858 ms @2,000 → **1,405 ms @10,000** |
| Comment thread | `social.repository.ts:62` | 0.31 ms @0 → 1.02 ms @100 on a 102-comment thread (limit is 200, so ~3x within one thread) |
| Leaderboard | `leaderboard.repository.ts:27` | flat (19.07 @0 vs 17.25 @10,000) — already O(N) for a different reason, §5.4 |
| Quest history | `quests.repository.ts:195` | bounded in practice (~3 rows/user in the test set) |
| Search (users/quests/posts) | `search.repository.ts:31, :43, :77` | posts already 164 ms at offset 0, §5.6 |
| A user's submissions | `submissions.repository.ts:164` | bounded per user |
| Followers/following | `social.repository.ts:168` | bounded per user |
| Blocked users | `social.repository.ts:220` | bounded per user |
| Saved quests / posts | `social.repository.ts:293, :310` | bounded per user |
| Admin reports / injections / notifications / qotd / waitlist / suggestions / xpAudit | `admin.repository.ts:513, :563, :734, :773, :811, :820, :719` | grow without bound with table size |

The first two matter most: the admin list and the feed are the only ones whose
offset can realistically reach five figures, and both degrade
super-linearly. The pattern to copy is already in the repo
(`notifications.repository.ts:25`):

```sql
AND ($3::timestamptz IS NULL OR (n.created_at, n.id) < ($3::timestamptz, $4::uuid))
```

Row-wise comparison on `(sort_column, id)` maps directly onto a two-column
index, so every page costs the same as page 1. The per-user lists are fine as
offsets in practice — a user cannot have 20,000 followers *and* page to the
end — but the admin surfaces have no such bound.

---

## 9. N+1 patterns still present

All of these are inside a single transaction, so each extra round trip also
extends how long a pool connection and its row locks are held.

**1. `social.repository.ts:328` `commentNotifications` — the worst one.**
It fetches thread participants with one query
(`SELECT DISTINCT user_id FROM comments WHERE submission_id = $1`, 0.75 ms,
index-driven) and then loops:

```ts
for (const participant of participants.rows) {   // :340
  await this.notification(participant.user_id, …); // 2 statements each:
}                                                  //   INSERT notifications
                                                   //   INSERT outbox_events
```

Measured on a real 102-comment / 100-participant thread from the seed:

| Approach | Statements | Elapsed |
|---|---|---|
| Current loop | 200 | **64.4 ms** (0.322 ms/statement, loopback TCP) |
| One batched statement | 1 | **6.28 ms** |

**10x, and it is unbounded** — cost grows linearly with thread size, on the
`POST /comments` write path. Over a real network (0.5–1 ms RTT) 200 round
trips is 100–200 ms. The batched form:

```sql
WITH n AS (
  INSERT INTO notifications (user_id, title, body, type, reference_id, actor_id)
  SELECT u, $2, $3, $4, $5, $6 FROM unnest($1::uuid[]) u
  RETURNING id, user_id
)
INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
SELECT 'notification', n.id, 'notification.created',
       jsonb_build_object('notificationId', n.id, 'userId', n.user_id)
FROM n
```

This also removes the per-recipient `actorName` lookup if the actor name is
resolved once outside the loop (it already is, `:329`).

**2. One outbox insert per notification row, in four places.** Each of these
does the bulk `INSERT … SELECT` correctly and then loops to emit events:

- `social.repository.ts:363` — `notifyAdminsOfReport`, one per admin
- `submissions.repository.ts:521` — `notifyAdmins`, one per admin
- `submissions.repository.ts:567` — `notifyCollabPartners`, one per partner
- `collab.repository.ts:133` — one per group member

All four collapse to a single `INSERT … SELECT … FROM` over the `RETURNING`
rows, exactly as above. Admin and collab-group counts are small today
(6 admins, 5 members max per `collab_groups.max_members`), so the current cost
is a few milliseconds — but the fix is the same one line and it removes the
growth-with-admin-count coupling.

**3. `quests.repository.ts:429` `expireOverdueForUser`** loops one outbox
insert per expired assignment. Bounded to 1 row by
`user_quests_one_in_progress_idx`, so harmless; noted only for completeness.

**Not an N+1, worth recording as a positive:** `submissions.repository.ts:216`
`reviewQueue` and `:183` `adminDetail` were clearly written to *avoid* the
client-side N+1 they replaced, and both measure well (1.60 ms and 0.25 ms).
The feed's `collab_members` subquery is a correlated subplan but runs only for
the rows actually returned (20 loops per page), not per candidate row.

---

## 10. Seeding method and row counts

`scripts/perf-seed.mjs` builds the dataset from `generate_series` only, with
identifiers derived from the series index
(`users = 00000000-0000-4000-8000-<n>`, quests `10000000-…`, user_quests
`20000000-…`, submissions `30000000-…`, collab groups `40000000-…`), so
foreign keys need no round trips and the same command always produces the same
data. Every real constraint is respected — enums, `CHECK`s, the partial unique
indexes on `user_quests (user_id) WHERE status IN ('assigned','submitted')` and
`submissions (user_quest_id) WHERE status = 'pending'`, and all uniqueness
pairs.

```bash
export PATH="/opt/homebrew/opt/node@24/bin:$PATH"
cd backend
DATABASE_URL=postgresql://bsheel:bsheel@127.0.0.1:5432/bsheel_agent_h npm run db:migrate
DATABASE_URL=postgresql://bsheel:bsheel@127.0.0.1:5432/bsheel_agent_h node scripts/perf-seed.mjs
# add --truncate to reseed an already-populated database
```

The script runs `ANALYZE` and prints the row counts when it finishes. Total
runtime ~15 s; database size 278 MB.

| Table | Rows | Notes |
|---|---|---|
| `users` | 20,000 | 1 in 997 `suspended` |
| `profiles` | 20,000 | `xp` = `(n * 7919) % 50000`, so leaderboard order is not insertion order |
| `admins` | 6 | 2 `super_admin`, 4 `moderator` |
| `quests` | 2,000 | 1 in 20 inactive; 1 in 3 admin-created (`created_by` set) |
| `user_quests` | 60,000 | 30k approved, 5k rejected, 5k expired, 15k `assigned`, 5k `submitted` — the in-flight ones expire in the future so `followingActive` returns rows |
| `submissions` | 40,000 | 30k approved, 5k rejected, 5k pending; 1 in 101 `hidden_from_feed`, 1 in 211 `deleted`, 1 in 17 `show_in_feed = false`; 22,258 are feed-eligible |
| `reactions` | 150,009 | 0–8 per approved submission (skewed), 75% upvotes, unique per `(submission, user)` |
| `comments` | 80,000 | 60k spread 2/submission + 20k concentrated on 200 "hot" submissions (~102 each), 5,101 replies |
| `follows` | 100,000 | exactly 5 per user, no self-follows |
| `blocked_users` | 5,000 | one per user for users 1–5,000 |
| `notifications` | 20,000 | 6 types, 2/3 with an actor, 25% unread |
| `collab_groups` | 3,000 | creator is always a member, so the feed's `gm.user_id = g.creator_id` filter matches |
| `collab_group_members` | 9,000 | 3 per group, distinct users |
| `collab_votes` | 9,000 | |
| `saved_posts` | 10,000 | |
| `saved_quests` | 5,000 | |
| `admin_quest_injections` | 5,000 | 50 unconsumed; concentrated on 200 of the 2,000 quests so `pickerOptions` still has an eligible pool |
| `reports` | 5,000 | 25% pending; a third reference submissions by `id::text` |
| `outbox_events` | 5,000 | 4,000 processed, 1,000 pending |
| `media_objects` | 20,000 | |
| `admin_audit_log` | 20,000 | |

**Outbox backlog stress test.** The 200k-backlog figures in §1 and §7 come
from temporarily adding unprocessed events on top of the seed:

```sql
INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload,
                           occurred_at, available_at)
SELECT 'notification', gen_random_uuid(), 'notification.created',
       jsonb_build_object('stress', g),
       now() - make_interval(secs => g), now() - make_interval(secs => g)
FROM generate_series(1, 200000) g;
ANALYZE outbox_events;
-- measure, then:
DELETE FROM outbox_events WHERE payload ? 'stress';
VACUUM ANALYZE outbox_events;
```

**Reproducing the before/after numbers.** Seed, then drop the 22 indexes from
`0015`, `ANALYZE`, measure; recreate them, `ANALYZE`, measure again. The
outbox claim mutates rows, so reset it between runs with
`UPDATE outbox_events SET available_at = occurred_at, attempts = 0 WHERE
processed_at IS NULL`.

---

## 11. Verification

```
$ DATABASE_URL=postgresql://bsheel:bsheel@127.0.0.1:5432/bsheel_agent_h npm run db:migrate
Applying 0001_initial_domain_schema.sql
…
Applying 0015_performance_indexes.sql
Database is up to date

$ DATABASE_URL=… npm run db:migrate:check
Migration check passed

$ DATABASE_URL=… npm run db:migrate      # idempotent re-run
Database is up to date
```

22 of 22 indexes present after a migration from an empty database, and all 22
observed with `idx_scan > 0` in `pg_stat_user_indexes` after one pass of the
measurement suite.
