import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestQuest, type TestUser } from './support/e2e-harness.js';

// The one-active-quest rule and the reroll cap are the two limits a client
// could trivially bypass by firing the same request twice, so both have to be
// enforced by the server and backed by the database rather than by UI state.
describe('quest assignment limits (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  describe('one active quest per user', () => {
    let user: TestUser;
    let questA: TestQuest;
    let questB: TestQuest;

    beforeAll(async () => {
      user = await harness.createUser({ prefix: 'q1' });
      questA = await harness.createQuest();
      questB = await harness.createQuest();
    }, 300_000);

    it('assigns the first quest', async () => {
      const response = await harness.post('/quests/assign', user).send({ questId: questA.id });
      expect(response.status).toBe(201);
      expect(response.body.data.quest_id).toBe(questA.id);
      expect(response.body.data.status).toBe('assigned');
      harness.track(response.body.data.id);

      expect(
        await harness.countRows(
          `SELECT count(*) FROM user_quests WHERE user_id = $1 AND status IN ('assigned', 'submitted')`,
          [user.id],
        ),
      ).toBe(1);
    });

    it('rejects a second quest with ACTIVE_QUEST_EXISTS', async () => {
      const response = await harness.post('/quests/assign', user).send({ questId: questB.id }).expect(409);
      expect(response.body.error.code).toBe('ACTIVE_QUEST_EXISTS');
    });

    it('rejects re-assigning the quest the user is already on', async () => {
      const response = await harness.post('/quests/assign', user).send({ questId: questA.id }).expect(409);
      expect(response.body.error.code).toBe('ACTIVE_QUEST_EXISTS');
    });

    // Deliberately inverted in migration 0021. This previously asserted that
    // a submitted quest still blocked a new assignment. It no longer does:
    // review latency is not something a user can clear, so being locked out
    // until a moderator arrived was a dead end. One *assigned* quest is still
    // enforced, by user_quests_one_assigned_idx.
    it('lets a new quest be assigned while an earlier one awaits review', async () => {
      const mediaUrl = await harness.createMediaObject(user);
      const submission = await harness
        .post('/submissions', user)
        .send({
          userQuestId: await harness.activeUserQuestId(user),
          mediaUrl,
          mediaType: 'image',
          showInFeed: true,
        })
        .expect(201);
      harness.track(submission.body.data.id);

      // The submitted quest stays submitted — it is not displaced or expired,
      // because that would discard proof no moderator has judged yet.
      const assigned = await harness
        .post('/quests/assign', user)
        .send({ questId: questB.id })
        .expect(201);
      expect(assigned.body.data.status).toBe('assigned');

      // ...and the new quest is now the only active one, so a *third*
      // assignment is still refused.
      const third = await harness
        .post('/quests/assign', user)
        .send({ questId: questA.id })
        .expect(409);
      expect(third.body.error.code).toBe('ACTIVE_QUEST_EXISTS');
    });
  });

  describe('two near-simultaneous assignments', () => {
    it('lets exactly one through and rejects the other', async () => {
      const user = await harness.createUser({ prefix: 'q2' });
      const quest = await harness.createQuest();

      const [first, second] = await Promise.all([
        harness.post('/quests/assign', user).send({ questId: quest.id }),
        harness.post('/quests/assign', user).send({ questId: quest.id }),
      ]);

      const statuses = [first.status, second.status].sort((a, b) => a - b);
      expect(statuses).toEqual([201, 409]);

      const loser = first.status === 409 ? first : second;
      expect(loser.body.error.code).toBe('ACTIVE_QUEST_EXISTS');

      const winner = first.status === 201 ? first : second;
      harness.track(winner.body.data.id);

      expect(
        await harness.countRows(
          `SELECT count(*) FROM user_quests WHERE user_id = $1 AND status IN ('assigned', 'submitted')`,
          [user.id],
        ),
      ).toBe(1);
    });

    it('is backed by a partial unique index, not only by the service check', async () => {
      const user = await harness.createUser({ prefix: 'q3' });
      const quest = await harness.createQuest();
      const assignment = await harness.assignQuest(user, quest.id);
      expect(assignment.id).toBeTruthy();

      // Bypassing the service entirely must still fail: the advisory lock in
      // assignSpecific only serialises callers that take it, so the
      // one-in-progress index is the real guarantee.
      await expect(
        harness.database.query(
          `INSERT INTO user_quests (user_id, quest_id, expires_at)
           VALUES ($1, $2, now() + interval '4 hours')`,
          [user.id, quest.id],
        ),
      ).rejects.toMatchObject({ code: '23505' });
    });
  });

  describe('reroll cap', () => {
    let user: TestUser;

    beforeAll(async () => {
      user = await harness.createUser({ prefix: 'q4' });
    }, 300_000);

    it('starts at five remaining', async () => {
      const response = await harness.get('/quests/rerolls/remaining', user).expect(200);
      expect(response.body.data.remaining).toBe(5);
    });

    // The budget is spent by GET /quests/picker, because that is the call
    // that hands out options. It used to be spent only by POST
    // /quests/rerolls — a bookkeeping route the client called voluntarily —
    // so a caller who simply never called it could spin the picker forever
    // and take any result. These exercise the path intake actually uses.
    it('the first spin of a cycle is free', async () => {
      await harness.get('/quests/picker?count=3', user).expect(200);
      expect(
        (await harness.get('/quests/rerolls/remaining', user).expect(200)).body.data.remaining,
      ).toBe(5);
      expect(
        await harness.countRows('SELECT count(*) FROM quest_reroll_log WHERE user_id = $1 AND charged', [user.id]),
      ).toBe(0);
      // The free spin is still recorded, as the marker that says the cycle
      // has started — without it the second spin cannot tell itself apart
      // from the first, and the cap never engages.
      expect(
        await harness.countRows('SELECT count(*) FROM quest_reroll_log WHERE user_id = $1 AND NOT charged', [user.id]),
      ).toBe(1);
    });

    it('counts down one per re-spin and reports the same number on the read route', async () => {
      for (const expected of [4, 3, 2, 1, 0]) {
        await harness.get('/quests/picker?count=3', user).expect(200);
        const remaining = await harness.get('/quests/rerolls/remaining', user).expect(200);
        expect(remaining.body.data.remaining).toBe(expected);
      }

      expect(
        await harness.countRows('SELECT count(*) FROM quest_reroll_log WHERE user_id = $1 AND charged', [user.id]),
      ).toBe(5);
    });

    it('refuses the sixth spin inside the window — the hole this closes', async () => {
      // Before the gate moved, this returned a fresh set of options at zero
      // remaining, and every one of them was assignable.
      const response = await harness.get('/quests/picker?count=3', user).expect(409);
      expect(response.body.error.code).toBe('REROLL_LIMIT_REACHED');

      // A refused spin must not be logged, or the window would never clear.
      expect(
        await harness.countRows('SELECT count(*) FROM quest_reroll_log WHERE user_id = $1 AND charged', [user.id]),
      ).toBe(5);
    });

    it('the read route reports the cap but no longer spends it', async () => {
      // Kept as a read for the build already in TestFlight, which calls it
      // right after the picker. If it still charged, every spin would cost
      // two rerolls.
      await harness.post('/quests/rerolls', user).send().expect(409);
      expect(
        await harness.countRows('SELECT count(*) FROM quest_reroll_log WHERE user_id = $1 AND charged', [user.id]),
      ).toBe(5);
    });

    it('is a rolling window: rerolls older than 24 hours stop counting', async () => {
      // Ageing the log rows is the only way to move the window without
      // waiting a day; the cap is computed from rerolled_at on every call.
      await harness.database.query(
        // Age the oldest CHARGED row: the cap counts only those, and the
        // oldest row overall is now the cycle's uncharged free-spin marker.
        `UPDATE quest_reroll_log SET rerolled_at = now() - interval '25 hours'
         WHERE id = (
           SELECT id FROM quest_reroll_log
           WHERE user_id = $1 AND charged ORDER BY rerolled_at LIMIT 1
         )`,
        [user.id],
      );

      expect((await harness.get('/quests/rerolls/remaining', user).expect(200)).body.data.remaining).toBe(1);
      // One spin left, spent by the picker; the next is refused.
      await harness.get('/quests/picker?count=3', user).expect(200);
      expect((await harness.get('/quests/rerolls/remaining', user).expect(200)).body.data.remaining).toBe(0);
      await harness.get('/quests/picker?count=3', user).expect(409);
    });

    it('keeps the cap per user', async () => {
      const other = await harness.createUser({ prefix: 'q5' });
      expect((await harness.get('/quests/rerolls/remaining', other).expect(200)).body.data.remaining).toBe(5);
    });

    it('requires a token', async () => {
      await harness.get('/quests/rerolls/remaining').expect(401);
      await harness.post('/quests/rerolls').send().expect(401);
      await harness.get('/quests/picker?count=3').expect(401);
    });

    it('taking a quest starts a new cycle, so the next spin is free again', async () => {
      const fresh = await harness.createUser({ prefix: 'q4b' });

      // Spin twice: the first is free, the second costs one.
      await harness.get('/quests/picker?count=3', fresh).expect(200);
      const options = await harness.get('/quests/picker?count=3', fresh).expect(200);
      expect(
        (await harness.get('/quests/rerolls/remaining', fresh).expect(200)).body.data.remaining,
      ).toBe(4);

      // Take one, which ends the cycle.
      const quest = options.body.data[0];
      await harness.post('/quests/assign', fresh).send({ questId: quest.id }).expect(201);
      await harness.post('/quests/abandon', fresh).send({ userQuestId: (
        await harness.get('/quests/active', fresh).expect(200)
      ).body.data.id }).expect(204);

      // The first spin of the new cycle is free.
      await harness.get('/quests/picker?count=3', fresh).expect(200);
      expect(
        (await harness.get('/quests/rerolls/remaining', fresh).expect(200)).body.data.remaining,
      ).toBe(4);
    }, 300_000);
  });

  describe('POST /quests/admin/assign', () => {
    let moderator: TestUser;
    let target: TestUser;
    let inFlight: TestQuest;
    let override: TestQuest;
    let displacedId: string;

    beforeAll(async () => {
      moderator = await harness.createUser({ role: 'moderator', prefix: 'q6' });
      target = await harness.createUser({ prefix: 'q7' });
      inFlight = await harness.createQuest();
      override = await harness.createQuest();
      displacedId = (await harness.assignQuest(target, inFlight.id)).id;
    }, 300_000);

    it('displaces the target user in-flight quest instead of rejecting', async () => {
      const response = await harness
        .post('/quests/admin/assign', moderator)
        .send({ userId: target.id, questId: override.id })
        .expect(201);

      expect(response.body.data.user_id).toBe(target.id);
      expect(response.body.data.quest_id).toBe(override.id);
      expect(response.body.data.status).toBe('assigned');
      harness.track(response.body.data.id);

      expect(await harness.userQuestStatus(displacedId)).toBe('expired');
      expect(
        await harness.countRows(
          `SELECT count(*) FROM user_quests WHERE user_id = $1 AND status IN ('assigned', 'submitted')`,
          [target.id],
        ),
      ).toBe(1);

      // The override still notifies the user and emits the assignment event.
      const events = await harness.outboxEvents(response.body.data.id, 'quest.assigned');
      expect(events).toHaveLength(1);
      const notifications = await harness.notificationsFor(target.id, response.body.data.id);
      expect(notifications.map((row) => row.type)).toContain('quest_assigned');
    });

    it('refuses an unknown or inactive quest', async () => {
      const inactive = await harness.createQuest({ isActive: false });
      const response = await harness
        .post('/quests/admin/assign', moderator)
        .send({ userId: target.id, questId: inactive.id })
        .expect(404);
      expect(response.body.error.code).toBe('QUEST_NOT_FOUND');

      // The override expires the in-flight quest before it validates the new
      // one, so a rejected override has to roll that expiry back.
      expect(
        await harness.countRows(
          `SELECT count(*) FROM user_quests WHERE user_id = $1 AND status IN ('assigned', 'submitted')`,
          [target.id],
        ),
      ).toBe(1);
    });

    it('requires a moderator or super_admin', async () => {
      await harness
        .post('/quests/admin/assign')
        .send({ userId: target.id, questId: override.id })
        .expect(401);

      const plain = await harness.createUser({ prefix: 'q8' });
      const response = await harness
        .post('/quests/admin/assign', plain)
        .send({ userId: target.id, questId: override.id })
        .expect(403);
      expect(response.body.error.code).toBe('INSUFFICIENT_PERMISSION');
    });

    it('does not let a plain user displace their own quest through the user route', async () => {
      const other = await harness.createQuest();
      const response = await harness.post('/quests/assign', target).send({ questId: other.id }).expect(409);
      expect(response.body.error.code).toBe('ACTIVE_QUEST_EXISTS');
    });
  });
});
