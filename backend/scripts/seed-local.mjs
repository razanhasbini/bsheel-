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

import { createHash, randomUUID } from 'node:crypto';
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
const camaraPersonas = process.argv.includes('--camara-personas');

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

// [email, username, displayName, bio, adminRole, phoneNumber]
//
// **Phone sign-in is the product's mandatory path, and nothing here may
// stand in its way.** Every account is anchored to a CAMARA-verified number
// (email/password is the secondary credential), so the app redirects a
// signed-in account without one to /verify-phone. A seeded account with no
// number can therefore sign in and reach nothing, which is why these exist
// at all — they are fixtures for the DATA, not a demonstration of sign-up.
//
// Writing the column directly is the documented local-testing device (see
// docs/CAMARA_TESTING.md); in production it is only ever written by a
// completed Number Verification, and this script refuses to run there.
//
// **These are deliberately NOT Nokia simulator numbers.** The simulator
// answers per number and only `+99999991000` can complete Number
// Verification — so a fixture holding it would take the one number the real
// phone sign-up flow needs, and `phone_number` is globally UNIQUE. An
// earlier version of this file did exactly that and broke the demo of the
// requirement it was meant to support. Lebanese fixture numbers stay out of
// the simulator's way; `--camara-personas` hands them out on purpose.
const USERS = [
  ['admin@bsheel.test', 'admin', 'Admin', 'Runs the place.', 'super_admin', '+9611000001'],
  ['mod@bsheel.test', 'moderator', 'Mod', 'Reviews the queue.', 'moderator', '+9611000002'],
  ['layla@bsheel.test', 'layla', 'Layla', 'Here for the adventure quests.', null, '+9611000003'],
  ['omar@bsheel.test', 'omar', 'Omar', 'Fitness only. No drawing.', null, '+9611000004'],
  ['rana@bsheel.test', 'rana', 'Rana', 'I will draw anything.', null, '+9611000005'],
  ['sami@bsheel.test', 'sami', 'Sami', 'Collecting every category.', null, '+9611000006'],
  ['nour@bsheel.test', 'nour', 'Nour', '', null, '+9611000007'],
  ['ziad@bsheel.test', 'ziad', 'Ziad', 'Lurker.', null, '+9611000008'],
];

