// Deterministic performance seed for the Bsheel schema.
//
// Every row is derived from generate_series, so the same DATABASE_URL always
// produces byte-identical data and the EXPLAIN numbers in PERFORMANCE.md are
// reproducible. Identifiers are synthesised from the series index
// (users = 00000000-0000-4000-8000-<n>, quests = 10000000-..., user_quests =
// 20000000-..., submissions = 30000000-..., collab groups = 40000000-...)
// so foreign keys can be wired without extra round trips.
//
// Usage:
//   DATABASE_URL=postgresql://... node scripts/perf-seed.mjs
//   DATABASE_URL=postgresql://... node scripts/perf-seed.mjs --truncate
//
// Target volumes (see PERFORMANCE.md "Seeding method"):
//   users/profiles 20k, quests 2k, user_quests 60k, submissions 40k,
//   reactions ~150k, comments 80k, follows 100k, blocked_users 5k,
//   notifications 20k, outbox_events 5k, plus collab + saved + reports.
import process from 'node:process';
import pg from 'pg';

const { Pool } = pg;
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

const USERS = 20_000;
const QUESTS = 2_000;
// user_quests layout, by series index g:
//   1..30000      approved  (finished, feed-eligible submissions hang off these)
//   30001..35000  rejected
//   35001..40000  expired
//   40001..55000  assigned  (one per user 1..15000 - partial unique index)
//   55001..60000  submitted (one per user 15001..20000 - partial unique index)
const USER_QUESTS = 60_000;
const APPROVED_UQ = 30_000;
const COLLAB_GROUPS = 3_000;

const uuid = (prefix, expression) =>
  `('${prefix}-0000-4000-8000-' || lpad((${expression})::text, 12, '0'))::uuid`;
const userId = (expression) => uuid('00000000', expression);
const questId = (expression) => uuid('10000000', expression);
const userQuestId = (expression) => uuid('20000000', expression);
const submissionId = (expression) => uuid('30000000', expression);
const groupId = (expression) => uuid('40000000', expression);

