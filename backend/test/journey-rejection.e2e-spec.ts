import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/**
 * What a journey does when a checkpoint is rejected.
 *
 * The failure these exist for was not a wrong value anywhere — it was a
 * screen with nothing on it. A rejected first checkpoint left the timeline
 * saying "THEIR TURN" on a solo run and the panel saying "nothing to do on
 * this journey right now", because ownership was read off an unlock row that
 * step 1 never has, and because a rejection had no state of its own to be in.
 * A player could not retry, could not appeal, and could not get rid of it.
 */
describe('journey rejection (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let admin: TestUser;
  let counter = 0;
  const newPlayer = () => harness.createUser({ prefix: `jr${counter++}` });

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    admin = await harness.createUser({ role: 'super_admin', prefix: 'jradm' });
  }, 300_000);
  afterAll(async () => { await harness?.close(); });

  async function soloChain(steps = 3): Promise<{ chainId: string; questIds: string[] }> {
    const questIds: string[] = [];
    for (let i = 0; i < steps; i++) questIds.push((await harness.createQuest()).id);
    return { chainId: await harness.createQuestChain(questIds), questIds };
  }

  async function runIdFor(chainId: string): Promise<string> {
    const result = await harness.database.query<{ id: string }>(
      `SELECT id FROM quest_chain_runs WHERE chain_id = $1`, [chainId],
    );
    return result.rows[0].id;
  }

  /** Take a checkpoint and have it rejected. */
  async function reject(user: TestUser, questId: string, note = 'Not the sea gate.') {
    const submission = await harness.createSubmission(user, { questId });
    await harness.post(`/submissions/${submission.id}/reject`, admin)
      .send({ reviewNote: note }).expect(204);
    return submission;
  }

  const stageOf = (body: Record<string, unknown>, order: number) =>
    (body.stages as Record<string, unknown>[]).find((s) => s.stepOrder === order)!;

  it('shows the rejection, its reason, and still offers the checkpoint', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain();
    await reject(user, questIds[0], 'That is a screenshot, not a sea gate.');

    const run = (await harness.get(`/journeys/${await runIdFor(chainId)}`, user).expect(200))
      .body.data as Record<string, unknown>;

    const first = stageOf(run, 1);
    expect(first.state).toBe('REJECTED');
    expect(first.rejectionNote).toContain('screenshot');
    expect(first.appealed).toBe(false);
    expect(first.rejectedSubmissionId).toBeTruthy();

    // Solo: the checkpoint is the player's, and the journey knows what it is
    // waiting on them for. Both were false before, which is what produced a
    // journey with nothing to do.
    expect(first.isYours).toBe(true);
    expect((run.nextForViewer as Record<string, unknown>).stepOrder).toBe(1);
    expect(run.status).toBe('active');
  });

  it('reports an appeal rather than an unanswered rejection', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain(2);
    const submission = await reject(user, questIds[0]);
    await harness.post(`/submissions/${submission.id}/appeal`, user)
      .send({ appealNote: 'It really is the gate, from the north side.' }).expect(204);

    const run = (await harness.get(`/journeys/${await runIdFor(chainId)}`, user).expect(200))
      .body.data as Record<string, unknown>;
    // An appeal puts the checkpoint back in front of a human, so the state
    // is the wait — but flagged as an appeal, which is a different wait from
    // a first review and the one the player is anxious about.
    expect(stageOf(run, 1).state).toBe('UNDER_REVIEW');
    expect(stageOf(run, 1).appealed).toBe(true);
    expect(stageOf(run, 1).rejectionNote).toBeNull();
  });

  // The button the player actually presses, end to end.
  //
  // TRY AGAIN goes through /journeys/:id/continue, and that route used to
  // read eligibility out of journey_stage_unlocks — which step 1 never has,
  // because nothing unlocked it. So the one checkpoint a player was allowed
  // to retake was the one the route could not see, and the button failed
  // with NO_CHECKPOINT_AVAILABLE every time. The journey was unfinishable.
  it('lets the player retake a rejected first checkpoint', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain();
    await reject(user, questIds[0]);
    const runId = await runIdFor(chainId);

    const retry = await harness.post(`/journeys/${runId}/continue`, user).send({});
    expect(retry.status, JSON.stringify(retry.body)).toBe(201);
    expect(retry.body.data.stepOrder).toBe(1);

    const run = (await harness.get(`/journeys/${runId}`, user).expect(200))
      .body.data as Record<string, unknown>;
    expect(stageOf(run, 1).state).toBe('IN_PROGRESS');
  });

  // Retaking must not become a way past the gate. Step 2 stays shut until
  // step 1 is actually approved, rejection or no rejection.
  it('still refuses a checkpoint that has not opened', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain();
    await reject(user, questIds[0]);

    const jump = await harness
      .post(`/journeys/${await runIdFor(chainId)}/continue`, user)
      .send({ questId: questIds[1] });
    expect(jump.status).toBe(409);
  });

  // A retake supersedes the rejection: the timeline should show the live
  // attempt, not the one it replaced.
  it('drops the rejection once the player retakes the checkpoint', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain(2);
    await reject(user, questIds[0]);
    await harness.assignQuest(user, questIds[0]);

    const run = (await harness.get(`/journeys/${await runIdFor(chainId)}`, user).expect(200))
      .body.data as Record<string, unknown>;
    expect(stageOf(run, 1).state).toBe('IN_PROGRESS');
    expect(stageOf(run, 1).rejectionNote).toBeNull();
  });

  describe('a rejection nobody answers', () => {
    async function sweep(): Promise<number> {
      const { QuestMaintenanceService } = await import(
        '../src/modules/quests/application/quest-maintenance.service.js'
      );
      return harness.app.get(QuestMaintenanceService).abandonUnansweredJourneys();
    }

    async function age(submissionId: string, hours: number) {
      await harness.database.query(
        `UPDATE submissions SET reviewed_at = now() - make_interval(hours => $2) WHERE id = $1`,
        [submissionId, hours],
      );
    }

    it('leaves the journey alone inside the grace window', async () => {
      const user = await newPlayer();
      const { chainId, questIds } = await soloChain(2);
      const submission = await reject(user, questIds[0]);
      await age(submission.id, 1);

      await sweep();
      const run = await harness.database.query<{ status: string }>(
        `SELECT status FROM quest_chain_runs WHERE id = $1`, [await runIdFor(chainId)],
      );
      expect(run.rows[0].status).toBe('active');
    });

    it('abandons it once the window has passed', async () => {
      const user = await newPlayer();
      const { chainId, questIds } = await soloChain(2);
      const submission = await reject(user, questIds[0]);
      await age(submission.id, 200);

      await sweep();
      const runId = await runIdFor(chainId);
      const run = await harness.database.query<{ status: string }>(
        `SELECT status FROM quest_chain_runs WHERE id = $1`, [runId],
      );
      expect(run.rows[0].status).toBe('abandoned');

      // And it leaves the player's active journeys, which is the whole point.
      const active = await harness.get('/journeys/active', user).expect(200);
      expect((active.body.data.runs as { runId: string }[]).some((r) => r.runId === runId))
        .toBe(false);
    });

    // An appeal is an answer. The clock must stop for it, or appealing would
    // buy the player nothing and the journey would close under them while a
    // moderator was still reading it.
    it('spares a journey whose rejection was appealed', async () => {
      const user = await newPlayer();
      const { chainId, questIds } = await soloChain(2);
      const submission = await reject(user, questIds[0]);
      await harness.post(`/submissions/${submission.id}/appeal`, user)
        .send({ appealNote: 'Please look again.' }).expect(204);
      await age(submission.id, 200);

      await sweep();
      const run = await harness.database.query<{ status: string }>(
        `SELECT status FROM quest_chain_runs WHERE id = $1`, [await runIdFor(chainId)],
      );
      expect(run.rows[0].status).toBe('active');
    });

    // So is a retake.
    it('spares a journey the player went back to', async () => {
      const user = await newPlayer();
      const { chainId, questIds } = await soloChain(2);
      const submission = await reject(user, questIds[0]);
      await age(submission.id, 200);
      await harness.assignQuest(user, questIds[0]);

      await sweep();
      const run = await harness.database.query<{ status: string }>(
        `SELECT status FROM quest_chain_runs WHERE id = $1`, [await runIdFor(chainId)],
      );
      expect(run.rows[0].status).toBe('active');
    });
  });
});
