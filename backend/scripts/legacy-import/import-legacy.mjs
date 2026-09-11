#!/usr/bin/env node
// Imports user info, quests, attempts, submissions and XP from the legacy
// Supabase database into the Bsheel schema. See ACCESS.md for how to create
// the read-only role this needs.
//
// Design decisions worth knowing before you run it:
//
//  * READ-ONLY on the source. The legacy connection opens a REPEATABLE READ
//    transaction and never writes. That instance is still serving quest-app.
//
//  * Legacy UUIDs are preserved. Every row keeps its id, so the import is
//    idempotent (re-running updates rather than duplicating) and so
//    submissions still point at the right attempts and authors.
//
//  * Passwords are NOT imported. Supabase hashes with bcrypt in auth.users;
//    Bsheel uses Argon2 and the column-level grant deliberately excludes
//    encrypted_password anyway. Imported accounts land with a NULL
//    password_hash, which the API treats as "cannot sign in with a
//    password" — they must use the reset flow. Pretending otherwise would
//    mean inventing a password and emailing it, which is worse.
//
//  * Conflicts are reported, never silently resolved. A legacy username or
//    email that already belongs to a DIFFERENT id in Bsheel is skipped and
//    listed. Renaming someone's handle to force a row in is not a decision
//    a script should make.
//
// Usage:
//   LEGACY_DATABASE_URL=... node scripts/legacy-import/import-legacy.mjs
//   LEGACY_DATABASE_URL=... node scripts/legacy-import/import-legacy.mjs --apply
//
// Without --apply it is a dry run: it reads everything, resolves every
// conflict, prints exactly what would change, and writes nothing.

import pg from 'pg';

const APPLY = process.argv.includes('--apply');
const LEGACY_URL = process.env.LEGACY_DATABASE_URL;
const TARGET_URL = process.env.DATABASE_URL;

if (!LEGACY_URL) fail('LEGACY_DATABASE_URL is not set — see scripts/legacy-import/ACCESS.md');
if (!TARGET_URL) fail('DATABASE_URL is not set — the Bsheel database to import into');

function fail(message) {
  console.error(`\n  ${message}\n`);
  process.exit(1);
}

const counts = {};
const skipped = [];
function note(table, key) {
  counts[table] ??= { read: 0, written: 0, skipped: 0 };
  counts[table][key] += 1;
}

async function main() {
  const legacy = new pg.Client({
    connectionString: LEGACY_URL,
    ssl: { rejectUnauthorized: false },
    application_name: 'bsheel-legacy-import(read-only)',
  });
  const target = new pg.Client({ connectionString: TARGET_URL });

  await legacy.connect();
  await target.connect();
  console.log(`\n  mode: ${APPLY ? 'APPLY — writing to the Bsheel database' : 'DRY RUN — nothing will be written'}`);

  try {
    // A single snapshot, so the counts cannot shift under us mid-import
    // while quest-app keeps serving traffic.
    await legacy.query('BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY');
    await target.query('BEGIN');

    await importUsers(legacy, target);
    await importQuests(legacy, target);
    await importUserQuests(legacy, target);
    await importSubmissions(legacy, target);
    await reconcileXp(target);

    await legacy.query('ROLLBACK'); // read-only; nothing to commit
    if (APPLY) {
      await target.query('COMMIT');
      console.log('\n  committed.');
    } else {
      await target.query('ROLLBACK');
      console.log('\n  rolled back (dry run).');
    }
  } catch (error) {
    await legacy.query('ROLLBACK').catch(() => {});
    await target.query('ROLLBACK').catch(() => {});
    throw error;
  } finally {
    await legacy.end().catch(() => {});
    await target.end().catch(() => {});
  }

  report();
}