const steps = [
  [
    'users',
    `INSERT INTO users (id, email, password_hash, email_verified_at, status, created_at)
     SELECT ${userId('g')},
            'perf' || g || '@perf.test',
            '$argon2id$v=19$m=65536,t=3,p=4$c2VlZHNlZWRzZWVk$0000000000000000000000000000000000000000000',
            now() - make_interval(mins => g),
            CASE WHEN g % 997 = 0 THEN 'suspended'::account_status ELSE 'active'::account_status END,
            now() - make_interval(mins => g)
     FROM generate_series(1, ${USERS}) g`,
  ],
  [
    'profiles',
    `INSERT INTO profiles (id, username, display_name, bio, xp, level, quests_completed,
                           profile_completed, age_verified, accepted_terms_at, created_at)
     SELECT ${userId('g')},
            'perfuser' || g,
            'Perf ' || (ARRAY['Ada','Grace','Linus','Rob','Barbara','Ken','Margaret','Alan'])[1 + (g % 8)] || ' ' || g,
            'Seeded profile ' || g || ' for the performance audit.',
            (g * 7919) % 50000,
            (((g * 7919) % 50000) / 100) + 1,
            g % 40,
            true,
            true,
            now() - make_interval(mins => g),
            now() - make_interval(mins => g)
     FROM generate_series(1, ${USERS}) g`,
  ],
  [
    'admins',
    `INSERT INTO admins (user_id, role)
     SELECT ${userId('g')},
            CASE WHEN g <= 2 THEN 'super_admin'::admin_role ELSE 'moderator'::admin_role END
     FROM generate_series(1, 6) g`,
  ],
  [
    'quests',
    `INSERT INTO quests (id, title, description, category, difficulty, xp_reward,
                         duration_hours, is_active, created_by, created_at)
     SELECT ${questId('g')},
            (ARRAY['Photograph','Cook','Run','Draw','Build','Record','Interview','Repair'])[1 + (g % 8)]
              || ' something ' || (ARRAY['blue','loud','tiny','ancient','borrowed'])[1 + (g % 5)] || ' #' || g,
            'Seeded quest ' || g || '. ' || repeat('Do the thing and photograph it. ', 4),
            (ARRAY['fitness','food','art','social','outdoors','music','tech','random'])[1 + (g % 8)],
            (ARRAY['easy','medium','hard'])[1 + (g % 3)],
            10 + (g % 200),
            1 + (g % 24),
            g % 20 <> 0,
            CASE WHEN g % 3 = 0 THEN ${userId('1 + (g % 6)')} ELSE NULL END,
            now() - make_interval(hours => g)
     FROM generate_series(1, ${QUESTS}) g`,
  ],
  [
    'user_quests',
    `INSERT INTO user_quests (id, user_id, quest_id, status, assigned_at, completed_at, expires_at)
     SELECT ${userQuestId('g')},
            CASE WHEN g <= 40000 THEN ${userId('1 + (g % ' + USERS + ')')} ELSE ${userId('g - 40000')} END,
            ${questId('1 + ((g * 31) % ' + QUESTS + ')')},
            CASE
              WHEN g <= 30000 THEN 'approved'::user_quest_status
              WHEN g <= 35000 THEN 'rejected'::user_quest_status
              WHEN g <= 40000 THEN 'expired'::user_quest_status
              WHEN g <= 55000 THEN 'assigned'::user_quest_status
              ELSE 'submitted'::user_quest_status
            END,
            -- assigned_at: finished assignments are spread back over ~28 days,
            -- in-flight ones (g > 40000) sit inside the last ~3 hours so their
            -- expires_at is still in the future for followingActive.
            CASE WHEN g <= 40000
                 THEN now() - make_interval(mins => g)
                 ELSE now() - make_interval(mins => g % 200)
            END,
            CASE WHEN g <= 30000 THEN now() - make_interval(mins => g) + interval '2 hours' ELSE NULL END,
            CASE WHEN g <= 40000
                 THEN now() - make_interval(mins => g) + interval '4 hours'
                 ELSE now() - make_interval(mins => g % 200) + interval '4 hours'
            END
     FROM generate_series(1, ${USER_QUESTS}) g`,
  ],
  [
    'submissions (approved + rejected)',
    `INSERT INTO submissions (id, user_quest_id, user_id, media_url, media_type, caption, status,
                              reviewed_by, submitted_at, reviewed_at, appealed, show_in_feed,
                              visibility, xp_awarded, xp_awarded_amount)
     SELECT ${submissionId('g')},
            ${userQuestId('g')},
            ${userId('1 + (g % ' + USERS + ')')},
            -- 3% of rejected rows deliberately reuse a media_url so the
            -- review-queue duplicate detector has real work to do.
            CASE WHEN g > 30000 AND g % 31 = 0
                 THEN 'https://media.perf.test/dupe/' || (g % 50) || '.jpg'
                 ELSE 'https://media.perf.test/perf/' || g || '.jpg'
            END,
            (ARRAY['image','video','mixed'])[1 + (g % 3)]::media_type,
            'Seeded caption for submission ' || (CASE WHEN g % 37 = 0 THEN (g % 90)::text ELSE g::text END)
              || ' with enough characters to trip the duplicate rule.',
            CASE WHEN g <= 30000 THEN 'approved'::submission_status ELSE 'rejected'::submission_status END,
            ${userId('1 + (g % 6)')},
            now() - make_interval(mins => g),
            now() - make_interval(mins => g) + interval '20 minutes',
            g % 53 = 0,
            g % 17 <> 0,
            CASE
              WHEN g % 101 = 0 THEN 'hidden_from_feed'::submission_visibility
              WHEN g % 211 = 0 THEN 'deleted'::submission_visibility
              ELSE 'visible'::submission_visibility
            END,
            g <= 30000,
            CASE WHEN g <= 30000 THEN 10 + (g % 200) ELSE 0 END
     FROM generate_series(1, 35000) g`,
  ],
  [
    'submissions (pending review queue)',
    `INSERT INTO submissions (id, user_quest_id, user_id, media_url, media_type, caption, status,
                              submitted_at, appealed, show_in_feed, visibility)
     SELECT ${submissionId('g')},
            ${userQuestId('g')},
            ${userId('g - 40000')},
            'https://media.perf.test/pending/' || g || '.jpg',
            'image'::media_type,
            'Pending submission ' || g || ' awaiting moderation review.',
            'pending'::submission_status,
            now() - make_interval(mins => g % 4000),
            g % 23 = 0,
            true,
            'visible'::submission_visibility
     FROM generate_series(55001, 60000) g`,
  ],
  [
    'reactions',
    `INSERT INTO reactions (submission_id, user_id, type, created_at)
     SELECT ${submissionId('i')},
            ${userId('1 + ((i * 7 + j * 6001) % ' + USERS + ')')},
            CASE WHEN (i + j) % 4 = 0 THEN 'downvote'::reaction_type ELSE 'upvote'::reaction_type END,
            now() - make_interval(mins => i) + make_interval(mins => j)
     FROM generate_series(1, ${APPROVED_UQ}) i,
          LATERAL generate_series(0, (i * 7919) % 9) j`,
  ],
  [
    'comments',
    `INSERT INTO comments (submission_id, user_id, body, created_at)
     SELECT ${submissionId('1 + (g % ' + APPROVED_UQ + ')')},
            ${userId('1 + ((g * 4409) % ' + USERS + ')')},
            'Seeded comment ' || g || ' saying something moderately supportive.',
            now() - make_interval(mins => g % 30000)
     FROM generate_series(1, 60000) g`,
  ],
  [
    'comments (hot threads)',
    `INSERT INTO comments (submission_id, user_id, body, created_at)
     SELECT ${submissionId('1 + (g % 200)')},
            ${userId('1 + ((g * 3571) % ' + USERS + ')')},
            'Hot thread comment ' || g,
            now() - make_interval(secs => g)
     FROM generate_series(1, 20000) g`,
  ],
  [
    'comments (replies)',
    `UPDATE comments c
     SET parent_id = parent.id
     FROM (
       SELECT c2.id, c2.submission_id,
              first_value(c2.id) OVER (PARTITION BY c2.submission_id ORDER BY c2.created_at, c2.id) AS root
       FROM comments c2
     ) parent
     WHERE parent.id = c.id AND parent.root <> c.id AND hashtext(c.id::text) % 10 = 0`,
  ],
  [
    'follows',
    `INSERT INTO follows (follower_id, following_id, created_at)
     SELECT ${userId('i')},
            ${userId('1 + ((i + j * 3571) % ' + USERS + ')')},
            now() - make_interval(mins => i + j)
     FROM generate_series(1, ${USERS}) i,
          LATERAL generate_series(1, 5) j`,
  ],
  [
    'blocked_users',
    `INSERT INTO blocked_users (blocker_id, blocked_id, created_at)
     SELECT ${userId('i')},
            ${userId('1 + ((i + 9001) % ' + USERS + ')')},
            now() - make_interval(mins => i)
     FROM generate_series(1, 5000) i`,
  ],
  [
    'notifications',
    `INSERT INTO notifications (user_id, actor_id, title, body, type, reference_id, is_read, created_at)
     SELECT ${userId('1 + (g % ' + USERS + ')')},
            CASE WHEN g % 3 = 0 THEN NULL ELSE ${userId('1 + ((g * 13) % ' + USERS + ')')} END,
            'Seeded notification ' || g,
            'Something happened on the platform that you may care about (' || g || ').',
            (ARRAY['new_follower','reaction_received','new_comment','quest_assigned','mention','comment_reply'])[1 + (g % 6)],
            ${submissionId('1 + (g % ' + APPROVED_UQ + ')')},
            g % 4 <> 0,
            now() - make_interval(mins => g)
     FROM generate_series(1, 20000) g`,
  ],
  [
    'collab_groups',
    `INSERT INTO collab_groups (id, quest_id, creator_id, code, mode, status, max_members, expires_at, created_at)
     SELECT ${groupId('i')},
            ${questId('1 + ((i * 31) % ' + QUESTS + ')')},
            ${userId('1 + ((3 * (i - 1) + 1) % ' + USERS + ')')},
            'PERF' || lpad(i::text, 6, '0'),
            CASE WHEN i % 2 = 0 THEN 'with'::collab_mode ELSE 'versus'::collab_mode END,
            CASE WHEN i % 5 = 0 THEN 'open'::collab_status ELSE 'completed'::collab_status END,
            5,
            now() - make_interval(mins => i) + interval '6 hours',
            now() - make_interval(mins => i)
     FROM generate_series(1, ${COLLAB_GROUPS}) i`,
  ],
  [
    'collab_group_members',
    `INSERT INTO collab_group_members (group_id, user_id, user_quest_id, joined_at, submission_time_seconds)
     SELECT ${groupId('1 + ((g - 1) / 3)')},
            ${userId('1 + (g % ' + USERS + ')')},
            ${userQuestId('g')},
            now() - make_interval(mins => g),
            600 + (g % 3000)
     FROM generate_series(1, ${COLLAB_GROUPS * 3}) g`,
  ],
  [
    'collab_votes',
    `INSERT INTO collab_votes (group_id, voter_id, submission_id, created_at)
     SELECT ${groupId('1 + ((g - 1) / 3)')},
            ${userId('1 + ((g * 17) % ' + USERS + ')')},
            ${submissionId('g')},
            now() - make_interval(mins => g)
     FROM generate_series(1, ${COLLAB_GROUPS * 3}) g`,
  ],
  [
    'saved_posts',
    `INSERT INTO saved_posts (user_id, submission_id, created_at)
     SELECT ${userId('i')},
            ${submissionId('1 + ((i * 7 + j * 5003) % ' + APPROVED_UQ + ')')},
            now() - make_interval(mins => i + j)
     FROM generate_series(1, 5000) i, LATERAL generate_series(1, 2) j`,
  ],
  [
    'saved_quests',
    `INSERT INTO saved_quests (user_id, quest_id, created_at)
     SELECT ${userId('i')},
            ${questId('1 + ((i * 11) % ' + QUESTS + ')')},
            now() - make_interval(mins => i)
     FROM generate_series(1, 5000) i`,
  ],
  [
    'admin_quest_injections',
    // The partial unique index allows only one unconsumed injection per user,
    // so all but 50 rows are marked consumed. pickerOptions' NOT EXISTS
    // ignores consumed_at, so every row still participates in that anti-join;
    // the rows are concentrated on 200 of the 2000 quests so the picker still
    // has an eligible pool to choose from (spreading them over all 2000 makes
    // every quest ineligible and the measurement degenerate).
    `INSERT INTO admin_quest_injections (target_user_id, quest_id, created_by, consumed_at, created_at)
     SELECT ${userId('g')},
            ${questId('1 + ((g * 13) % 200)')},
            ${userId('1 + (g % 6)')},
            CASE WHEN g > 50 THEN now() - make_interval(mins => g) + interval '1 minute' ELSE NULL END,
            now() - make_interval(mins => g)
     FROM generate_series(1, 5000) g`,
  ],
  [
    'reports',
    `INSERT INTO reports (reporter_id, reported_type, reported_id, reason, status, created_at)
     SELECT ${userId('1 + (g % ' + USERS + ')')},
            (ARRAY['submission','comment','user'])[1 + (g % 3)],
            CASE (g % 3)
              WHEN 0 THEN (${submissionId('1 + (g % ' + APPROVED_UQ + ')')})::text
              WHEN 1 THEN gen_random_uuid()::text
              ELSE (${userId('1 + ((g * 19) % ' + USERS + ')')})::text
            END,
            'Seeded report reason ' || g,
            CASE WHEN g % 4 = 0 THEN 'pending' ELSE 'reviewed' END,
            now() - make_interval(mins => g)
     FROM generate_series(1, 5000) g
     ON CONFLICT DO NOTHING`,
  ],
  [
    'outbox_events',
    `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload,
                                occurred_at, available_at, attempts, processed_at)
     SELECT 'notification',
            ${submissionId('1 + (g % ' + APPROVED_UQ + ')')},
            (ARRAY['notification.created','social.reaction.changed','social.comment.changed','quest.assigned'])[1 + (g % 4)],
            jsonb_build_object('seed', g),
            now() - make_interval(secs => g),
            now() - make_interval(secs => g),
            CASE WHEN g > 4000 THEN g % 3 ELSE 1 END,
            CASE WHEN g <= 4000 THEN now() - make_interval(secs => g) + interval '1 second' ELSE NULL END
     FROM generate_series(1, 5000) g`,
  ],
  [
    'media_objects',
    `INSERT INTO media_objects (user_id, client_request_id, object_key, kind, status,
                                content_type, declared_size_bytes, stored_size_bytes, created_at, completed_at)
     SELECT ${userId('1 + (g % ' + USERS + ')')},
            gen_random_uuid(),
            'perf/media/' || g || '.jpg',
            CASE WHEN g % 5 = 0 THEN 'avatar'::media_object_kind ELSE 'submission'::media_object_kind END,
            CASE WHEN g % 23 = 0 THEN 'pending'::media_object_status ELSE 'ready'::media_object_status END,
            'image/jpeg',
            250000 + g,
            250000 + g,
            now() - make_interval(mins => g),
            now() - make_interval(mins => g) + interval '10 seconds'
     FROM generate_series(1, 20000) g`,
  ],
  [
    'admin_audit_log',
    `INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, after_state, created_at)
     SELECT ${userId('1 + (g % 6)')},
            (ARRAY['submission.approve','submission.reject','user.set_status','quest.create'])[1 + (g % 4)],
            'submission',
            (${submissionId('1 + (g % ' + APPROVED_UQ + ')')})::text,
            jsonb_build_object('seed', g),
            now() - make_interval(mins => g)
     FROM generate_series(1, 20000) g`,
  ],
];

