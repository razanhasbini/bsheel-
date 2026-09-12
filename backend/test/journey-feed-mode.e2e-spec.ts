import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/**
 * A journey posted as one route instead of three photographs (0047).
 *
 * The whole feature is a promise about timing — nothing reaches the feed
 * until the route is finished, and then exactly one thing does — so every
 * test here is about what is visible at a given moment rather than about any
 * single row. That is also the only way to catch the failure that would hurt
 * most: a stop leaking into the feed on its own can never be pulled back into
 * the route afterwards, because by then it has its own comments.
 */
describe('journey feed mode (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let admin: TestUser;
  let counter = 0;
  const newPlayer = () => harness.createUser({ prefix: `jf${counter++}` });

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    admin = await harness.createUser({ role: 'super_admin', prefix: 'jfadm' });
  }, 300_000);
  afterAll(async () => { await harness?.close(); });

  async function soloChain(steps = 3): Promise<{ chainId: string; questIds: string[] }> {
    const questIds: string[] = [];
    for (let i = 0; i < steps; i++) questIds.push((await harness.createQuest()).id);
    return { chainId: await harness.createQuestChain(questIds), questIds };
  }

  /** The run the player is on, which only exists once step 1 is assigned. */
  async function runIdFor(chainId: string): Promise<string> {
    const result = await harness.database.query<{ id: string }>(
      `SELECT id FROM quest_chain_runs WHERE chain_id = $1`, [chainId],
    );
    return result.rows[0].id;
  }

  async function progress(questId: string, user: TestUser) {
    const { JourneyProgressionService } = await import(
      '../src/modules/quests/application/journey-progression.service.js'
    );
    return harness.app.get(JourneyProgressionService).onSubmissionApproved(questId, user.id);
  }

  /**
   * Submit against an assignment that already exists.
   *
   * The fixture's createSubmission assigns first, and the run only exists
   * once step 1 has been assigned — so a test that needs to choose the feed
   * mode before submitting has to split the two, which is also the order the
   * app does them in.
   */
  async function submitFor(user: TestUser, assignmentId: string): Promise<{ id: string }> {
    const response = await harness.post('/submissions', user).send({
      userQuestId: assignmentId,
      mediaUrl: await harness.createMediaObject(user),
      mediaType: 'image',
      showInFeed: true,
    });
    if (response.status !== 201) {
      throw new Error(`submit failed: ${response.status} ${JSON.stringify(response.body)}`);
    }
    return response.body.data;
  }

  /** Assign, submit and approve one checkpoint. */
  async function clear(user: TestUser, questId: string): Promise<{ id: string }> {
    const assignment = await harness.assignQuest(user, questId);
    const submission = await submitFor(user, assignment.id);
    await harness.post(`/submissions/${submission.id}/approve`, admin).send({}).expect(204);
    await progress(questId, user);
    return submission;
  }

  async function inFeed(user: TestUser, submissionId: string): Promise<boolean> {
    const response = await harness.get('/feed?limit=50', user).expect(200);
    return (response.body.data as { submission_id: string }[])
      .some((post) => post.submission_id === submissionId);
  }

  // The guard, asserted before the happy path so a regression in it cannot
  // hide behind the feature otherwise working.
  it('refuses the choice once a checkpoint has been submitted', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain(2);
    const assignment = await harness.assignQuest(user, questIds[0]);
    await submitFor(user, assignment.id);

    const late = await harness
      .post(`/journeys/${await runIdFor(chainId)}/feed-mode`, user)
      .send({ mode: 'one_post' })
      .expect(200);
    expect(late.body.data.applied).toBe(false);
  });

  it('holds the stops back and publishes one post carrying all of them', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain();

    // Assign step 1 without submitting: the run exists and the choice is
    // still open, which is exactly the state the app asks in.
    const first = await harness.assignQuest(user, questIds[0]);
    const runId = await runIdFor(chainId);
    const chosen = await harness.post(`/journeys/${runId}/feed-mode`, user)
      .send({ mode: 'one_post' }).expect(200);
    expect(chosen.body.data.applied).toBe(true);

    const firstSubmission = await submitFor(user, first.id);
    await harness.post(`/submissions/${firstSubmission.id}/approve`, admin).send({}).expect(204);
    await progress(questIds[0], user);

    // Asked for show_in_feed true and did not get it. The rule is the
    // server's, not the switch's.
    expect(await inFeed(user, firstSubmission.id)).toBe(false);

    const second = await clear(user, questIds[1]);
    expect(await inFeed(user, second.id)).toBe(false);

    const third = await clear(user, questIds[2]);

    // The last checkpoint anchors the route: one post, not three.
    expect(await inFeed(user, third.id)).toBe(true);
    expect(await inFeed(user, firstSubmission.id)).toBe(false);
    expect(await inFeed(user, second.id)).toBe(false);

    const feed = await harness.get('/feed?limit=50', user).expect(200);
    const post = (feed.body.data as Record<string, unknown>[])
      .find((row) => row.submission_id === third.id)!;
    const stops = post.journey_stops as { submission_id: string; step_order: number }[];
    expect(stops).toHaveLength(3);
    expect(stops.map((stop) => stop.step_order)).toEqual([1, 2, 3]);
    expect(stops.map((stop) => stop.submission_id))
      .toEqual([firstSubmission.id, second.id, third.id]);
    expect(post.journey_title).toBeTruthy();

    const run = await harness.database.query<{ status: string }>(
      `SELECT status FROM quest_chain_runs WHERE id = $1`, [runId],
    );
    expect(run.rows[0].status).toBe('completed');
  });

  it('leaves a journey nobody chose for posting per stop', async () => {
    const user = await newPlayer();
    const { questIds } = await soloChain(2);
    const first = await clear(user, questIds[0]);

    expect(await inFeed(user, first.id)).toBe(true);
    const feed = await harness.get('/feed?limit=50', user).expect(200);
    const post = (feed.body.data as Record<string, unknown>[])
      .find((row) => row.submission_id === first.id)!;
    expect(post.journey_stops).toBeNull();
  });

  it('tells the client whether the choice is still open', async () => {
    const user = await newPlayer();
    const { chainId, questIds } = await soloChain(2);
    const assignment = await harness.assignQuest(user, questIds[0]);
    const runId = await runIdFor(chainId);

    const open = await harness.get(`/journeys/${runId}`, user).expect(200);
    expect(open.body.data.canChooseFeedMode).toBe(true);
    expect(open.body.data.feedMode).toBeNull();

    await harness.post(`/journeys/${runId}/feed-mode`, user).send({ mode: 'one_post' }).expect(200);
    await submitFor(user, assignment.id);

    const closed = await harness.get(`/journeys/${runId}`, user).expect(200);
    expect(closed.body.data.feedMode).toBe('one_post');
    expect(closed.body.data.canChooseFeedMode).toBe(false);
  });

  it('refuses a run the caller is not on', async () => {
    const owner = await newPlayer();
    const stranger = await newPlayer();
    const { chainId, questIds } = await soloChain(2);
    await harness.assignQuest(owner, questIds[0]);
    const runId = await runIdFor(chainId);

    const attempt = await harness.post(`/journeys/${runId}/feed-mode`, stranger)
      .send({ mode: 'one_post' }).expect(200);
    expect(attempt.body.data.applied).toBe(false);
    const run = await harness.database.query<{ feed_mode: string | null }>(
      `SELECT feed_mode FROM quest_chain_runs WHERE id = $1`, [runId],
    );
    expect(run.rows[0].feed_mode).toBeNull();
  });
});