/// users + profiles. auth.users holds the email; public.profiles holds
/// everything the app shows. They share the same id, in both schemas.
async function importUsers(legacy, target) {
  const { rows } = await legacy.query(`
    SELECT p.id, p.username::text AS username, p.display_name, p.avatar_url, p.bio,
           p.xp, p.level, p.quests_completed, p.created_at, p.updated_at,
           u.email::text AS email, u.email_confirmed_at, u.last_sign_in_at
    FROM public.profiles p
    JOIN auth.users u ON u.id = p.id
    ORDER BY p.created_at`);

  for (const r of rows) {
    note('users', 'read');
    // An email or username already held by a different id is a genuine
    // collision between two systems' accounts. Report it; do not rename.
    const clash = await target.query(
      `SELECT 'email' AS what FROM users WHERE email = $2 AND id <> $1
       UNION ALL
       SELECT 'username' FROM profiles WHERE username = $3 AND id <> $1`,
      [r.id, r.email, r.username]);
    if (clash.rowCount) {
      note('users', 'skipped');
      skipped.push(`user ${r.username} <${mask(r.email)}> — ${clash.rows.map((c) => c.what).join(' and ')} already taken by another account`);
      continue;
    }

    await target.query(`
      INSERT INTO users (id, email, password_hash, email_verified_at, status, last_login_at, created_at)
      VALUES ($1, $2, NULL, $3, 'active', $4, $5)
      ON CONFLICT (id) DO UPDATE SET
        email = EXCLUDED.email,
        email_verified_at = COALESCE(users.email_verified_at, EXCLUDED.email_verified_at),
        last_login_at = GREATEST(users.last_login_at, EXCLUDED.last_login_at),
        updated_at = now()`,
      [r.id, r.email, r.email_confirmed_at, r.last_sign_in_at, r.created_at]);

    await target.query(`
      INSERT INTO profiles (id, username, display_name, avatar_url, bio, xp, level, quests_completed, created_at, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
      ON CONFLICT (id) DO UPDATE SET
        username = EXCLUDED.username,
        display_name = EXCLUDED.display_name,
        avatar_url = EXCLUDED.avatar_url,
        bio = EXCLUDED.bio,
        xp = EXCLUDED.xp,
        level = EXCLUDED.level,
        quests_completed = EXCLUDED.quests_completed,
        updated_at = now()`,
      [r.id, r.username, r.display_name || r.username, r.avatar_url, r.bio,
       r.xp ?? 0, r.level ?? 1, r.quests_completed ?? 0, r.created_at, r.updated_at]);
    note('users', 'written');
  }
}

/// Quests must land before attempts reference them.
async function importQuests(legacy, target) {
  const { rows } = await legacy.query(`
    SELECT id, title, description, category, difficulty, xp_reward,
           COALESCE(duration_hours, 4) AS duration_hours,
           COALESCE(is_active, true) AS is_active, created_at, updated_at
    FROM public.quests ORDER BY created_at`);

  for (const r of rows) {
    note('quests', 'read');
    await target.query(`
      INSERT INTO quests (id, title, description, category, difficulty, xp_reward, duration_hours, is_active, created_at, updated_at)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
      ON CONFLICT (id) DO UPDATE SET
        title = EXCLUDED.title, description = EXCLUDED.description,
        category = EXCLUDED.category, difficulty = EXCLUDED.difficulty,
        xp_reward = EXCLUDED.xp_reward, duration_hours = EXCLUDED.duration_hours,
        is_active = EXCLUDED.is_active, updated_at = now()`,
      [r.id, r.title, r.description ?? '', r.category, r.difficulty,
       r.xp_reward ?? 0, r.duration_hours, r.is_active, r.created_at, r.updated_at]);
    note('quests', 'written');
  }
}

/// Attempts. Every legacy status value is already legal in Bsheel's
/// user_quest_status enum, so no translation is needed.
async function importUserQuests(legacy, target) {
  const { rows } = await legacy.query(`
    SELECT id, user_id, quest_id, status::text AS status, assigned_at, completed_at, expires_at
    FROM public.user_quests ORDER BY assigned_at`);

  for (const r of rows) {
    note('user_quests', 'read');
    // Its author or quest may have been skipped as a collision.
    const ok = await target.query(
      `SELECT 1 FROM profiles WHERE id=$1 AND EXISTS (SELECT 1 FROM quests WHERE id=$2)`,
      [r.user_id, r.quest_id]);
    if (!ok.rowCount) {
      note('user_quests', 'skipped');
      skipped.push(`attempt ${r.id} — its user or quest was not imported`);
      continue;
    }
    await target.query(`
      INSERT INTO user_quests (id, user_id, quest_id, status, assigned_at, completed_at, expires_at)
      VALUES ($1,$2,$3,$4::user_quest_status,$5,$6,$7)
      ON CONFLICT (id) DO UPDATE SET
        status = EXCLUDED.status, completed_at = EXCLUDED.completed_at`,
      [r.id, r.user_id, r.quest_id, r.status, r.assigned_at, r.completed_at, r.expires_at]);
    note('user_quests', 'written');
  }
}

