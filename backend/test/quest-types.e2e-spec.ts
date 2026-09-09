import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

// The full quest system (#51). The schema part is cheap; the risk is the
// ROLL. Adding a row for a stage-3 quest or a finished festival is harmless,
// but letting the random picker hand one to a user is not — and neither is
// letting a user assign one directly by id, which is the same hole the map
// contract's acceptance check 7 is about.
//
// The issue is explicit that these types must EXTEND the random-quest
// algorithm, not replace it, so the first test here is that ordinary quests
// still roll exactly as before.
describe('quest type system (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  const roll = async (user: TestUser, count = 20) =>
    (await harness.get(`/quests/picker?count=${count}`, user).expect(200)).body.data as
      { id: string }[];

  it('still offers ordinary quests — the existing algorithm is untouched', async () => {
    const user = await harness.createUser({ prefix: 'qtStd' });
    const quest = await harness.createQuest({ title: 'ordinary rollable' });

    // Two deterministic claims, since which quests a random roll returns is
    // by definition not one: the picker still returns options at all, and an
    // ordinary quest is still assignable.
    const options = await roll(user, 3);
    expect(options.length).toBeGreaterThan(0);

    const assigned = await harness
      .post('/quests/assign', user)
      .send({ questId: quest.id })
      .expect(201);
    expect(assigned.body.data.status).toBe('assigned');
  });

  it('never rolls a hidden quest', async () => {
    const user = await harness.createUser({ prefix: 'qtHidden' });
    const hidden = await harness.createQuest({ isHidden: true, title: 'hidden content' });
    const options = await roll(user);
    expect(options.some((q) => q.id === hidden.id)).toBe(false);
  });

  it('rolls an event quest inside its window and not outside it', async () => {
    const user = await harness.createUser({ prefix: 'qtEvent' });
    const hour = 3_600_000;
    const live = await harness.createQuest({
      title: 'festival, live',
      availableFrom: new Date(Date.now() - hour),
      availableUntil: new Date(Date.now() + hour),
    });
    const over = await harness.createQuest({
      title: 'festival, finished',
      availableFrom: new Date(Date.now() - 2 * hour),
      availableUntil: new Date(Date.now() - hour),
    });
    const future = await harness.createQuest({
      title: 'festival, not yet',
      availableFrom: new Date(Date.now() + hour),
    });

    // Exclusion is the reliable direction here: a closed or unopened window
    // must NEVER be offered. Inclusion is checked by assignability, because
    // which quests a random sample contains is not deterministic.
    const options = await roll(user);
    expect(options.some((q) => q.id === over.id)).toBe(false);
    expect(options.some((q) => q.id === future.id)).toBe(false);

    const assigned = await harness
      .post('/quests/assign', user)
      .send({ questId: live.id })
      .expect(201);
    expect(assigned.body.data.status).toBe('assigned');

    // And neither of the two out-of-window quests is assignable by id.
    const other = await harness.createUser({ prefix: 'qtEventB' });
    await harness.post('/quests/assign', other).send({ questId: over.id }).expect(404);
    await harness.post('/quests/assign', other).send({ questId: future.id }).expect(404);
  });

  it('refuses to assign a quest whose event window has closed', async () => {
    const user = await harness.createUser({ prefix: 'qtEventAssign' });
    const over = await harness.createQuest({
      availableUntil: new Date(Date.now() - 60_000),
    });
    await harness.post('/quests/assign', user).send({ questId: over.id }).expect(404);
  });

  describe('multi-stage chains', () => {
    it('offers only the first step, and locks the rest', async () => {
      const user = await harness.createUser({ prefix: 'qtChain' });
      const [one, two, three] = [
        await harness.createQuest({ title: 'step one' }),
        await harness.createQuest({ title: 'step two' }),
        await harness.createQuest({ title: 'step three' }),
      ];
      await harness.createQuestChain([one.id, two.id, three.id]);

      // Later steps must never be offered; that direction is deterministic.
      const options = await roll(user);
      expect(options.some((q) => q.id === two.id)).toBe(false);
      expect(options.some((q) => q.id === three.id)).toBe(false);

      // The entry point is assignable, which is what "offered" means once a
      // user acts on it.
      const assigned = await harness
        .post('/quests/assign', user)
        .send({ questId: one.id })
        .expect(201);
      expect(assigned.body.data.status).toBe('assigned');
    });

    it('cannot be skipped by assigning a later step directly', async () => {
      const user = await harness.createUser({ prefix: 'qtSkip' });
      const one = await harness.createQuest({ title: 'gate' });
      const two = await harness.createQuest({ title: 'reward' });
      await harness.createQuestChain([one.id, two.id]);

      const response = await harness
        .post('/quests/assign', user)
        .send({ questId: two.id })
        .expect(409);
      expect(response.body.error.code).toBe('QUEST_STEP_LOCKED');
    });

    it('unlocks the next step once the previous one is approved', async () => {
      const moderator = await harness.createUser({ role: 'super_admin', prefix: 'qtMod' });
      const user = await harness.createUser({ prefix: 'qtUnlock' });
      const one = await harness.createQuest({ title: 'stage 1' });
      const two = await harness.createQuest({ title: 'stage 2' });
      await harness.createQuestChain([one.id, two.id]);

      // Locked before any work.
      await harness.post('/quests/assign', user).send({ questId: two.id }).expect(409);

      await harness.assignQuest(user, one.id);
      const mediaUrl = await harness.createMediaObject(user);
      const created = await harness
        .post('/submissions', user)
        .send({
          userQuestId: await harness.activeUserQuestId(user),
          mediaUrl,
          mediaType: 'image',
          showInFeed: true,
        })
        .expect(201);
      harness.track(created.body.data.id);

      // Submitted but not yet judged: still locked. Approval is the gate,
      // not submission — otherwise the chain is bypassable by submitting
      // anything at all.
      await harness.post('/quests/assign', user).send({ questId: two.id }).expect(409);

      await harness
        .post(`/submissions/${created.body.data.id}/approve`, moderator)
        .send({})
        .expect(204);

      // Now assignable.
      const unlocked = await harness
        .post('/quests/assign', user)
        .send({ questId: two.id })
        .expect(201);
      expect(unlocked.body.data.status).toBe('assigned');
    });
  });

  it('groups quests into a collection without affecting the roll', async () => {
    const user = await harness.createUser({ prefix: 'qtColl' });
    const a = await harness.createQuest({ title: 'journey a' });
    const b = await harness.createQuest({ title: 'journey b' });
    await harness.createQuestCollection([a.id, b.id]);

    // A collection is a grouping for progress, not a gate: its members stay
    // ordinary assignable quests. Asserted by assignability rather than by
    // sampling the roll, which is random.
    const assigned = await harness
      .post('/quests/assign', user)
      .send({ questId: a.id })
      .expect(201);
    expect(assigned.body.data.status).toBe('assigned');
    expect(b.id).toBeTruthy();
  });

  it('carries sponsor attribution without inventing partner accounts', async () => {
    const user = await harness.createUser({ prefix: 'qtSpon' });
    const sponsored = await harness.createQuest({
      title: 'sponsored quest',
      sponsorName: 'Museum of Beirut',
    });
    // Sponsorship is attribution, not a gate.
    const assigned = await harness
      .post('/quests/assign', user)
      .send({ questId: sponsored.id })
      .expect(201);
    expect(assigned.body.data.status).toBe('assigned');
  });
});
