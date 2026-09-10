// Seeds the curated development quest catalogue from backend/seeds/*.json.
//
// Idempotent on `seed_key`, never on title: curated copy gets edited, and
// keying on a title would insert a second copy every time somebody fixed a
// typo. Running this twice is a no-op.
//
// Usage:
//   DATABASE_URL=… node scripts/seed-quests.mjs
//   DATABASE_URL=… node scripts/seed-quests.mjs --prune
//
// --prune removes seeded rows that are no longer in the files. It only ever
// touches rows whose seed_key starts with `bsheel:`, so user-authored quests
// — which have no seed key at all — cannot be caught by it.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import process from 'node:process';
import pg from 'pg';
import { validateSeed } from './seed-validate.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const seedDir = join(here, '..', 'seeds');
const read = (name) => JSON.parse(readFileSync(join(seedDir, name), 'utf8'));

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');
const prune = process.argv.includes('--prune');

const data = {
  countries: read('countries.json'),
  places: read('places.json'),
  standard: read('quests.standard.json'),
  destination: read('quests.destination.json'),
  mechanics: read('quests.mechanics.json'),
  chains: read('chains.json'),
  collections: read('collections.json'),
};

// Refuse the whole run rather than insert half a catalogue. Half a chain is a
// dead end a user can walk into, which is worse than no chain at all.
const problems = validateSeed(data);
if (problems.length > 0) {
  console.error(`\nSeed validation failed (${problems.length}):\n`);
  for (const p of problems) console.error(`  ${p}`);
  process.exit(1);
}

const pool = new pg.Pool({ connectionString: databaseUrl, max: 4 });
const client = await pool.connect();

/** Every quest in the files, flattened with its dimensions resolved. */
function allQuests() {
  const out = [];
  for (const q of data.standard) out.push({ ...q, kind: 'standard' });
  for (const q of data.destination) out.push({ ...q, kind: 'destination' });
  for (const q of data.mechanics.hidden) out.push({ ...q, kind: 'hidden', isHidden: true });
  for (const q of data.mechanics.events) out.push({ ...q, kind: 'event' });
  for (const q of data.mechanics.sponsored) out.push({ ...q, kind: 'sponsored' });
  for (const q of data.chains.questsForChains) out.push({ ...q, kind: 'chain-step' });
  return out;
}

function daysFromNow(days) {
  if (days === undefined || days === null) return null;
  return new Date(Date.now() + days * 86_400_000).toISOString();
}