const truncate = `TRUNCATE admin_quest_injections, admin_audit_log, media_objects, outbox_events, reports, saved_quests,
  saved_posts, collab_votes, collab_group_members, collab_groups, notifications,
  blocked_users, follows, comments, reactions, submissions, user_quests, quests,
  admins, profiles, users RESTART IDENTITY CASCADE`;

const pool = new Pool({ connectionString: databaseUrl, max: 1 });
const client = await pool.connect();
try {
  await client.query('SET statement_timeout = 0');
  if (process.argv.includes('--truncate')) {
    process.stdout.write('truncating…\n');
    await client.query(truncate);
  }

  for (const [label, sql] of steps) {
    const started = Date.now();
    const result = await client.query(sql);
    process.stdout.write(
      `${label.padEnd(34)} ${String(result.rowCount ?? 0).padStart(8)} rows  ${Date.now() - started} ms\n`,
    );
  }

  process.stdout.write('ANALYZE…\n');
  await client.query('ANALYZE');

  const counts = await client.query(`
    SELECT 'users' AS table_name, count(*) FROM users
    UNION ALL SELECT 'profiles', count(*) FROM profiles
    UNION ALL SELECT 'quests', count(*) FROM quests
    UNION ALL SELECT 'user_quests', count(*) FROM user_quests
    UNION ALL SELECT 'submissions', count(*) FROM submissions
    UNION ALL SELECT 'reactions', count(*) FROM reactions
    UNION ALL SELECT 'comments', count(*) FROM comments
    UNION ALL SELECT 'follows', count(*) FROM follows
    UNION ALL SELECT 'blocked_users', count(*) FROM blocked_users
    UNION ALL SELECT 'notifications', count(*) FROM notifications
    UNION ALL SELECT 'collab_groups', count(*) FROM collab_groups
    UNION ALL SELECT 'collab_group_members', count(*) FROM collab_group_members
    UNION ALL SELECT 'collab_votes', count(*) FROM collab_votes
    UNION ALL SELECT 'saved_posts', count(*) FROM saved_posts
    UNION ALL SELECT 'saved_quests', count(*) FROM saved_quests
    UNION ALL SELECT 'reports', count(*) FROM reports
    UNION ALL SELECT 'outbox_events', count(*) FROM outbox_events
    UNION ALL SELECT 'media_objects', count(*) FROM media_objects
    UNION ALL SELECT 'admin_quest_injections', count(*) FROM admin_quest_injections
    UNION ALL SELECT 'admin_audit_log', count(*) FROM admin_audit_log
    ORDER BY 1
  `);
  for (const row of counts.rows) {
    process.stdout.write(`${row.table_name.padEnd(24)} ${String(row.count).padStart(8)}\n`);
  }
} finally {
  client.release();
  await pool.end();
}