/// Submissions. `media_url` is carried across verbatim and NO media_objects
/// row is created here, deliberately: copying bytes needs the legacy object
/// store, which is a different credential and a different failure mode from
/// this read-only database transaction.
///
/// Run `npm run legacy:media` afterwards. Until it has run, an imported
/// submission points at a path that does not resolve against the new bucket
/// and has no media record, so signed-URL serving, AI proof verification and
/// the media quota all silently see nothing (#57).
///
/// This comment used to cite "STORAGE notes in ACCESS.md", which has never
/// contained any. The note is the header of scripts/legacy-import/import-media.mjs.
///
/// xp_awarded is set from the status so the reversal paths stay correct, and
/// visibility defaults to visible for approved work.
async function importSubmissions(legacy, target) {
  const { rows } = await legacy.query(`
    SELECT s.id, s.user_quest_id, s.user_id, s.media_url, s.media_type::text AS media_type,
           s.caption, s.status::text AS status, s.reviewed_by, s.review_note,
           s.submitted_at, s.reviewed_at, q.xp_reward
    FROM public.submissions s
    LEFT JOIN public.user_quests uq ON uq.id = s.user_quest_id
    LEFT JOIN public.quests q ON q.id = uq.quest_id
    ORDER BY s.submitted_at`);

  for (const r of rows) {
    note('submissions', 'read');
    const ok = await target.query('SELECT 1 FROM user_quests WHERE id=$1', [r.user_quest_id]);
    if (!ok.rowCount) {
      note('submissions', 'skipped');
      skipped.push(`submission ${r.id} — its attempt was not imported`);
      continue;
    }
    const approved = r.status === 'approved';
    await target.query(`
      INSERT INTO submissions (id, user_quest_id, user_id, media_url, media_type, caption,
                               status, reviewed_by, review_note, submitted_at, reviewed_at,
                               xp_awarded, xp_awarded_amount, visibility, show_in_feed)
      VALUES ($1,$2,$3,$4,$5::media_type,$6,$7::submission_status,$8,$9,$10,$11,
              $12,$13,'visible'::submission_visibility,$12)
      ON CONFLICT (id) DO UPDATE SET
        status = EXCLUDED.status, review_note = EXCLUDED.review_note,
        reviewed_at = EXCLUDED.reviewed_at, xp_awarded = EXCLUDED.xp_awarded,
        xp_awarded_amount = EXCLUDED.xp_awarded_amount`,
      [r.id, r.user_quest_id, r.user_id, r.media_url, r.media_type ?? 'image',
       r.caption, r.status, r.reviewed_by, r.review_note, r.submitted_at,
       r.reviewed_at, approved, approved ? (r.xp_reward ?? 0) : 0]);
    note('submissions', 'written');
  }
}

/// The legacy `profiles.xp` is authoritative for history, but Bsheel has an
/// XP reconciliation screen precisely because a stored total can drift from
/// the submissions that justify it. Report the drift rather than silently
/// overwriting either number.
async function reconcileXp(target) {
  const { rows } = await target.query(`
    SELECT count(*)::int AS drifted
    FROM profiles p
    WHERE p.xp <> COALESCE((
      SELECT sum(s.xp_awarded_amount) FROM submissions s
      WHERE s.user_id = p.id AND s.xp_awarded), 0)`);
  const drifted = rows[0]?.drifted ?? 0;
  if (drifted > 0) {
    console.log(`\n  note: ${drifted} profile(s) have a stored XP total that differs from the sum of their approved submissions.`);
    console.log('        Legacy XP was kept as-is. Use the admin /xp screen to reconcile deliberately.');
  }
}

function mask(email) {
  const [user, domain] = String(email).split('@');
  return `${user.slice(0, 2)}***@${domain ?? '?'}`;
}

function report() {
  console.log('\n  ── summary ──');
  for (const [table, c] of Object.entries(counts)) {
    console.log(`  ${table.padEnd(14)} read ${String(c.read).padStart(6)}   written ${String(c.written).padStart(6)}   skipped ${String(c.skipped).padStart(5)}`);
  }
  if (skipped.length) {
    console.log(`\n  ── skipped (${skipped.length}) ──`);
    for (const line of skipped.slice(0, 25)) console.log(`  • ${line}`);
    if (skipped.length > 25) console.log(`  … and ${skipped.length - 25} more`);
  }
  if (!APPLY) console.log('\n  This was a dry run. Re-run with --apply to write.');
  console.log('\n  Imported accounts have no password: they must use the reset flow to sign in.\n');
}

await main();