try {
  await client.query('BEGIN');

  // ── Countries ──────────────────────────────────────────────────────────
  // Master geographic data: upsert the name, never delete. Other tables have
  // foreign keys into this and an ISO dataset is not ours to prune.
  for (const c of data.countries) {
    await client.query(
      `INSERT INTO map_countries (code, name, geometry_id) VALUES ($1,$2,$3)
       ON CONFLICT (code) DO UPDATE SET name = EXCLUDED.name`,
      [c.code, c.name, c.geometryId],
    );
  }

  // ── Places ─────────────────────────────────────────────────────────────
  // A place with unknown coordinates is seeded UNPUBLISHED, so it cannot
  // reach a user until somebody checks it. Inventing a latitude to make the
  // row insert cleanly is how a geofence ends up in the wrong country.
  const placeIds = new Map();
  for (const p of data.places) {
    const publish = !p.needsLocationReview;
    const { rows } = await client.query(
      `INSERT INTO map_places (seed_key, country_code, name, description, city, category,
                               latitude, longitude, radius_m, is_published)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
       ON CONFLICT (seed_key) DO UPDATE SET
         name = EXCLUDED.name, description = EXCLUDED.description, city = EXCLUDED.city,
         category = EXCLUDED.category, radius_m = EXCLUDED.radius_m,
         latitude = COALESCE(EXCLUDED.latitude, map_places.latitude),
         longitude = COALESCE(EXCLUDED.longitude, map_places.longitude),
         is_published = EXCLUDED.is_published
       RETURNING id`,
      [p.seedKey, p.countryCode, p.name, p.description ?? '', p.city ?? '', p.category,
       p.latitude ?? 0, p.longitude ?? 0, p.radiusM ?? 250, publish],
    );
    placeIds.set(p.seedKey, rows[0].id);
  }

  // ── Partners ───────────────────────────────────────────────────────────
  const partnerIds = new Map();
  for (const pt of data.mechanics.partners) {
    const { rows } = await client.query(
      `INSERT INTO quest_partners (seed_key, name, slug, kind, country_code, is_demo)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (seed_key) DO UPDATE SET
         name = EXCLUDED.name, kind = EXCLUDED.kind,
         country_code = EXCLUDED.country_code, is_demo = EXCLUDED.is_demo
       RETURNING id`,
      [pt.seedKey, pt.name, pt.slug, pt.kind, pt.countryCode ?? null, pt.isDemo === true],
    );
    partnerIds.set(pt.seedKey, rows[0].id);
  }

  // ── Quests ─────────────────────────────────────────────────────────────
  const questIds = new Map();
  for (const q of allQuests()) {
    const { rows } = await client.query(
      `INSERT INTO quests (seed_key, title, description, category, difficulty, xp_reward,
                           duration_hours, is_active, is_hidden, editorial_tier,
                           is_globally_discoverable, available_from, available_until, partner_id)
       VALUES ($1,$2,$3,$4,$5,$6,$7,true,$8,$9,true,$10,$11,$12)
       ON CONFLICT (seed_key) DO UPDATE SET
         title = EXCLUDED.title, description = EXCLUDED.description,
         category = EXCLUDED.category, difficulty = EXCLUDED.difficulty,
         xp_reward = EXCLUDED.xp_reward, duration_hours = EXCLUDED.duration_hours,
         is_hidden = EXCLUDED.is_hidden, editorial_tier = EXCLUDED.editorial_tier,
         available_from = EXCLUDED.available_from, available_until = EXCLUDED.available_until,
         partner_id = EXCLUDED.partner_id, updated_at = now()
       RETURNING id`,
      [q.seedKey, q.title, q.description, q.category, q.difficulty, q.xpReward,
       q.durationHours, q.isHidden === true, q.editorialTier ?? 'standard',
       daysFromNow(q.availableFromDaysFromNow), daysFromNow(q.availableUntilDaysFromNow),
       q.partner ? partnerIds.get(q.partner) : null],
    );
    questIds.set(q.seedKey, rows[0].id);

    if (q.place) {
      await client.query(
        `INSERT INTO quest_destinations (quest_id, place_id, requires_verification)
         VALUES ($1,$2,$3)
         ON CONFLICT (quest_id) DO UPDATE SET
           place_id = EXCLUDED.place_id, requires_verification = EXCLUDED.requires_verification`,
        [rows[0].id, placeIds.get(q.place), q.requiresVerification !== false],
      );
    }
  }

  // ── Collections ────────────────────────────────────────────────────────
  const collectionIds = new Map();
  for (const col of data.collections) {
    const { rows } = await client.query(
      `INSERT INTO quest_collections (seed_key, name, description, country_code, is_published)
       VALUES ($1,$2,$3,$4,true)
       ON CONFLICT (seed_key) DO UPDATE SET
         name = EXCLUDED.name, description = EXCLUDED.description,
         country_code = EXCLUDED.country_code, is_published = true, updated_at = now()
       RETURNING id`,
      [col.seedKey, col.name, col.description, col.countryCode ?? null],
    );
    const collectionId = rows[0].id;
    collectionIds.set(col.seedKey, collectionId);
    await client.query('DELETE FROM quest_collection_items WHERE collection_id = $1', [collectionId]);
    for (const q of col.quests) {
      await client.query(
        `INSERT INTO quest_collection_items (collection_id, quest_id) VALUES ($1,$2)
         ON CONFLICT DO NOTHING`,
        [collectionId, questIds.get(q)],
      );
    }
  }

  // ── Chains ─────────────────────────────────────────────────────────────
  for (const ch of data.chains.chains) {
    const { rows } = await client.query(
      `INSERT INTO quest_chains (seed_key, name, description, mode, completion_rule, is_active)
       VALUES ($1,$2,$3,$4,$5,true)
       ON CONFLICT (seed_key) DO UPDATE SET
         name = EXCLUDED.name, description = EXCLUDED.description,
         mode = EXCLUDED.mode, completion_rule = EXCLUDED.completion_rule, updated_at = now()
       RETURNING id`,
      [ch.seedKey, ch.name, ch.description, ch.mode, ch.completionRule],
    );
    const chainId = rows[0].id;
    await client.query('DELETE FROM quest_chain_steps WHERE chain_id = $1', [chainId]);
    for (const [index, step] of ch.steps.entries()) {
      await client.query(
        `INSERT INTO quest_chain_steps (chain_id, quest_id, step_order) VALUES ($1,$2,$3)`,
        [chainId, questIds.get(step), index + 1],
      );
    }
  }

  // ── Unlock rules ───────────────────────────────────────────────────────
  // After collections, deliberately: a collection_progress rule has to name
  // the collection it counts, and the CHECK on quest_unlock_rules is
  // immediate — inserting a placeholder null and filling it in afterwards is
  // rejected at INSERT, not at COMMIT.
  //
  // Replaced wholesale per quest, so a rule that was edited in the file does
  // not leave its previous version behind still able to open the quest.
  for (const q of data.mechanics.hidden) {
    const questId = questIds.get(q.seedKey);
    await client.query('DELETE FROM quest_unlock_rules WHERE quest_id = $1', [questId]);
    const u = q.unlock;
    await client.query(
      `INSERT INTO quest_unlock_rules
         (quest_id, unlock_type, country_code, place_id, prerequisite_quest_id, collection_id, threshold)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [questId, u.type, u.countryCode ?? null,
       u.place ? placeIds.get(u.place) : null,
       u.quest ? questIds.get(u.quest) : null,
       u.collection ? collectionIds.get(u.collection) : null,
       u.threshold ?? null],
    );
  }

  if (prune) {
    const keep = [...questIds.keys()];
    const { rowCount } = await client.query(
      `DELETE FROM quests
       WHERE seed_key LIKE 'bsheel:%' AND seed_key <> ALL($1::text[])
         AND NOT EXISTS (SELECT 1 FROM user_quests uq WHERE uq.quest_id = quests.id)`,
      [keep],
    );
    console.log(`Pruned ${rowCount} seeded quest(s) no longer in the files.`);
  }

  await client.query('COMMIT');

  const counts = await client.query(
    `SELECT
       (SELECT count(*) FROM quests WHERE seed_key LIKE 'bsheel:%')                AS quests,
       (SELECT count(*) FROM quests WHERE seed_key LIKE 'bsheel:%' AND is_hidden)  AS hidden,
       (SELECT count(*) FROM quests WHERE seed_key LIKE 'bsheel:%'
          AND editorial_tier = 'flagship')                                         AS flagship,
       (SELECT count(*) FROM map_places WHERE seed_key LIKE 'bsheel:%')            AS places,
       (SELECT count(*) FROM map_places WHERE seed_key LIKE 'bsheel:%'
          AND NOT is_published)                                                    AS needs_review,
       (SELECT count(*) FROM quest_chains WHERE seed_key LIKE 'bsheel:%')          AS chains,
       (SELECT count(*) FROM quest_collections WHERE seed_key LIKE 'bsheel:%')     AS collections,
       (SELECT count(*) FROM quest_unlock_rules)                                   AS unlock_rules,
       (SELECT count(*) FROM quest_partners WHERE seed_key LIKE 'bsheel:%')        AS partners`,
  );
  console.log('\nSeeded:');
  for (const [key, value] of Object.entries(counts.rows[0])) {
    console.log(`  ${key.padEnd(14)} ${value}`);
  }
} catch (error) {
  await client.query('ROLLBACK');
  throw error;
} finally {
  client.release();
  await pool.end();
}
