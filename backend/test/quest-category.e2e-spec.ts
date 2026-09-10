import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// Quest category is a closed set, and both halves of that have to hold.
///
/// The DTO half is the clean 400 — see quest-category.spec.ts for its full
/// table. The half that matters is the constraint: CLAUDE.md puts the final
/// guard for legal values in PostgreSQL, so the interesting tests here go
/// straight at the table on the application's own connection, past every DTO.
/// Before migration 0027 `category` was free text bounded only by length, so
/// all of these succeeded.
describe('quest category is a closed set (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let admin: TestUser;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    admin = await harness.createUser({ role: 'super_admin', prefix: 'catAdm' });
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  const body = (category: string) => ({
    title: `Category probe ${harness.uniqueName('q')}`,
    description: 'Created by the quest-category integration suite.',
    category,
    difficulty: 'easy',
    xpReward: 15,
    durationHours: 4,
    isActive: true,
  });

  it('creates a quest in a legal category', async () => {
    const response = await harness.post('/quests/admin', admin).send(body('adventure')).expect(201);
    harness.trackQuest(response.body.data.id);
    expect(response.body.data.category).toBe('adventure');
  });

  it('answers a category nobody implemented with a 400, not a constraint violation', async () => {
    const response = await harness.post('/quests/admin', admin).send(body('sports')).expect(400);
    expect(response.body.error.message).toContain('category');
  });

  it('rejects the near-miss spelling that was already in the data', async () => {
    await harness.post('/quests/admin', admin).send(body('creative')).expect(400);
  });

  it('rejects an illegal category on the update path too', async () => {
    const quest = await harness.createQuest();
    await harness.patch(`/quests/admin/${quest.id}`, admin).send({ category: 'sports' }).expect(400);
    await harness.patch(`/quests/admin/${quest.id}`, admin).send({ category: 'fitness' }).expect(200);

    const stored = await harness.database.query<{ category: string }>(
      'SELECT category FROM quests WHERE id = $1',
      [quest.id],
    );
    expect(stored.rows[0].category).toBe('fitness');
  });

  it('refuses a bulk create if any one row is illegal', async () => {
    await harness
      .post('/quests/admin/bulk', admin)
      .send({ quests: [body('fitness'), body('sports')] })
      .expect(400);
  });

  it('refuses an illegal category at the table, with no DTO involved', async () => {
    await expect(harness.createQuest({ category: 'sports' })).rejects.toMatchObject({
      code: '23514',
      constraint: 'quests_category_check',
    });
  });

  it('refuses an UPDATE that walks a legal row out of the set', async () => {
    const quest = await harness.createQuest();
    await expect(
      harness.database.query('UPDATE quests SET category = $2 WHERE id = $1', [quest.id, 'e2e']),
    ).rejects.toMatchObject({ code: '23514', constraint: 'quests_category_check' });
  });

  it.each(['fitness', 'creativity', 'social', 'learning', 'adventure'])(
    'accepts %s at the table',
    async (category) => {
      const quest = await harness.createQuest({ category });
      const stored = await harness.database.query<{ category: string }>(
        'SELECT category FROM quests WHERE id = $1',
        [quest.id],
      );
      expect(stored.rows[0].category).toBe(category);
    },
  );

  it('closes quest_suggestions too, because approving one copies its category into quests', async () => {
    await expect(
      harness.database.query(
        `INSERT INTO quest_suggestions (title, description, category, difficulty, status)
         VALUES ($1, 'Suggested by the integration suite.', 'sports', 'easy', 'pending')`,
        [`Suggestion probe ${harness.uniqueName('s')}`],
      ),
    ).rejects.toMatchObject({ code: '23514', constraint: 'quest_suggestions_category_check' });
  });

  it('leaves no illegal category anywhere in the table', async () => {
    // The constraint makes this true by construction; it is here because it
    // is the claim the finding was about, and it would have failed before.
    expect(
      await harness.countRows(
        `SELECT count(*) FROM quests
         WHERE category NOT IN ('fitness', 'creativity', 'social', 'learning', 'adventure')`,
        [],
      ),
    ).toBe(0);
  });
});
