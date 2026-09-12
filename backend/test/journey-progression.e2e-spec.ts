import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/**
 * Multi-stage progression: what happens when a checkpoint is approved.
 *
 * These run against the real schema and the real progression service,
 * because every failure worth catching here is a state transition that looks
 * fine in isolation: an unlock that opens for the wrong person, a second
 * unlock from a replayed event, a timer that starts while the user is
 * asleep. None of those are visible in a unit test of any single piece.
 *
 * The progression service is called directly rather than through the queue.
 * The worker's delivery is the outbox's job and is tested there; what these
 * pin is the decision it makes, which is the part that was missing entirely.
 */
describe('journey progression (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
  }, 300_000);

  /**
   * A player of their own.
   *
   * Assignment carries a 30-second per-user cooldown, so tests that share a
   * fixture user start failing on pacing rather than on the behaviour they
   * describe — which is exactly how a green suite starts lying.
   */
  let counter = 0;
  const newPlayer = () => harness.createUser({ prefix: `jp${counter++}` });

  afterAll(async () => { await harness?.close(); });

  /** A fresh solo chain of `steps` quests. Returns their ids in order. */
  async function soloChain(steps = 3): Promise<{ chainId: string; questIds: string[] }> {
    const questIds: string[] = [];
    for (let i = 0; i < steps; i++) {
      const quest = await harness.createQuest({ isHidden: i > 0 });
      questIds.push(quest.id);
    }
    const chainId = await harness.createQuestChain(questIds);
    return { chainId, questIds };
  }

  /** Runs the progression decision the outbox consumer would run. */
  async function progress(questId: string, forUser: TestUser) {
    const { JourneyProgressionService } = await import(
      '../src/modules/quests/application/journey-progression.service.js'
    );
    const service = harness.app.get(JourneyProgressionService);
    return service.onSubmissionApproved(questId, forUser.id);
  }

  async function unlocksFor(chainId: string) {
    const result = await harness.database.query<{ step_order: number; target_user_id: string; started_at: Date | null }>(
      `SELECT u.step_order, u.target_user_id, u.started_at
       FROM journey_stage_unlocks u JOIN quest_chain_runs r ON r.id = u.chain_run_id
       WHERE r.chain_id = $1 ORDER BY u.step_order`,
      [chainId],
    );
    return result.rows;
  }

  it('approving stage 1 unlocks stage 2 and starts no timer', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain();
    // Assigning step 1 opens the run; approving it opens step 2.
    await harness.createSubmission(user, { questId: questIds[0] });
    await harness.database.query(
      `UPDATE user_quests SET status = 'approved' WHERE user_id = $1 AND quest_id = $2`,
      [user.id, questIds[0]],
    );
    const result = await progress(questIds[0], user);
    expect(result.kind).toBe('stage-unlocked');

    const unlocks = await unlocksFor(chainId);
    expect(unlocks).toHaveLength(1);
    expect(unlocks[0].step_order).toBe(2);
    expect(unlocks[0].target_user_id).toBe(user.id);
    // The whole point of unlock-and-offer: nothing is assigned, so no
    // countdown is running against a user who has not chosen to start.
    expect(unlocks[0].started_at).toBeNull();
    const assigned = await harness.database.query(
      `SELECT 1 FROM user_quests WHERE user_id = $1 AND quest_id = $2`,
      [user.id, questIds[1]],
    );
    expect(assigned.rows, 'unlocking must not assign').toHaveLength(0);
  });

  it('a replayed approval produces exactly one unlock', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain(2);
    await harness.createSubmission(user, { questId: questIds[0] });
    await harness.database.query(
      `UPDATE user_quests SET status = 'approved' WHERE user_id = $1 AND quest_id = $2`,
      [user.id, questIds[0]],
    );
    await progress(questIds[0], user);
    const second = await progress(questIds[0], user);
    // The primary key refuses the second row, so the caller is told there is
    // nothing new to announce rather than notifying twice.
    expect(second.kind).toBe('already-processed');
    expect(await unlocksFor(chainId)).toHaveLength(1);
  });

  it('a stage that is only submitted unlocks nothing', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain(2);
    await harness.createSubmission(user, { questId: questIds[0] });
    // Left 'submitted' — under review, not approved.
    const result = await progress(questIds[0], user);
    // Nothing approved, so the next step is still the first unapproved one
    // and there is nothing to open beyond what already exists.
    expect(result.kind).not.toBe('journey-completed');
    const unlocks = await unlocksFor(chainId);
    expect(unlocks.filter((u) => u.step_order === 2)).toHaveLength(0);
  });

  it('approving the final stage completes the run and unlocks nothing further', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain(2);
    for (const questId of questIds) {
      // The cooldown is per user and real; the fixture waits it out rather
      // than reaching past the rule it is not testing.
      await harness.database.query(
        `UPDATE user_quests SET assigned_at = assigned_at - interval '1 hour' WHERE user_id = $1`,
        [user.id],
      );
      await harness.createSubmission(user, { questId });
      await harness.database.query(
        `UPDATE user_quests SET status = 'approved' WHERE user_id = $1 AND quest_id = $2`,
        [user.id, questId],
      );
      await progress(questId, user);
    }
    const run = await harness.database.query<{ status: string; completed_at: Date | null }>(
      `SELECT status, completed_at FROM quest_chain_runs WHERE chain_id = $1`, [chainId],
    );
    expect(run.rows[0].status).toBe('completed');
    expect(run.rows[0].completed_at).not.toBeNull();
    // No step 3 exists, so nothing was invented to keep the journey going.
    expect((await unlocksFor(chainId)).every((u) => u.step_order <= 2)).toBe(true);
  });

  it('a locked later step never reaches the random roll', async () => {
    const { questIds } = await soloChain(3);
    const fresh = await harness.createUser({ prefix: 'jproll' });
    const response = await harness.get('/quests/picker?count=20', fresh);
    const rolled = (response.body.data as { id: string }[]).map((q) => q.id);
    expect(rolled).not.toContain(questIds[1]);
    expect(rolled).not.toContain(questIds[2]);
  });

  it('an unlock belongs to one user, not to anyone who asks', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain(2);
    await harness.createSubmission(user, { questId: questIds[0] });
    await harness.database.query(
      `UPDATE user_quests SET status = 'approved' WHERE user_id = $1 AND quest_id = $2`,
      [user.id, questIds[0]],
    );
    await progress(questIds[0], user);
    // A different account must not be able to take the checkpoint that
    // opened for this one — the unlock names its target, and eligibility
    // reads that rather than "was the previous step approved by somebody".
    const stranger = await harness.createUser({ prefix: 'jpstr' });
    const response = await harness.post('/quests/assign', stranger).send({ questId: questIds[1] });
    expect(response.status).toBeGreaterThanOrEqual(400);
    const unlocks = await unlocksFor(chainId);
    expect(unlocks.every((u) => u.target_user_id !== stranger.id)).toBe(true);
  });

  it('a group chain refuses to start as a solo run', async () => {
    const user = await newPlayer();
    // Coercing a relay into a solo run would produce a run whose kind
    // disagrees with its chain, and would hand one person a journey meant
    // to pass between several.
    const questIds: string[] = [];
    for (let i = 0; i < 2; i++) questIds.push((await harness.createQuest()).id);
    await harness.createQuestChain(questIds, 'group');
    const response = await harness.post('/quests/assign', user).send({ questId: questIds[0] });
    expect(response.status).toBeGreaterThanOrEqual(400);
    expect(response.body.error.code).toBe('CHAIN_RUN_REQUIRED');
  });

  it('a started checkpoint that expires stays retryable', async () => {
    // started_at is audit, never a gate. If it gated, a checkpoint somebody
    // began and ran out of time on would strand the journey permanently.
    const user = await newPlayer();
    const { questIds } = await soloChain(2);
    await harness.createSubmission(user, { questId: questIds[0] });
    await harness.database.query(
      `UPDATE user_quests SET status = 'approved' WHERE user_id = $1 AND quest_id = $2`,
      [user.id, questIds[0]],
    );
    await progress(questIds[0], user);
    // Start step 2, then let it expire unfinished.
    await harness.database.query(
      `UPDATE user_quests SET assigned_at = assigned_at - interval '1 hour' WHERE user_id = $1`,
      [user.id],
    );
    await harness.post('/quests/assign', user).send({ questId: questIds[1] });
    await harness.database.query(
      `UPDATE user_quests SET status = 'expired' WHERE user_id = $1 AND quest_id = $2`,
      [user.id, questIds[1]],
    );
    await harness.database.query(
      `UPDATE user_quests SET assigned_at = assigned_at - interval '1 hour' WHERE user_id = $1`,
      [user.id],
    );
    const retry = await harness.post('/quests/assign', user).send({ questId: questIds[1] });
    expect(retry.status, JSON.stringify(retry.body)).toBe(201);
  });
});
