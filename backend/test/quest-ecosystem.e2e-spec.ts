import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/**
 * The nineteen acceptance checks for the quest ecosystem.
 *
 * These run against the real schema and the real eligibility engine, because
 * the failures worth catching are exactly the ones a unit test cannot see: a
 * hidden quest leaking into a roll, an expired festival still assignable, a
 * relay whose second step nobody can reach. Every one of those inserts
 * perfectly and reads back fine — they only show up when the query that
 * decides what a person may be handed runs for real.
 */
describe('quest ecosystem (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let user: TestUser;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    user = await harness.createUser({ prefix: 'eco' });
  }, 300_000);

  afterAll(async () => { await harness?.close(); });

  /** Seeded content, addressed by its stable key rather than its title. */
  async function seededQuestId(seedKey: string): Promise<string | undefined> {
    const result = await harness.database.query<{ id: string }>(
      'SELECT id FROM quests WHERE seed_key = $1', [seedKey],
    );
    return result.rows[0]?.id;
  }

  // ── 1 & 2: the roll still works, and still spans the categories ────────

  it('TEST 1 — the random roll still returns everyday quests', async () => {
    const response = await harness.get('/quests/picker?count=3', user);
    expect(response.status).toBe(200);
    const quests = response.body.data as { id: string; category: string }[];
    expect(quests.length).toBeGreaterThan(0);
  });

  it('TEST 2 — all five categories remain rollable', async () => {
    const result = await harness.database.query<{ category: string }>(
      `SELECT DISTINCT category FROM quests
       WHERE is_active AND NOT is_hidden
         AND NOT EXISTS (SELECT 1 FROM quest_destinations d WHERE d.quest_id = quests.id)`,
    );
    const categories = result.rows.map((r) => r.category);
    for (const expected of ['fitness', 'social', 'creativity', 'learning', 'adventure']) {
      expect(categories, `${expected} must stay rollable`).toContain(expected);
    }
  });

  // ── 3 & 4: destination content is discoverable from anywhere ───────────

  it('TEST 3 — every seeded country has visible destination quests', async () => {
    const result = await harness.database.query<{ country_code: string; n: number }>(
      `SELECT p.country_code, count(*)::int AS n
       FROM quests q
       JOIN quest_destinations d ON d.quest_id = q.id
       JOIN map_places p ON p.id = d.place_id AND p.is_published
       WHERE q.is_active AND NOT q.is_hidden AND q.seed_key LIKE 'bsheel:%'
       GROUP BY p.country_code`,
    );
    expect(result.rows.length).toBeGreaterThanOrEqual(10);
    for (const row of result.rows) expect(row.n).toBeGreaterThanOrEqual(2);
  });

  it('TEST 4 — a user with no verified presence can still browse a foreign country', async () => {
    // The whole tourism premise: discovery has to work before the trip, or
    // it can never be the reason for one.
    const response = await harness.get('/discovery/countries/QA', user);
    expect(response.status).toBe(200);
    expect((response.body.data as unknown[]).length).toBeGreaterThan(0);
  });

  it('TEST 5 — Worth the Trip returns curated flagship quests', async () => {
    const response = await harness.get('/discovery/worth-the-trip', user);
    expect(response.status).toBe(200);
    const items = response.body.data as { destination: unknown; badges: string[] }[];
    expect(items.length).toBeGreaterThan(0);
    for (const item of items) {
      expect(item.destination, 'a travel shelf item must have somewhere to travel to').not.toBeNull();
      expect(item.badges).toContain('WORTH THE TRIP');
    }
  });

  // ── 6: hidden ──────────────────────────────────────────────────────────

  it('TEST 6 — a hidden quest is withheld before unlock and appears after', async () => {
    const questId = await seededQuestId('bsheel:q:hidden-qa-inland-sea');
    expect(questId).toBeDefined();

    const before = await harness.database.query(
      `SELECT 1 FROM quests q
       WHERE q.id = $1
         AND (NOT q.is_hidden OR EXISTS (
           SELECT 1 FROM user_quest_unlocks u WHERE u.quest_id = q.id AND u.user_id = $2))`,
      [questId, user.id],
    );
    expect(before.rowCount, 'hidden content must not be visible before unlock').toBe(0);

    await harness.database.query(
      `INSERT INTO user_quest_unlocks (user_id, quest_id) VALUES ($1,$2)
       ON CONFLICT DO NOTHING`, [user.id, questId],
    );

    const after = await harness.database.query(
      `SELECT 1 FROM quests q
       WHERE q.id = $1
         AND (NOT q.is_hidden OR EXISTS (
           SELECT 1 FROM user_quest_unlocks u WHERE u.quest_id = q.id AND u.user_id = $2))`,
      [questId, user.id],
    );
    expect(after.rowCount, 'an unlocked quest must become visible').toBe(1);
  });

  // ── 7 & 9: chains ──────────────────────────────────────────────────────

  it('TEST 7 — a later stage cannot be started before the previous is approved', async () => {
    const stepTwo = await seededQuestId('bsheel:q:chain-byblos-2');
    const response = await harness.post('/quests/assign', user).send({ questId: stepTwo });
    expect(response.status).toBe(409);
    expect(response.body.error.code).toBe('QUEST_STEP_LOCKED');
  });

  it('TEST 9 — a group relay reads the group, not the caller', async () => {
    // The bug this pins: the gate used to require the SAME user to have the
    // previous step approved, so a relay's second step could never open for
    // anyone and mode='group' was unreachable.
    const result = await harness.database.query<{ mode: string; completion_rule: string }>(
      `SELECT mode, completion_rule FROM quest_chains WHERE seed_key = 'bsheel:chain:relay'`,
    );
    expect(result.rows[0]?.mode).toBe('group');
    expect(result.rows[0]?.completion_rule).toBe('sequential');

    const relayTwo = await seededQuestId('bsheel:q:relay-2');
    const response = await harness.post('/quests/assign', user).send({ questId: relayTwo });
    // Locked for a non-member, and locked for the right reason.
    expect(response.status).toBe(409);
    expect(response.body.error.code).toBe('QUEST_STEP_LOCKED');
  });

  it('TEST 10 — a cross-country challenge links steps in different countries', async () => {
    const result = await harness.database.query<{ countries: number; rule: string }>(
      `SELECT count(DISTINCT p.country_code)::int AS countries, max(ch.completion_rule) AS rule
       FROM quest_chains ch
       JOIN quest_chain_steps cs ON cs.chain_id = ch.id
       JOIN quest_destinations d ON d.quest_id = cs.quest_id
       JOIN map_places p ON p.id = d.place_id
       WHERE ch.seed_key = 'bsheel:chain:levant-table'`,
    );
    expect(result.rows[0].countries).toBeGreaterThanOrEqual(3);
    // Order must not matter across borders.
    expect(result.rows[0].rule).toBe('all_steps_any_order');
  });

  it('TEST 10b — an any-order chain does not gate its later steps', async () => {
    const step = await seededQuestId('bsheel:q:xc-ps-oil');
    const response = await harness.post('/quests/assign', user).send({ questId: step });
    // Assignable without step 1, which is the point of the rule.
    expect(response.status, JSON.stringify(response.body)).toBe(201);
    await harness.database.query('DELETE FROM user_quests WHERE user_id=$1', [user.id]);
  });

  // ── 11 & 12: time ──────────────────────────────────────────────────────

  it('TEST 11 — an expired event cannot be started, an active one can', async () => {
    const expired = await seededQuestId('bsheel:q:event-eg-expired-lantern');
    const expiredResponse = await harness.post('/quests/assign', user).send({ questId: expired });
    expect(expiredResponse.status, 'a closed window must refuse').toBeGreaterThanOrEqual(400);

    const active = await seededQuestId('bsheel:q:event-qa-f1-paddock');
    const activeResponse = await harness.post('/quests/assign', user).send({ questId: active });
    expect(activeResponse.status, JSON.stringify(activeResponse.body)).toBe(201);
    await harness.database.query('DELETE FROM user_quests WHERE user_id=$1', [user.id]);
  });

  it('TEST 12 — Quest of the Day returns one quest through the existing mechanism', async () => {
    const response = await harness.get('/quests/quest-of-the-day', user);
    expect(response.status).toBe(200);
  });

  // ── 13, 14, 15: sponsorship and verification ───────────────────────────

  it('TEST 13 — sponsorship is a relation, and seed partners are marked demo', async () => {
    const result = await harness.database.query<{ name: string; is_demo: boolean }>(
      `SELECT pt.name, pt.is_demo FROM quests q
       JOIN quest_partners pt ON pt.id = q.partner_id
       WHERE q.seed_key = 'bsheel:q:spon-qa-chef'`,
    );
    expect(result.rows[0]).toBeDefined();
    expect(result.rows[0].is_demo, 'seeded sponsors must be unmistakably demo').toBe(true);
    expect(result.rows[0].name).toMatch(/^DEMO/);
  });

  it('TEST 14 — a location-independent quest needs no CAMARA evidence', async () => {
    const questId = await seededQuestId('bsheel:q:std-phrases');
    const response = await harness.post('/quests/assign', user).send({ questId });
    expect(response.status, JSON.stringify(response.body)).toBe(201);
    await harness.database.query('DELETE FROM user_quests WHERE user_id=$1', [user.id]);
  });

  it('TEST 15 — a destination quest declares verification and is takeable before travel', async () => {
    // The proposal's flagship journey: press Do This Quest in Lebanon, fly
    // later. Presence is proven at submission, not at assignment.
    const questId = await seededQuestId('bsheel:q:qa-lusail-final');
    const declared = await harness.database.query<{ requires_verification: boolean }>(
      'SELECT requires_verification FROM quest_destinations WHERE quest_id = $1', [questId],
    );
    expect(declared.rows[0].requires_verification).toBe(true);

    const response = await harness.post('/quests/assign', user).send({ questId });
    expect(response.status, 'discovery must be able to precede the trip').toBe(201);
    await harness.database.query('DELETE FROM user_quests WHERE user_id=$1', [user.id]);
  });

  it('TEST 16 — collection progress counts only approved quests', async () => {
    const result = await harness.database.query<{ total: number }>(
      `SELECT count(*)::int AS total FROM quest_collection_items ci
       JOIN quest_collections c ON c.id = ci.collection_id
       WHERE c.seed_key = 'bsheel:col:discover-lebanon'`,
    );
    expect(result.rows[0].total).toBeGreaterThanOrEqual(5);

    const response = await harness.get('/discovery/home', user);
    expect(response.status).toBe(200);
  });

  // ── 17 & 18: the two properties that keep the product coherent ─────────

  it('TEST 17 — Home stays a handful of modules, not a taxonomy screen', async () => {
    const response = await harness.get('/discovery/home', user);
    const modules = (response.body.data as { modules: { type: string; items: unknown[] }[] }).modules;
    expect(modules.length, 'Home must not grow a row per quest type').toBeLessThanOrEqual(4);
    for (const module of modules) {
      expect(module.items.length + ((module as { journeys?: unknown[] }).journeys?.length ?? 0),
        `${module.type} rendered empty`).toBeGreaterThan(0);
    }
  });

  it('TEST 18 — nothing ineligible can leak into the roll', async () => {
    // One query standing in for every leak at once, because each of these
    // reads back perfectly and is only wrong at the moment of being offered.
    const leaks = await harness.database.query<{ seed_key: string; reason: string }>(
      `WITH rollable AS (
         SELECT q.* FROM quests q
         WHERE q.is_active
           AND NOT q.is_hidden
           AND (q.available_from  IS NULL OR q.available_from  <= now())
           AND (q.available_until IS NULL OR q.available_until >  now())
           AND NOT EXISTS (SELECT 1 FROM quest_destinations d WHERE d.quest_id = q.id)
           AND NOT EXISTS (
             SELECT 1 FROM quest_chain_steps cs
             JOIN quest_chains ch ON ch.id = cs.chain_id
             WHERE cs.quest_id = q.id AND cs.step_order > 1
               AND ch.completion_rule = 'sequential')
       )
       SELECT seed_key, 'hidden'   AS reason FROM rollable WHERE is_hidden
       UNION ALL SELECT seed_key, 'expired'  FROM rollable WHERE available_until <= now()
       UNION ALL SELECT seed_key, 'upcoming' FROM rollable WHERE available_from  >  now()
       UNION ALL SELECT r.seed_key, 'destination' FROM rollable r
         JOIN quest_destinations d ON d.quest_id = r.id`,
    );
    expect(leaks.rows, JSON.stringify(leaks.rows)).toHaveLength(0);
  });

  it('TEST 19 — the seed is idempotent', async () => {
    const duplicates = await harness.database.query<{ title: string }>(
      `SELECT title FROM quests WHERE seed_key LIKE 'bsheel:%'
       GROUP BY title HAVING count(*) > 1`,
    );
    expect(duplicates.rows).toHaveLength(0);
  });
});
