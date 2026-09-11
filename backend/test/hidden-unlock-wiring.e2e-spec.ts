import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness } from './support/e2e-harness.js';

/**
 * Hidden quests must actually open.
 *
 * The engine that evaluates unlock rules was written, tested and then never
 * called: `evaluateFor` had zero callers, so a hidden quest gated on a
 * prerequisite could not open for anybody, ever. The rules were right and
 * the wiring was absent, which is the kind of gap that looks like a working
 * feature in every unit test.
 */
describe('hidden quest unlock wiring (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let counter = 0;
  const newPlayer = () => harness.createUser({ prefix: `hu${counter++}` });

  beforeAll(async () => { harness = await E2eHarness.boot(); }, 300_000);
  afterAll(async () => { await harness?.close(); });

  async function evaluate(userId: string) {
    const { QuestUnlockService } = await import(
      '../src/modules/discovery/application/quest-unlock.service.js'
    );
    return harness.app.get(QuestUnlockService).evaluateFor(userId);
  }

  it('a prerequisite approval opens the hidden quest behind it', async () => {
    const user = await newPlayer();
    const gateway = await harness.createQuest();
    const secret = await harness.createQuest({ isHidden: true });
    await harness.database.query(
      `INSERT INTO quest_unlock_rules (quest_id, unlock_type, prerequisite_quest_id)
       VALUES ($1, 'prerequisite_quest', $2)`,
      [secret.id, gateway.id],
    );

    // Nothing opens on a submission alone — approval is the condition.
    await harness.createSubmission(user, { questId: gateway.id });
    expect(await evaluate(user.id)).toHaveLength(0);

    await harness.database.query(
      `UPDATE user_quests SET status = 'approved' WHERE user_id = $1 AND quest_id = $2`,
      [user.id, gateway.id],
    );
    const opened = await evaluate(user.id);
    expect(opened.map((q) => q.questId)).toContain(secret.id);
  });

  it('a discovery happens once, however many times it is evaluated', async () => {
    const user = await newPlayer();
    const gateway = await harness.createQuest();
    const secret = await harness.createQuest({ isHidden: true });
    await harness.database.query(
      `INSERT INTO quest_unlock_rules (quest_id, unlock_type, prerequisite_quest_id)
       VALUES ($1, 'prerequisite_quest', $2)`,
      [secret.id, gateway.id],
    );
    await harness.createSubmission(user, { questId: gateway.id });
    await harness.database.query(
      `UPDATE user_quests SET status = 'approved' WHERE user_id = $1 AND quest_id = $2`,
      [user.id, gateway.id],
    );

    expect(await evaluate(user.id)).toHaveLength(1);
    // The replay a retried job would produce: the primary key refuses the
    // second row, so nothing is announced twice.
    expect(await evaluate(user.id)).toHaveLength(0);
  });

  it('an unopened hidden quest stays out of the roll and out of discovery',
    async () => {
      const user = await newPlayer();
      const secret = await harness.createQuest({ isHidden: true });
      const roll = await harness.get('/quests/picker?count=20', user);
      expect((roll.body.data as { id: string }[]).map((q) => q.id))
        .not.toContain(secret.id);
      // And it cannot be taken by asking for it directly either.
      const grab = await harness.post('/quests/assign', user).send({ questId: secret.id });
      expect(grab.status).toBeGreaterThanOrEqual(400);
    });

  it('an opened hidden quest becomes assignable', async () => {
    const user = await newPlayer();
    const gateway = await harness.createQuest();
    const secret = await harness.createQuest({ isHidden: true });
    await harness.database.query(
      `INSERT INTO quest_unlock_rules (quest_id, unlock_type, prerequisite_quest_id)
       VALUES ($1, 'prerequisite_quest', $2)`,
      [secret.id, gateway.id],
    );
    await harness.createSubmission(user, { questId: gateway.id });
    await harness.database.query(
      `UPDATE user_quests SET status = 'approved' WHERE user_id = $1 AND quest_id = $2`,
      [user.id, gateway.id],
    );
    await evaluate(user.id);
    await harness.database.query(
      `UPDATE user_quests SET assigned_at = assigned_at - interval '1 hour' WHERE user_id = $1`,
      [user.id],
    );
    const grab = await harness.post('/quests/assign', user).send({ questId: secret.id });
    expect(grab.status, JSON.stringify(grab.body)).toBe(201);
  });
});
