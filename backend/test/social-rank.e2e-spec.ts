import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

// One social score, every surface (common/ranking/social-rank.sql.ts), and
// the attribution that feeds it (migration 0049). The assertions are about
// AGREEMENT: the post the feed's HOT sort puts first is the post search puts
// first, and the credit a post is given is exactly what the ledgers say
// followed from it — a BSHEEEL raised from the post, the assignment after
// it, the approved submission after that. Nobody's own post credits them.
describe('social rank and post attribution (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let admin: TestUser;
  let alice: TestUser;
  let bob: TestUser;
  let fan: TestUser;
  let questId: string;
  let questTitle: string;
  let quiet: string;
  let loud: string;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    admin = await harness.createUser({ role: 'super_admin', prefix: 'srAdmin' });
    alice = await harness.createUser({ prefix: 'srAlice' });
    bob = await harness.createUser({ prefix: 'srBob' });
    fan = await harness.createUser({ prefix: 'srFan' });
    questTitle = `SocialRank ${randomUUID().slice(0, 8)}`;
    questId = (await harness.createQuest({ title: questTitle })).id;
    // Two approved posts for the same quest: one nobody touched, one that
    // gathered a comment, a save and a BSHEEEL pressed from its card.
    quiet = (await harness.createApprovedPost(alice, admin, { questId })).id;
    loud = (await harness.createApprovedPost(bob, admin, { questId })).id;
    await harness.post(`/social/posts/${loud}/comments`, fan).send({ body: 'this one' }).expect(201);
    await harness.put(`/social/saved/posts/${loud}`, fan).expect(204);
    const press = randomUUID();
    await harness
      .post('/analytics/events', fan)
      .send({
        events: [{
          clientEventId: press,
          eventType: 'quest_bsheeel',
          questId,
          surface: 'feed',
          sourceSubmissionId: loud,
          occurredAt: new Date().toISOString(),
        }],
      })
      .expect(202);
    // The harness backdates fixture assignments to step past the assignment
    // cooldown, which would put the fan's later assignment BEFORE this
    // press. In production the order is press → assign; recreate it by
    // moving the press a day back (the server would clamp a client's own
    // backdating to two hours, so this goes through the database).
    await harness.database.query(
      "UPDATE analytics_events SET occurred_at = now() - interval '1 day' WHERE client_event_id = $1",
      [press],
    );
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  it('HOT ranks the engaged post above the quiet one', async () => {
    const feed = await harness.get('/feed?sort=hot&limit=50', fan).expect(200);
    const ids = (feed.body.data as { submission_id: string }[]).map((p) => p.submission_id);
    expect(ids).toContain(loud);
    expect(ids).toContain(quiet);
    expect(ids.indexOf(loud)).toBeLessThan(ids.indexOf(quiet));
  });

  it('search orders the same quest\'s posts the same way', async () => {
    const search = await harness.get(`/search?q=${encodeURIComponent(questTitle)}`, fan).expect(200);
    const ids = (search.body.data.posts as { id: string }[]).map((p) => p.id);
    expect(ids.indexOf(loud)).toBeLessThan(ids.indexOf(quiet));
  });

  it('credits the post with the BSHEEEL, then the activation, then the verified completion', async () => {
    const before = await harness.get(`/analytics/attribution/posts/${loud}`, bob).expect(200);
    expect(before.body.data).toMatchObject({ bsheeels: 1, activations: 0, completions: 0 });

    // The fan who pressed BSHEEEL from Bob's post now takes the quest and
    // has it approved. Both facts come from user_quests/submissions, not
    // from anything the client reported.
    await harness.createApprovedPost(fan, admin, { questId });
    const after = await harness.get(`/analytics/attribution/posts/${loud}`, bob).expect(200);
    expect(after.body.data).toMatchObject({ bsheeels: 1, activations: 1, completions: 1 });

    // Alice's post caused none of it.
    const other = await harness.get(`/analytics/attribution/posts/${quiet}`, alice).expect(200);
    expect(other.body.data).toMatchObject({ bsheeels: 0, activations: 0, completions: 0 });
  });

  it('is the author\'s to read, and a moderator\'s — nobody else\'s', async () => {
    await harness.get(`/analytics/attribution/posts/${loud}`, fan).expect(404);
    await harness.get(`/analytics/attribution/posts/${loud}`, admin).expect(200);
    await harness.get(`/analytics/attribution/posts/${randomUUID()}`, bob).expect(404);
  });

  it('drops a source post that does not exist without losing the event', async () => {
    const clientEventId = randomUUID();
    const response = await harness
      .post('/analytics/events', fan)
      .send({
        events: [{
          clientEventId,
          eventType: 'quest_detail_view',
          questId,
          surface: 'feed',
          sourceSubmissionId: randomUUID(),
          occurredAt: new Date().toISOString(),
        }],
      })
      .expect(202);
    expect(response.body.data.recorded).toBe(1);
    const stored = await harness.countRows(
      'SELECT count(*) AS count FROM analytics_events WHERE client_event_id = $1 AND source_submission_id IS NULL',
      [clientEventId],
    );
    expect(stored).toBe(1);
  });
});
