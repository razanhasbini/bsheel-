// Seeds a small, realistic dataset for local testing.
//
// Not a performance fixture — that is `perf-seed.mjs`, which creates hundreds
// of thousands of rows. This one creates just enough of every shape that each
// admin page and each mobile surface has something to render: an admin, a
// handful of users, quests in every category, and submissions in every review
// state including an appealed one and a soft-deleted one.
//
// Passwords are hashed with the same Argon2 settings the API uses, so the
// seeded accounts can actually sign in.
//
// Usage:
//   DATABASE_URL=… node scripts/seed-local.mjs [--reset]
//
// `--reset` deletes the seeded users first (cascading to their content), so
// the script is idempotent and safe to re-run.

import { randomUUID } from 'node:crypto';
import process from 'node:process';
import { hash } from 'argon2';
import pg from 'pg';

const { Pool } = pg;
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');
if (/(^|@)([^/]*\.)?bsheel\.app/.test(databaseUrl)) {
  throw new Error('Refusing to seed what looks like a production database');
}
const reset = process.argv.includes('--reset');

const PASSWORD = 'Str0ng-Passphrase-9';
const pool = new Pool({ connectionString: databaseUrl, max: 4 });

const CATEGORIES = ['fitness', 'creativity', 'social', 'learning', 'adventure'];
const DIFFICULTIES = ['easy', 'medium', 'hard'];

const QUESTS = [
  ['Take a 30 minute walk somewhere new', 'Pick a street you have never walked down and follow it for half an hour.', 'fitness', 'easy', 15, 4],
  ['Do 50 push-ups before noon', 'Split them however you like. Photo of you mid-set.', 'fitness', 'medium', 25, 6],
  ['Run to the highest point near you', 'Find the highest accessible point within walking distance and get there.', 'fitness', 'hard', 50, 12],
  ['Draw the view from your window', 'Any medium. Ten minutes minimum. It does not have to be good.', 'creativity', 'easy', 15, 4],
  ['Write a six-word story about today', 'Exactly six words. Photograph it written by hand.', 'creativity', 'easy', 10, 4],
  ['Build something from what is in the room', 'No shopping. Use only what is already around you.', 'creativity', 'medium', 30, 8],
  ['Compliment a stranger and mean it', 'Specific, not generic. Tell us how it went.', 'social', 'easy', 15, 4],
  ['Call someone you have not spoken to in a year', 'Actually call. Not a text.', 'social', 'medium', 35, 24],
  ['Eat lunch with someone new', 'Someone you have never shared a meal with before.', 'social', 'hard', 45, 24],
  ['Learn to say hello in three new languages', 'Record yourself saying all three.', 'learning', 'easy', 15, 6],
  ['Read 20 pages of something difficult', 'Something you would not normally pick up.', 'learning', 'medium', 25, 12],
  ['Teach someone something you know well', 'Ten minutes, one person, one skill.', 'learning', 'hard', 40, 24],
  ['Watch the sunrise', 'Be outside before the sun is up. Photo at first light.', 'adventure', 'medium', 30, 24],
  ['Take a bus to the end of its route', 'Any line. Ride it to the last stop and look around.', 'adventure', 'medium', 30, 8],
  ['Spend an hour with no phone', 'Leave it behind. Tell us what you noticed.', 'adventure', 'easy', 20, 4],
];

const USERS = [
  ['admin@bsheel.test', 'admin', 'Admin', 'Runs the place.', 'super_admin'],
  ['mod@bsheel.test', 'moderator', 'Mod', 'Reviews the queue.', 'moderator'],
  ['layla@bsheel.test', 'layla', 'Layla', 'Here for the adventure quests.', null],
  ['omar@bsheel.test', 'omar', 'Omar', 'Fitness only. No drawing.', null],
  ['rana@bsheel.test', 'rana', 'Rana', 'I will draw anything.', null],
  ['sami@bsheel.test', 'sami', 'Sami', 'Collecting every category.', null],
  ['nour@bsheel.test', 'nour', 'Nour', '', null],
  ['ziad@bsheel.test', 'ziad', 'Ziad', 'Lurker.', null],
];

const log = (...args) => console.log(...args);