/// Nokia simulator personas, assigned only with `--camara-personas`.
///
/// The simulator answers PER PHONE NUMBER, so a location outcome is chosen
/// by choosing whose account to act as. Off by default for one reason:
/// handing `+99999991000` to a fixture consumes the only number that can
/// complete Number Verification, and the live phone sign-up — a mandatory
/// requirement — then has no number left to demonstrate with.
///
/// Use it when you are testing the location matrix and not the sign-up.
const CAMARA_PERSONAS = [
  // Location Verification TRUE — the only persona that reaches an APPROVED
  // location outcome end to end.
  ['layla', '+99999991001'],
  // Number Verification TRUE, Location FALSE — the contradiction case: good
  // photo, network says the device was never there. TAKES THE SIGN-UP NUMBER.
  ['omar', '+99999991000'],
  // UNKNOWN → UNAVAILABLE → human review. Never an automatic rejection.
  ['rana', '+99999991002'],
  // PARTIAL with no matchRate → UNAVAILABLE → human review.
  ['sami', '+99999991003'],
  // Provider error (returns 500) → UNAVAILABLE → human review.
  ['nour', '+99999990503'],
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
      // Two tables reference `quests` with ON DELETE RESTRICT, and both have
      // to go first or the reset fails on its own fixture. quest_of_the_day
      // was always one of them. collab_groups is the other, and it only
      // shows up on a database that has been used: a group whose creator was
      // not a seeded user survives the delete above and then holds its quest
      // hostage, so `--reset` worked on a clean database and failed on a
      // real one — which is the opposite of when you need it.
      await client.query(
        `DELETE FROM quest_of_the_day
         WHERE quest_id IN (SELECT id FROM quests WHERE title = ANY($1::text[]))`,
        [QUESTS.map(([title]) => title)],
      );
      await client.query(
        `DELETE FROM collab_groups
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
    for (const [email, username, displayName, bio, role, phoneNumber] of USERS) {
      // `phone_number` is globally UNIQUE, and the simulator personas are a
      // shared testing resource: an account created by hand during earlier
      // CAMARA work may be holding the one this fixture wants, and the seed
      // then dies on a 23505 halfway through. Take it back, and say so.
      //
      // Releasing it costs that account nothing it needs: `phoneVerified`
      // is read from `phone_verified_at`, which is left alone, so it does
      // not land at the phone wall — it just stops answering as this
      // persona, which is the point.
      const claimed = await client.query(
        `UPDATE users SET phone_number = NULL
          WHERE phone_number = $1 AND email IS DISTINCT FROM $2
          RETURNING id`,
        [phoneNumber, email],
      );
      if (claimed.rowCount) {
        log(`  reclaimed ${phoneNumber} from ${claimed.rowCount} other local account(s)`);
      }
      const existing = await client.query('SELECT id FROM users WHERE email = $1', [email]);
      if (existing.rowCount) {
        userIds[username] = existing.rows[0].id;
        // Backfill for a database seeded before the numbers existed —
        // otherwise re-running the seed leaves the accounts at the phone
        // wall, which is the one thing this is here to prevent.
        await client.query(
          `UPDATE users SET phone_number = $2, phone_verified_at = now()
            WHERE id = $1 AND phone_number IS NULL`,
          [existing.rows[0].id, phoneNumber],
        );
        continue;
      }
      const user = await client.query(
        `INSERT INTO users (email, password_hash, email_verified_at, status,
                            phone_number, phone_verified_at)
         VALUES ($1, $2, now(), 'active', $3, now()) RETURNING id`,
        [email, passwordHash, phoneNumber],
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

    // Opt-in only. See CAMARA_PERSONAS: this consumes +99999991000, the one
    // number that can complete Number Verification, so the live phone
    // sign-up has nothing left to demonstrate with until the seed is run
    // again without the flag.
    if (camaraPersonas) {
      for (const [username, phoneNumber] of CAMARA_PERSONAS) {
        await client.query(
          `UPDATE users SET phone_number = NULL
            WHERE phone_number = $1 AND id IS DISTINCT FROM $2`,
          [phoneNumber, userIds[username]],
        );
        await client.query(
          `UPDATE users SET phone_number = $2, phone_verified_at = now() WHERE id = $1`,
          [userIds[username], phoneNumber],
        );
      }
      log(`camara personas: ${CAMARA_PERSONAS.map(([u]) => u).join(', ')}`);
      log('  WARNING: omar now holds +99999991000 — the only number that can');
      log('  complete Number Verification. Live phone sign-up cannot be');
      log('  demonstrated until you re-run the seed without --camara-personas.');
    }

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
    // Every seeded submission shares these bytes, so exact-duplicate
    // detection will legitimately flag them against each other. That is a
    // faithful local exercise of the check rather than a defect.
    const pngMd5 = createHash('md5').update(pngBytes).digest('hex');
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
      putObject = async (key, body = pngBytes, contentType = 'image/png') => {
        await s3.send(new PutObjectCommand({
          Bucket: process.env.R2_BUCKET,
          Key: key,
          Body: body,
          ContentType: contentType,
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

      const submission = await client.query(
        `INSERT INTO submissions
           (user_quest_id, user_id, media_url, media_type, caption, status,
            appealed, appeal_note, visibility, submitted_at, reviewed_at, reviewed_by, review_note)
         VALUES ($1, $2, $3, 'image', $4, $5::submission_status,
                 $6, CASE WHEN $6 THEN 'I think this does meet the brief, please take another look.' END,
                 $7::submission_visibility,
                 now() - make_interval(days => $8) + interval '1 hour',
                 CASE WHEN $5 IN ('approved','rejected') THEN now() - make_interval(days => $8) + interval '3 hours' END,
                 CASE WHEN $5 IN ('approved','rejected') THEN $9::uuid END,
                 CASE WHEN $5 = 'rejected' THEN 'Proof does not clearly show the quest being completed.' END)
         RETURNING id`,
        [uq.rows[0].id, userId, key, caption, subStatus, appealed,
          visibility ?? 'visible', assignedAgo, userIds.moderator],
      );

      // The `media_objects` row the real upload flow creates. Without it the
      // seeded environment has bytes in storage and no record of them, so
      // anything that reads media metadata — the AI proof forensics pass
      // (#47), the media quota, the orphan reclaim — sees an empty table and
      // silently does nothing locally.
      await client.query(
        `INSERT INTO media_objects
           (user_id, client_request_id, object_key, kind, status, content_type,
            declared_size_bytes, stored_size_bytes, etag, submission_id,
            upload_expires_at, created_at, completed_at)
         VALUES ($1, gen_random_uuid(), $2, 'submission', 'ready', 'image/png',
                 $3, $3, $4, $5,
                 now(), now() - make_interval(days => $6), now() - make_interval(days => $6))`,
        [userId, key, pngBytes.length, pngMd5, submission.rows[0].id, assignedAgo],
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


    // ── A business, with enough activity that every dashboard section has
    //    something to render (#14, #50, #81 §28).
    //
    // Without this a teammate seeds, opens the partner dashboard and sees
    // an empty screen with no way to tell "nothing seeded" from "broken".
    //
    // Rebuilt from scratch every run rather than upserted, because this
    // script promises to be idempotent and the first version of this block
    // broke that promise: the partner visitors are not in USERS, so
    // `--reset` left them behind and a second run added a second place, two
    // more quests and six more submissions. Counts doubled and the fixture
    // stopped meaning anything.
    await client.query(
      `DELETE FROM users WHERE email LIKE 'partner-visitor-%@bsheel.test'`,
    );
    await client.query(`DELETE FROM businesses WHERE slug = 'tawlet-mar-mikhael'`);
    await client.query(
      `DELETE FROM quests WHERE title IN
         ('Fold your first manoushe', 'Find the oldest tool in the kitchen')`,
    );
    await client.query(`DELETE FROM map_places WHERE name = 'Tawlet Mar Mikhael'`);

    // The counts below are chosen deliberately: five consented visitors is
    // the minimum reportable cohort, so the country panel shows a real
    // bucket instead of its suppression notice, and a sixth visitor with no
    // country exercises the "undisclosed" line.
    const businessOwner = userIds.layla;
    const place = (await client.query(
      `INSERT INTO map_places (country_code, name, description, city, category,
                               latitude, longitude, is_published)
       VALUES ('LB', 'Tawlet Mar Mikhael', 'Seeded partner location.', 'Beirut',
               'culture', 33.8938, 35.5018, true)
       RETURNING id`,
    )).rows[0];

    const business = (await client.query(
      `INSERT INTO businesses (name, slug, description, contact_email,
                               status, analytics_subscribed_at, created_by)
       VALUES ('Tawlet Mar Mikhael', 'tawlet-mar-mikhael',
               'Seeded partner account for local testing.',
               'partner@bsheel.test', 'active', now(), $1)
       RETURNING id`,
      [userIds.admin],
    )).rows[0];

    await client.query(
      `INSERT INTO business_members (business_id, user_id, role)
       VALUES ($1, $2, 'owner')`,
      [business.id, businessOwner],
    );
    // A manager as well, so the read-only role is testable without an admin.
    await client.query(
      `INSERT INTO business_members (business_id, user_id, role)
       VALUES ($1, $2, 'manager')`,
      [business.id, userIds.omar],
    );
    await client.query(
      `INSERT INTO business_places (business_id, place_id, linked_by)
       VALUES ($1, $2, $3)`,
      [business.id, place.id, userIds.admin],
    );

    // Two quests at the place: one that people finish, one nobody has
    // started — which is what makes the "no completion rate" case visible
    // rather than theoretical.
    const partnerQuests = [];
    for (const [title, description] of [
      ['Fold your first manoushe', 'Watch, then try it yourself. Photo of yours.'],
      ['Find the oldest tool in the kitchen', 'Ask. Then show us what they said.'],
    ]) {
      const row = (await client.query(
        `INSERT INTO quests (title, description, category, difficulty,
                             xp_reward, duration_hours, is_active, created_by)
         VALUES ($1, $2, 'learning', 'easy', 25, 24, true, $3)
         RETURNING id`,
        [title, description, userIds.admin],
      )).rows[0];
      await client.query(
        `INSERT INTO quest_destinations (quest_id, place_id) VALUES ($1, $2)`,
        [row.id, place.id],
      );
      partnerQuests.push(row.id);
    }

    // Visitors. Six complete the first quest; five declare a country and
    // consent, which is exactly the reporting threshold, and the sixth
    // leaves the origin panel an "undisclosed" figure to state.
    const visitorCountries = ['LB', 'LB', 'LB', 'LB', 'LB', null];
    for (const [index, countryCode] of visitorCountries.entries()) {
      const visitor = (await client.query(
        `INSERT INTO users (email, password_hash, email_verified_at, status)
         VALUES ($1, $2, now(), 'active')
         RETURNING id`,
        [`partner-visitor-${index}@bsheel.test`, passwordHash],
      )).rows[0];
      await client.query(
        `INSERT INTO profiles (id, username, display_name, country_code, analytics_consent_at)
         VALUES ($1, $2, $3, $4, CASE WHEN $4::text IS NULL THEN NULL ELSE now() END)`,
        [visitor.id, `visitor${index}`, `Visitor ${index + 1}`, countryCode],
      );

      const assignment = (await client.query(
        `INSERT INTO user_quests (user_id, quest_id, status, assigned_at, expires_at)
         VALUES ($1, $2, 'approved', now() - interval '3 days',
                 now() - interval '2 days')
         RETURNING id`,
        [visitor.id, partnerQuests[0]],
      )).rows[0];
      // The same key/upload/media_objects shape the other seeded
      // submissions use. Without the media_objects row POST /media/sign
      // finds nothing, and the proof wall -- the one section that shows
      // actual pictures -- renders placeholders while looking broken.
      const partnerKey = `submissions/${visitor.id}/${randomUUID()}.png`;
      await putObject(partnerKey);
      const partnerSubmission = (await client.query(
        `INSERT INTO submissions
           (user_quest_id, user_id, media_url, media_type, caption, status,
            show_in_feed, visibility, submitted_at, reviewed_at, reviewed_by)
         VALUES ($1, $2, $3, 'image', 'Seeded partner proof.', 'approved',
                 $4, 'visible', now() - interval '3 days',
                 now() - interval '3 days' + interval '2 hours', $5)
         RETURNING id`,
        [
          assignment.id,
          visitor.id,
          partnerKey,
          // One kept off the feed, so the proof wall demonstrates that an
          // approved-but-private submission still counts as a completion
          // while its media stays private.
          index !== 0,
          userIds.moderator,
        ],
      )).rows[0];
      await client.query(
        `INSERT INTO media_objects
           (user_id, client_request_id, object_key, kind, status, content_type,
            declared_size_bytes, stored_size_bytes, etag, submission_id,
            upload_expires_at, created_at, completed_at)
         VALUES ($1, gen_random_uuid(), $2, 'submission', 'ready', 'image/png',
                 $3, $3, $4, $5, now(), now() - interval '3 days',
                 now() - interval '3 days')`,
        [visitor.id, partnerKey, pngBytes.length, pngMd5, partnerSubmission.id],
      );
      // The link the real upload flow writes, and the one the CV provider
      // and the media quota read.
      await client.query(
        `INSERT INTO media_submission_links (media_object_id, submission_id)
         SELECT id, $2 FROM media_objects WHERE object_key = $1
         ON CONFLICT DO NOTHING`,
        [partnerKey, partnerSubmission.id],
      );

      // Exposure telemetry, so the funnel's top half is populated. Client-
      // attested by definition, and labelled as such on the dashboard.
      for (const [eventType, howMany] of [
        ['quest_impression', 4],
        ['quest_detail_view', 2],
        ['quest_bsheeel', index < 2 ? 1 : 0],
      ]) {
        for (let n = 0; n < howMany; n += 1) {
          await client.query(
            `INSERT INTO analytics_events
               (client_event_id, user_id, event_type, quest_id, surface, occurred_at)
             VALUES ($1, $2, $3, $4, 'feed', now() - make_interval(days => $5))`,
            [randomUUID(), visitor.id, eventType, partnerQuests[0], (index % 5) + 1],
          );
        }
      }
    }
    log(`business: Tawlet Mar Mikhael — owner layla, manager omar`);

    // ── moments: proof pinned across the map ─────────────────────────────
    //
    // The map's moments layer draws one square per approved, feed-visible
    // submission at a published place. Everything above leaves exactly one
    // place with proof on it, so the layer renders as a single tile and the
    // thing it is for — a board that looks like people have been places —
    // cannot be seen at all.
    //
    // Dedicated users, like the partner visitors and for the same reason:
    // these are approved quests, and hanging them on the named accounts
    // would put their XP out of step with the reconciliation the seed ran
    // further up. Rebuilt each run, so a second run does not double them.
    await client.query(
      `DELETE FROM users WHERE email LIKE 'moment-traveller-%@bsheel.test'`,
    );
    await client.query(`DELETE FROM quests WHERE title LIKE 'Seeded moment at %'`);

    // Whatever published places this database has — the ones seed-quests
    // loaded from backend/seeds/places.json if it has been run, and the
    // partner place otherwise. Deliberately not a list of coordinates
    // invented here: a place is a real location, and seeds/validate.mjs
    // refuses fabricated ones for exactly that reason.
    //
    // Spread wide, not deep, and spread EVENLY — which a plain
    // `ORDER BY country_code, name LIMIT 40` does not.
    //
    // That ordering is alphabetical by country code, so the limit was spent
    // entirely on AE, EG, ES, HU, IT and a single place in JO. Lebanon —
    // forty-one published places, the densest part of the board — received
    // nothing at all, and neither did PS, QA, SA or TR. The map looked like
    // proof existed in five countries and nowhere else, which is worse than
    // the eight-place version it replaced: it is not sparse, it is lopsided.
    //
    // Partitioning by country takes the same budget and spends it across all
    // of them. Ordered by name within a country rather than by anything
    // spatial, because a place is not guaranteed a sensible geometry and a
    // deterministic pick matters more here than a geometric one.
    const momentPlaces = (await client.query(
      `WITH ranked AS (
         SELECT id, name, country_code,
                row_number() OVER (PARTITION BY country_code ORDER BY name) AS rank
           FROM map_places
          WHERE is_published AND category <> 'hidden'
       )
       SELECT id, name, country_code FROM ranked
        WHERE rank <= 6
        ORDER BY country_code, name`,
    )).rows;

    // A sample clip, synthesised rather than committed.
    //
    // The repository has no video in it and should not gain one: a binary
    // fixture is a thing to review, license and carry forever. ffmpeg is
    // already a dependency of this system (the Dockerfile installs it for
    // #47's frame extraction), so where it exists the seed can make its own
    // — three seconds of a test pattern, a few kilobytes, H.264 in an mp4 so
    // every browser can decode it.
    //
    // Without ffmpeg this is null and every seeded moment is a photo, which
    // is exactly what this seed did before. The video moments are what make
    // the map's poster frames visible at all, and a poster is cut by the
    // same ffmpeg — so the two are absent together or present together,
    // never one without the other.
    //
    // The photographs are synthesised too, and for a reason beyond variety.
    // Every other seeded submission shares one 1x1 transparent PNG, which is
    // correct there — it exercises exact-duplicate detection, and nothing
    // renders it at size. A map tile does render it at size, and a
    // transparent pixel stretched over a 54x66 square is indistinguishable
    // from the tile having failed to load: the board looked like flat
    // coloured squares whether or not the media had arrived, so a real bug
    // and a working layer were the same picture.
    //
    // Eight different lavfi sources, picked per place, so tiles differ from
    // each other the way real proof does.
    const MOMENT_IMAGE_SOURCES = [
      'mandelbrot=size=480x854',
      'testsrc2=size=480x854',
      'rgbtestsrc=size=480x854',
      'smptebars=size=480x854',
      'gradients=size=480x854:c0=0x1A1330:c1=0x6B3BFF',
      'gradients=size=480x854:c0=0xFF5A6E:c1=0xFFC224',
      'life=size=480x854:mold=10:r=20',
      'cellauto=size=480x854:rule=110',
    ];

    let sampleVideo = null;
    let momentImages = [];
    try {
      const { execFileSync } = await import('node:child_process');
      const { mkdtempSync, readFileSync, rmSync } = await import('node:fs');
      const { tmpdir } = await import('node:os');
      const { join } = await import('node:path');
      const directory = mkdtempSync(join(tmpdir(), 'bsheel-seed-media-'));

      const file = join(directory, 'sample.mp4');
      execFileSync('ffmpeg', [
        '-f', 'lavfi', '-i', 'testsrc=size=480x854:rate=24:duration=3',
        '-pix_fmt', 'yuv420p', '-c:v', 'libx264', '-preset', 'ultrafast',
        '-movflags', '+faststart', '-y', file,
      ], { stdio: 'ignore' });
      sampleVideo = readFileSync(file);

      momentImages = MOMENT_IMAGE_SOURCES.map((source, variant) => {
        const output = join(directory, `moment-${variant}.jpg`);
        execFileSync('ffmpeg', [
          '-f', 'lavfi', '-i', source, '-frames:v', '1', '-q:v', '4',
          '-y', output,
        ], { stdio: 'ignore' });
        const bytes = readFileSync(output);
        return { bytes, md5: createHash('md5').update(bytes).digest('hex') };
      });

      rmSync(directory, { recursive: true, force: true });
    } catch {
      log('moments: ffmpeg unavailable, seeding the placeholder pixel only');
    }
    const videoMd5 = sampleVideo
      ? createHash('md5').update(sampleVideo).digest('hex')
      : null;

    let moments = 0;
    let videoMoments = 0;
    for (const [index, momentPlace] of momentPlaces.entries()) {
      const traveller = (await client.query(
        `INSERT INTO users (email, password_hash, email_verified_at, status)
         VALUES ($1, $2, now(), 'active') RETURNING id`,
        [`moment-traveller-${index}@bsheel.test`, passwordHash],
      )).rows[0];
      await client.query(
        `INSERT INTO profiles (id, username, display_name, xp, level, quests_completed)
         VALUES ($1, $2, $3, 40, 1, 1)`,
        [traveller.id, `traveller${index}`, `Traveller ${index + 1}`],
      );

      const momentQuest = (await client.query(
        `INSERT INTO quests (title, description, category, difficulty,
                             xp_reward, duration_hours, is_active, created_by)
         VALUES ($1, $2, $3, 'easy', 40, 24, true, $4) RETURNING id`,
        [
          `Seeded moment at ${momentPlace.name}`,
          'Local fixture: proof pinned on the map.',
          ['adventure', 'creativity', 'social', 'learning', 'fitness'][index % 5],
          userIds.admin,
        ],
      )).rows[0];
      await client.query(
        `INSERT INTO quest_destinations (quest_id, place_id) VALUES ($1, $2)`,
        [momentQuest.id, momentPlace.id],
      );

      // Three per place: two are drawn (MOMENTS_PER_PLACE) and the third
      // is what makes the "+N more" badge appear on a real tile, which is
      // otherwise only ever exercised in tests.
      // Every third place is video, so the board carries both kinds and the
      // poster pipeline has something to be seen doing. Not every place:
      // a map of nothing but play glyphs would hide the photographs, which
      // are still what most proof is.
      const isVideoPlace = sampleVideo !== null && index % 3 === 2;
      // Falls back to the shared transparent pixel where ffmpeg is absent,
      // which is the same deployment in which no poster could be cut either.
      const photo = momentImages.length > 0
        ? momentImages[index % momentImages.length]
        : { bytes: pngBytes, md5: pngMd5 };
      const photoType = momentImages.length > 0 ? 'image/jpeg' : 'image/png';
      const photoExtension = momentImages.length > 0 ? 'jpg' : 'png';

      for (let copy = 0; copy < 3; copy += 1) {
        // Deliberately NOT `index + copy`. The moments query takes the
        // newest N overall after ranking within each place, so a date that
        // climbed with the place index handed every drawn tile to the first
        // few places in the list and starved the rest — the same lopsided
        // board, arriving by a different route. Stepping by a number coprime
        // with the window scatters the dates across a month without
        // correlating with position.
        const daysAgo = ((index * 7 + copy * 11) % 29) + 1;
        const assignment = (await client.query(
          `INSERT INTO user_quests (user_id, quest_id, status, assigned_at, expires_at)
           VALUES ($1, $2, 'approved', now() - make_interval(days => $3),
                   now() - make_interval(days => $3) + interval '1 day')
           RETURNING id`,
          [traveller.id, momentQuest.id, daysAgo],
        )).rows[0];
        const key = isVideoPlace
          ? `submissions/${traveller.id}/${randomUUID()}.mp4`
          : `submissions/${traveller.id}/${randomUUID()}.${photoExtension}`;
        await putObject(
          key,
          isVideoPlace ? sampleVideo : photo.bytes,
          isVideoPlace ? 'video/mp4' : photoType,
        );
        const submission = (await client.query(
          `INSERT INTO submissions
             (user_quest_id, user_id, media_url, media_type, caption, status,
              show_in_feed, visibility, submitted_at, reviewed_at, reviewed_by)
           VALUES ($1, $2, $3, $7, $4, 'approved', true, 'visible',
                   now() - make_interval(days => $5),
                   now() - make_interval(days => $5) + interval '2 hours', $6)
           RETURNING id`,
          [
            assignment.id, traveller.id, key,
            `Seeded proof at ${momentPlace.name}.`, daysAgo, userIds.moderator,
            isVideoPlace ? 'video' : 'image',
          ],
        )).rows[0];
        // Without the media_objects row POST /media/sign finds nothing and
        // every tile draws its placeholder — which looks exactly like the
        // layer being broken.
        await client.query(
          `INSERT INTO media_objects
             (user_id, client_request_id, object_key, kind, status, content_type,
              declared_size_bytes, stored_size_bytes, etag, submission_id,
              upload_expires_at, created_at, completed_at)
           VALUES ($1, gen_random_uuid(), $2, 'submission', 'ready', $7,
                   $3, $3, $4, $5, now(), now() - make_interval(days => $6),
                   now() - make_interval(days => $6))`,
          [
            traveller.id, key,
            isVideoPlace ? sampleVideo.length : photo.bytes.length,
            isVideoPlace ? videoMd5 : photo.md5,
            submission.id, daysAgo,
            isVideoPlace ? 'video/mp4' : photoType,
          ],
        );
        await client.query(
          `INSERT INTO media_submission_links (media_object_id, submission_id)
           SELECT id, $2 FROM media_objects WHERE object_key = $1
           ON CONFLICT DO NOTHING`,
          [key, submission.id],
        );
        moments += 1;
        if (isVideoPlace) videoMoments += 1;
      }
    }
    // The poster frames for those videos are not cut here. The worker's
    // sweep does it, off the same partial index a production backlog would
    // use — so seeding exercises the real path rather than a seed-only
    // shortcut that could keep working after the real one broke. Until it
    // runs, a video tile draws the category tint, which is the honest
    // fallback and the thing to look for if posters ever stop appearing.
    log(`moments: ${moments} across ${momentPlaces.length} places (${videoMoments} video)`);

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
         (SELECT count(*) FROM reports WHERE status = 'pending') AS open_reports,
         (SELECT count(*) FROM businesses) AS businesses,
         (SELECT count(*) FROM map_places WHERE is_published) AS published_places,
         (SELECT count(*) FROM quest_destinations) AS placed_quests,
         (SELECT count(*) FROM analytics_events) AS analytics_events`,
    );
    log('\nseeded:', counts.rows[0]);
    log(`\nsign in with any of these — password: ${PASSWORD}`);
    for (const [email, username, , , role, phoneNumber] of USERS) {
      log(`  ${email.padEnd(22)} ${username.padEnd(11)} ${(role ?? 'user').padEnd(12)} ${phoneNumber}`);
    }
    log('\nPhone sign-in is the real path: sign UP in the app with');
    log('  +99999991000 — the Nokia simulator number that verifies.');
    log('These seeded accounts are data fixtures, and their numbers are');
    log('Lebanese placeholders that stay out of the simulator\'s way; sign in');
    log('to them with the email and password above. For the location matrix,');
    log('re-run with --camara-personas (see docs/CAMARA_TESTING.md).');
    log('\nthe partner dashboard: sign in as layla (owner) or omar (manager)');
    log('  cd apps/business_web && flutter run -d chrome \\');
    log('    --dart-define=API_URL=http://127.0.0.1:3010/api/v1');
  } finally {
    client.release();
    await pool.end();
  }
}

await main();
