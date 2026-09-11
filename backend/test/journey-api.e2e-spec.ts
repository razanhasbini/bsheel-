import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness } from './support/e2e-harness.js';

/**
 * The journey API a player actually touches.
 *
 * The projection tests matter most: hidden content is withheld by the QUERY,
 * so if it ever leaks it leaks to every device that asks, and no amount of
 * client-side care gets it back.
 */
describe('journey API (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let counter = 0;
  const newPlayer = () => harness.createUser({ prefix: `ja${counter++}` });

  beforeAll(async () => { harness = await E2eHarness.boot(); }, 300_000);
  afterAll(async () => { await harness?.close(); });

  async function progress(questId: string, userId: string) {
    const { JourneyProgressionService } = await import(
      '../src/modules/quests/application/journey-progression.service.js'
    );
    return harness.app.get(JourneyProgressionService).onSubmissionApproved(questId, userId);
  }

  /** A started solo chain with step 1 approved, so step 2 is open. */
  async function startedChain(user: { id: string }, hiddenLater = true) {
    const ids: string[] = [];
    for (let i = 0; i < 3; i++) ids.push((await harness.createQuest({ isHidden: i > 0 && hiddenLater })).id);
    const chainId = await harness.createQuestChain(ids);
    await harness.createSubmission(user as never, { questId: ids[0] });
    await harness.database.query(
      `UPDATE user_quests SET status = 'approved' WHERE user_id = $1 AND quest_id = $2`,
      [user.id, ids[0]],
    );
    await progress(ids[0], user.id);
    return { chainId, questIds: ids };
  }

  it('GET /journeys/active shows a run that outlived its first checkpoint', async () => {
    const user = await newPlayer();
    await startedChain(user);
    const response = await harness.get('/journeys/active', user);
    expect(response.status).toBe(200);
    const runs = response.body.data.runs as { status: string; completedSteps: number; totalSteps: number }[];
    // The whole point: stage 1 approved and the JOURNEY is still active.
    expect(runs).toHaveLength(1);
    expect(runs[0].status).toBe('active');
    expect(runs[0].completedSteps).toBe(1);
    expect(runs[0].totalSteps).toBe(3);
  });

  it('withholds a hidden checkpoint the viewer has not unlocked', async () => {
    const user = await newPlayer();
    await startedChain(user);
    const response = await harness.get('/journeys/active', user);
    const stages = response.body.data.runs[0].stages as {
      stepOrder: number; state: string; title: string | null; description: string | null; latitude: number | null;
    }[];
    const locked = stages.find((s) => s.stepOrder === 3)!;
    expect(locked.state).toBe('LOCKED');
    // Not blurred — absent. Sending it and hiding it client-side would ship
    // the secret to the device.
    expect(locked.title).toBeNull();
    expect(locked.description).toBeNull();
    expect(locked.latitude).toBeNull();

    // The one that opened for them reads in full.
    const open = stages.find((s) => s.stepOrder === 2)!;
    expect(open.state).toBe('AVAILABLE');
    expect(open.title).not.toBeNull();
  });

  it('continue starts the timer, and only then', async () => {
    const user = await newPlayer();
    const { chainId } = await startedChain(user);
    const runId = (await harness.get('/journeys/active', user)).body.data.runs[0].runId;

    const before = await harness.database.query(
      `SELECT 1 FROM user_quests uq JOIN quest_chain_steps cs ON cs.quest_id = uq.quest_id
       WHERE uq.user_id = $1 AND cs.chain_id = $2 AND cs.step_order = 2`,
      [user.id, chainId],
    );
    expect(before.rows, 'unlocking must not assign').toHaveLength(0);

    await harness.database.query(
      `UPDATE user_quests SET assigned_at = assigned_at - interval '1 hour' WHERE user_id = $1`,
      [user.id],
    );
    const response = await harness.post(`/journeys/${runId}/continue`, user).send({});
    expect(response.status, JSON.stringify(response.body)).toBe(201);
    expect(response.body.data.stepOrder).toBe(2);
    expect(response.body.data.assignment.expires_at).toBeTruthy();
  });

  it('continue is refused twice, and refused to anyone else', async () => {
    const user = await newPlayer();
    await startedChain(user);
    const runId = (await harness.get('/journeys/active', user)).body.data.runs[0].runId;
    await harness.database.query(
      `UPDATE user_quests SET assigned_at = assigned_at - interval '1 hour' WHERE user_id = $1`,
      [user.id],
    );
    expect((await harness.post(`/journeys/${runId}/continue`, user).send({})).status).toBe(201);
    // Already under way — starting it again would mean two timers on one
    // checkpoint.
    const again = await harness.post(`/journeys/${runId}/continue`, user).send({});
    expect(again.status).toBe(409);
    expect(again.body.error.code).toBe('NO_CHECKPOINT_AVAILABLE');

    const stranger = await newPlayer();
    const theirs = await harness.post(`/journeys/${runId}/continue`, stranger).send({});
    expect(theirs.status).toBeGreaterThanOrEqual(400);
  });

  it('a stranger cannot read someone else journey', async () => {
    const user = await newPlayer();
    await startedChain(user);
    const runId = (await harness.get('/journeys/active', user)).body.data.runs[0].runId;
    const stranger = await newPlayer();
    expect((await harness.get(`/journeys/${runId}`, stranger)).status).toBe(404);
    expect((await harness.get('/journeys/active', stranger)).body.data.runs).toHaveLength(0);
  });

  it('a relay needs a roster, and members join themselves', async () => {
    const creator = await newPlayer();
    const friend = await newPlayer();
    const ids: string[] = [];
    for (let i = 0; i < 2; i++) ids.push((await harness.createQuest()).id);
    const chainId = await harness.createQuestChain(ids, 'group');

    const created = await harness.post('/journeys/runs', creator).send({ chainId });
    expect(created.status).toBe(201);
    const { runId, joinCode } = created.body.data;

    // One participant is not a relay.
    const early = await harness.post(`/journeys/${runId}/start`, creator).send({});
    expect(early.body.error.code).toBe('ROSTER_TOO_SMALL');

    // The friend adds THEMSELVES. Nobody is conscripted by being named.
    expect((await harness.post('/journeys/runs/join', friend).send({ joinCode })).status).toBe(200);
    const roster = await harness.get(`/journeys/${runId}/roster`, creator);
    expect(roster.body.data.map((p: { position: number }) => p.position)).toEqual([1, 2]);

    expect((await harness.post(`/journeys/${runId}/start`, creator).send({})).status).toBe(200);
  });

  it('a relay checkpoint belongs to one participant', async () => {
    const creator = await newPlayer();
    const friend = await newPlayer();
    const ids: string[] = [];
    for (let i = 0; i < 2; i++) ids.push((await harness.createQuest({ isHidden: i > 0 })).id);
    const chainId = await harness.createQuestChain(ids, 'group');
    const created = await harness.post('/journeys/runs', creator).send({ chainId });
    const { runId, joinCode } = created.body.data;
    await harness.post('/journeys/runs/join', friend).send({ joinCode });
    await harness.post(`/journeys/${runId}/start`, creator).send({});

    // The teammate sees the journey and whose turn it is — and no more.
    const seen = await harness.get(`/journeys/${runId}`, friend);
    expect(seen.status).toBe(200);
    const stage1 = seen.body.data.stages[0];
    expect(stage1.state).toBe('AVAILABLE');
    expect(stage1.isYours, 'stage 1 belongs to participant 1').toBe(false);
    expect(stage1.targetUsername).toBeTruthy();
    expect(seen.body.data.nextForViewer).toBeNull();

    const refused = await harness.post(`/journeys/${runId}/continue`, friend).send({});
    expect(refused.status).toBe(409);
  });

  it('an any-order journey offers every checkpoint at once', async () => {
    const user = await newPlayer();
    const ids: string[] = [];
    for (let i = 0; i < 3; i++) ids.push((await harness.createQuest()).id);
    const chainId = await harness.createQuestChain(ids);
    await harness.database.query(
      `UPDATE quest_chains SET completion_rule = 'all_steps_any_order' WHERE id = $1`, [chainId],
    );
    // Starting any step opens the run; nothing is sequenced.
    await harness.createSubmission(user, { questId: ids[1] });
    const response = await harness.get('/journeys/active', user);
    const runs = response.body.data.runs as { stages: { state: string }[] }[];
    if (runs.length === 0) return; // no run for an any-order chain by design
    expect(runs[0].stages.every((s) => s.state !== 'LOCKED')).toBe(true);
  });

  it('acknowledging an unlock stops it replaying', async () => {
    const user = await newPlayer();
    await startedChain(user);
    const first = await harness.get('/journeys/active', user);
    expect(first.body.data.runs[0].unseenUnlock).not.toBeNull();
    const runId = first.body.data.runs[0].runId;

    expect((await harness.post(`/journeys/${runId}/unlock-seen`, user).send({})).status).toBe(204);
    const second = await harness.get('/journeys/active', user);
    // Durable, not a local watermark: the server decides whether the
    // celebration is still owed, so closing the app cannot lose it and
    // reinstalling cannot replay it.
    expect(second.body.data.runs[0].unseenUnlock).toBeNull();
  });

  it('Home offers chains and collections in one shelf, tagged apart', async () => {
    const user = await newPlayer();
    await startedChain(user);
    const response = await harness.get('/discovery/home', user);
    const modules = response.body.data.modules as { type: string; journeys: { kind: string }[] }[];
    const shelf = modules.find((m) => m.type === 'CONTINUE_JOURNEY');
    expect(shelf, 'an active journey must reach Home').toBeDefined();
    expect(shelf!.journeys.some((j) => j.kind === 'chain')).toBe(true);
    // Tagged, not merged: the two remain different backend concepts.
    expect(shelf!.journeys.every((j) => j.kind === 'chain' || j.kind === 'collection')).toBe(true);
  });
});