async function main() {
  const client = await pool.connect();
  try {
    if (reset) {
      const emails = USERS.map(([email]) => email);
      // admin_quest_injections.created_by is intentionally RESTRICT: an
      // audit trail must not disappear when a seeded admin is reset. Remove
      // only the local fixture's injections before deleting those users.
      await client.query(
        `DELETE FROM admin_quest_injections
         WHERE created_by IN (SELECT id FROM users WHERE email = ANY($1::citext[]))`,
        [emails],
      );
      const { rowCount } = await client.query(
        'DELETE FROM users WHERE email = ANY($1::citext[])',
        [emails],
      );
      log(`reset: removed ${rowCount} seeded user(s) and their content`);
      await client.query(
        `DELETE FROM quest_of_the_day
         WHERE quest_id IN (SELECT id FROM quests WHERE title = ANY($1::text[]))`,
        [QUESTS.map(([title]) => title)],
      );
      await client.query('DELETE FROM quests WHERE title = ANY($1::text[])', [
        QUESTS.map(([title]) => title),
      ]);
    }

    const passwordHash = await hash(PASSWORD, { type: 2 });

    // ── users, profiles, identities ──────────────────────────────────────
    const userIds = {};
    for (const [email, username, displayName, bio, role] of USERS) {
      const existing = await client.query('SELECT id FROM users WHERE email = $1', [email]);
      if (existing.rowCount) {
        userIds[username] = existing.rows[0].id;
        continue;
      }
      const user = await client.query(
        `INSERT INTO users (email, password_hash, email_verified_at, status)
         VALUES ($1, $2, now(), 'active') RETURNING id`,
        [email, passwordHash],
      );
      const id = user.rows[0].id;
      userIds[username] = id;
      await client.query(
        `INSERT INTO profiles (id, username, display_name, bio, age_verified, profile_completed, xp, level, quests_completed)
         VALUES ($1, $2, $3, $4, true, true, 0, 1, 0)`,
        [id, username, displayName, bio || null],
      );
      await client.query(
        `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, 'password', $2::text, $2::citext)`,
        [id, email],
      );
      if (role) {
        await client.query(
          `INSERT INTO admins (user_id, role) VALUES ($1, $2::admin_role)
           ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role`,
          [id, role],
        );
      }
    }
    log(`users: ${Object.keys(userIds).length}`);

    // ── quests ───────────────────────────────────────────────────────────
    const questIds = [];
    for (const [title, description, category, difficulty, xp, hours] of QUESTS) {
      const existing = await client.query('SELECT id FROM quests WHERE title = $1', [title]);
      if (existing.rowCount) {
        questIds.push(existing.rows[0].id);
        continue;
      }
      const quest = await client.query(
        `INSERT INTO quests (title, description, category, difficulty, xp_reward, duration_hours, is_active, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, true, $7) RETURNING id`,
        [title, description, category, difficulty, xp, hours, userIds.admin],
      );
      questIds.push(quest.rows[0].id);
    }
    log(`quests: ${questIds.length}`);

    // ── media: a real object per submission so signed URLs resolve ───────
    // A 1x1 PNG is enough to prove the signing and fetch path end to end.
    const pngBytes = Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAABzenr0AAAAEklEQVR42mP8z8DwHwMDAxMDAwMAFAYBAK0k9WQAAAAASUVORK5CYII=',
      'base64',
    );
    let putObject = async () => null;
    if (process.env.R2_ENDPOINT && process.env.R2_ACCESS_KEY_ID) {
      const { S3Client, PutObjectCommand } = await import('@aws-sdk/client-s3');
      const s3 = new S3Client({
        endpoint: process.env.R2_ENDPOINT,
        region: process.env.R2_REGION ?? 'us-east-1',
        forcePathStyle: process.env.S3_FORCE_PATH_STYLE === 'true',
        credentials: {
          accessKeyId: process.env.R2_ACCESS_KEY_ID,
          secretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
        },
      });
      putObject = async (key) => {
        await s3.send(new PutObjectCommand({
          Bucket: process.env.R2_BUCKET,
          Key: key,
          Body: pngBytes,
          ContentType: 'image/png',
        }));
        return key;
      };
    }

    // ── submissions in every review state ────────────────────────────────
    // [user, questIndex, userQuestStatus, submissionStatus, appealed, visibility]
    //
    // CONSTRAINT: `user_quests_one_in_progress_idx` allows at most ONE
    // assigned-or-submitted quest per user. The plan below therefore gives
    // each user at most one non-terminal row; everything else is approved,
    // rejected or expired. The assertion after this table enforces it, so a
    // bad edit fails with a readable message instead of a 23505 from
    // PostgreSQL 200 lines later.
    const DUPLICATE_CAPTION = 'Complimented a stranger on the bus this morning';
    const PLAN = [
      // layla: one done, one appeal waiting for a second review
      ['layla', 0, 'approved', 'approved', false, 'visible'],
      ['layla', 3, 'submitted', 'pending', true, 'visible'],
      // omar: one done, one waiting
      ['omar', 1, 'approved', 'approved', false, 'visible'],
      ['omar', 2, 'submitted', 'pending', false, 'visible'],
      // rana: one done, one waiting
      ['rana', 4, 'approved', 'approved', false, 'visible'],
      ['rana', 5, 'submitted', 'pending', false, 'visible'],
      // sami: a rejection and a re-upload reusing its caption, so the review
      // queue shows the DUPLICATE badge (same user, caption >= 8 chars)
      ['sami', 6, 'approved', 'approved', false, 'visible'],
      ['sami', 7, 'rejected', 'rejected', false, 'visible'],
      ['sami', 14, 'submitted', 'pending', false, 'visible'],
      // nour: one done, one waiting
      ['nour', 9, 'approved', 'approved', false, 'visible'],
      ['nour', 10, 'submitted', 'pending', false, 'visible'],
      // ziad: only terminal states — a spent appeal, a takedown, a timeout
      ['ziad', 11, 'rejected', 'rejected', true, 'visible'],
      ['ziad', 12, 'approved', 'approved', false, 'deleted'],
      ['ziad', 13, 'expired', null, false, null],
    ];

    // Fail fast rather than letting the database explain it to us.
    const inProgress = {};
    for (const [username, , uqStatus] of PLAN) {
      if (uqStatus !== 'assigned' && uqStatus !== 'submitted') continue;
      inProgress[username] = (inProgress[username] ?? 0) + 1;
      if (inProgress[username] > 1) {
        throw new Error(
          `Seed plan gives ${username} more than one in-progress quest, ` +
          'which user_quests_one_in_progress_idx forbids',
        );
      }
    }

    let submissions = 0;
    let mediaObjects = 0;
    for (const [username, questIndex, uqStatus, subStatus, appealed, visibility] of PLAN) {
      const userId = userIds[username];
      const questId = questIds[questIndex];
      const dup = await client.query(
        `SELECT uq.id FROM user_quests uq
         WHERE uq.user_id = $1 AND uq.quest_id = $2 AND uq.status = $3::user_quest_status`,
        [userId, questId, uqStatus],
      );
      if (dup.rowCount) continue;

      const assignedAgo = 1 + Math.floor(Math.random() * 20);
      const uq = await client.query(
        `INSERT INTO user_quests (user_id, quest_id, status, assigned_at, expires_at, completed_at)
         VALUES ($1, $2, $3::user_quest_status,
                 now() - make_interval(days => $4),
                 now() - make_interval(days => $4) + make_interval(hours => 24),
                 CASE WHEN $3 IN ('approved','rejected') THEN now() - make_interval(days => $4) + interval '2 hours' END)
         RETURNING id`,
        [userId, questId, uqStatus, assignedAgo],
      );
      if (!subStatus) continue;

      const key = `submissions/${userId}/${randomUUID()}.png`;
      if (await putObject(key)) mediaObjects += 1;

      // sami's rejected quest 7 and pending quest 14 deliberately share a
      // caption so the review queue's duplicate check fires.
      const caption =
        username === 'sami' && (questIndex === 7 || questIndex === 14)
          ? DUPLICATE_CAPTION
          : `Did it — ${QUESTS[questIndex][0].toLowerCase()}.`;

      await client.query(
        `INSERT INTO submissions
           (user_quest_id, user_id, media_url, media_type, caption, status,
            appealed, appeal_note, visibility, submitted_at, reviewed_at, reviewed_by, review_note)
         VALUES ($1, $2, $3, 'image', $4, $5::submission_status,
                 $6, CASE WHEN $6 THEN 'I think this does meet the brief, please take another look.' END,
                 $7::submission_visibility,
                 now() - make_interval(days => $8) + interval '1 hour',
                 CASE WHEN $5 IN ('approved','rejected') THEN now() - make_interval(days => $8) + interval '3 hours' END,
                 CASE WHEN $5 IN ('approved','rejected') THEN $9::uuid END,
                 CASE WHEN $5 = 'rejected' THEN 'Proof does not clearly show the quest being completed.' END)`,
        [uq.rows[0].id, userId, key, caption, subStatus, appealed,
          visibility ?? 'visible', assignedAgo, userIds.moderator],
      );
      submissions += 1;
    }
    log(`submissions: ${submissions} (media objects uploaded: ${mediaObjects})`);

    // ── XP consistent with approved quests ───────────────────────────────
    await client.query(
      `UPDATE profiles p SET
         xp = COALESCE(e.xp, 0),
         quests_completed = COALESCE(e.done, 0),
         level = (COALESCE(e.xp, 0) / 100) + 1
       FROM (SELECT id FROM profiles) ids
       LEFT JOIN LATERAL (
         SELECT sum(q.xp_reward)::int AS xp, count(*)::int AS done
         FROM user_quests uq JOIN quests q ON q.id = uq.quest_id
         WHERE uq.user_id = ids.id AND uq.status = 'approved'
       ) e ON true
       WHERE p.id = ids.id`,
    );

    // ── social graph, votes, comments, saves ─────────────────────────────
    const names = Object.keys(userIds).filter((n) => !['admin', 'moderator'].includes(n));
    for (const follower of names) {
      for (const target of names) {
        if (follower === target) continue;
        if (Math.random() > 0.55) continue;
        await client.query(
          `INSERT INTO follows (follower_id, following_id) VALUES ($1, $2)
           ON CONFLICT DO NOTHING`,
          [userIds[follower], userIds[target]],
        );
      }
    }
    const approved = await client.query(
      `SELECT id, user_id FROM submissions WHERE status = 'approved' AND visibility = 'visible'`,
    );
    let votes = 0;
    let comments = 0;
    for (const submission of approved.rows) {
      for (const voter of names) {
        if (userIds[voter] === submission.user_id) continue;
        if (Math.random() > 0.6) continue;
        await client.query(
          `INSERT INTO reactions (submission_id, user_id, type)
           VALUES ($1, $2, $3::reaction_type) ON CONFLICT DO NOTHING`,
          [submission.id, userIds[voter], Math.random() > 0.2 ? 'upvote' : 'downvote'],
        );
        votes += 1;
      }
      const commenter = names[Math.floor(Math.random() * names.length)];
      if (userIds[commenter] !== submission.user_id) {
        await client.query(
          `INSERT INTO comments (submission_id, user_id, body) VALUES ($1, $2, $3)`,
          [submission.id, userIds[commenter], 'This is genuinely great. @layla you should try this one.'],
        );
        comments += 1;
      }
    }
    log(`follows/votes/comments: votes=${votes} comments=${comments}`);

    // ── one block, so the feed's block filtering has something to do ─────
    await client.query(
      `INSERT INTO blocked_users (blocker_id, blocked_id) VALUES ($1, $2)
       ON CONFLICT DO NOTHING`,
      [userIds.ziad, userIds.omar],
    );

    // ── an open report for the reports page ──────────────────────────────
    const reportable = approved.rows[0];
    if (reportable) {
      // `reports` stores only reported_type + reported_id; the API derives
      // reported_user_id in its query by joining through the submission.
      await client.query(
        `INSERT INTO reports (reporter_id, reported_type, reported_id, reason, status)
         VALUES ($1, 'submission', $2::text, 'Not actually the quest', 'pending')
         ON CONFLICT DO NOTHING`,
        [userIds.nour, reportable.id],
      );
    }

    // ── quest of the day + a waitlist entry + a suggestion ───────────────
    await client.query(
      `INSERT INTO quest_of_the_day (quest_id, display_date, ticket_no, bonus_xp, note, created_by)
       VALUES ($1, current_date, 'QOTD-001', 25, 'Featured today.', $2)
       ON CONFLICT (display_date) DO NOTHING`,
      [questIds[12], userIds.admin],
    );
    await client.query(
      `INSERT INTO waitlist (email, source) VALUES ('curious@example.test', 'landing-page')
       ON CONFLICT DO NOTHING`,
    );
    await client.query(
      `INSERT INTO quest_suggestions (email, title, description, category, difficulty, suggested_by_name, status)
       VALUES ('fan@example.test', 'Swim in the sea before work',
               'Any body of water counts. Photo of you actually in it.',
               'adventure', 'medium', 'A fan', 'pending')
       ON CONFLICT DO NOTHING`,
    );

    const counts = await client.query(
      `SELECT
         (SELECT count(*) FROM profiles) AS profiles,
         (SELECT count(*) FROM quests) AS quests,
         (SELECT count(*) FROM user_quests) AS user_quests,
         (SELECT count(*) FROM submissions) AS submissions,
         (SELECT count(*) FROM submissions WHERE status = 'pending') AS pending,
         (SELECT count(*) FROM submissions WHERE status = 'pending' AND appealed) AS appeals,
         (SELECT count(*) FROM reactions) AS reactions,
         (SELECT count(*) FROM comments) AS comments,
         (SELECT count(*) FROM follows) AS follows,
         (SELECT count(*) FROM reports WHERE status = 'pending') AS open_reports`,
    );
    log('\nseeded:', counts.rows[0]);
    log(`\nsign in with any of these — password: ${PASSWORD}`);
    for (const [email, username, , , role] of USERS) {
      log(`  ${email.padEnd(22)} ${username.padEnd(11)} ${role ?? 'user'}`);
    }
  } finally {
    client.release();
    await pool.end();
  }
}

await main();
