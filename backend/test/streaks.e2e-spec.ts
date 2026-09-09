import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';
import { StreakReminderService } from '../src/modules/profiles/application/streak-reminder.service.js';

// Streaks (#46). Before this, no streak existed anywhere: no column, no
// query, and a BsStreakFlame widget documented as "Pure visual; doesn't
// itself fetch streak data". The number on the home screen was decoration.
//
// A streak is the run of consecutive UTC days with at least one APPROVED
// submission, counted by `submitted_at`. The review date is deliberately not
// used: a moderation backlog would otherwise break a streak the user cannot
// protect.
describe('streaks (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let moderator: TestUser;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    moderator = await harness.createUser({ role: 'super_admin', prefix: 'streakmod' });
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  /// Completes one quest and approves it, then backdates the submission so
  /// it lands `daysAgo` days back.
  async function approvedDay(user: TestUser, daysAgo: number) {
    const quest = await harness.createQuest({ xpReward: 10 });
    await harness.assignQuest(user, quest.id);
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
    await harness
      .post(`/submissions/${created.body.data.id}/approve`, moderator)
      .send({})
      .expect(204);
    if (daysAgo > 0) await harness.backdateSubmission(created.body.data.id, daysAgo);
    return created.body.data.id as string;
  }

  const streakOf = async (user: TestUser) =>
    (await harness.get('/profiles/me/streak', user).expect(200)).body.data;

  it('reports a real zero rather than a fabricated number', async () => {
    const user = await harness.createUser({ prefix: 'st0' });
    const streak = await streakOf(user);
    expect(streak.current).toBe(0);
    expect(streak.longest).toBe(0);
    expect(streak.lastDay).toBeNull();
    expect(streak.atRisk).toBe(false);
  });

  it('counts consecutive approved days', async () => {
    const user = await harness.createUser({ prefix: 'st3' });
    await approvedDay(user, 2);
    await approvedDay(user, 1);
    await approvedDay(user, 0);

    const streak = await streakOf(user);
    expect(streak.current).toBe(3);
    expect(streak.longest).toBe(3);
    // Submitted today, so it does not die tonight.
    expect(streak.atRisk).toBe(false);
  });

  it('treats a streak whose last day was yesterday as alive but at risk', async () => {
    const user = await harness.createUser({ prefix: 'stRisk' });
    await approvedDay(user, 2);
    await approvedDay(user, 1);

    const streak = await streakOf(user);
    expect(streak.current).toBe(2);
    expect(streak.atRisk).toBe(true);
  });

  it('breaks the current run on a missed day but keeps the longest', async () => {
    const user = await harness.createUser({ prefix: 'stGap' });
    // A 3-day run a week ago, then nothing until today.
    await approvedDay(user, 9);
    await approvedDay(user, 8);
    await approvedDay(user, 7);
    await approvedDay(user, 0);

    const streak = await streakOf(user);
    expect(streak.current).toBe(1);
    expect(streak.longest).toBe(3);
  });

  it('does not count a rejected submission', async () => {
    const user = await harness.createUser({ prefix: 'stRej' });
    const quest = await harness.createQuest({ xpReward: 10 });
    await harness.assignQuest(user, quest.id);
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
    await harness
      .post(`/submissions/${created.body.data.id}/reject`, moderator)
      .send({ reviewNote: 'not it' })
      .expect(204);

    const streak = await streakOf(user);
    expect(streak.current).toBe(0);
  });

  it('is visible on another user’s profile', async () => {
    const owner = await harness.createUser({ prefix: 'stOwner' });
    const viewer = await harness.createUser({ prefix: 'stViewer' });
    await approvedDay(owner, 0);

    const response = await harness.get(`/profiles/${owner.id}/streak`, viewer).expect(200);
    expect(response.body.data.current).toBe(1);
  });

  // ── the daily "your streak dies tonight" reminder ──────────────────
  //
  // The reminder only makes sense for a streak whose last approved day is
  // yesterday: today's is already safe, and one that lapsed earlier is gone.
  // It must fire at most once per user per day however often the sweep runs,
  // because the job is hourly — a fixed daily hour would reach half the users
  // after their streak had already lapsed.
  describe('streak-at-risk reminder', () => {
    const sweep = () => harness.app.get(StreakReminderService).sweep();

    it('reminds a user whose streak expires tonight, exactly once a day', async () => {
      const user = await harness.createUser({ prefix: 'stRem' });
      await approvedDay(user, 2);
      await approvedDay(user, 1);

      await sweep();
      const notes = await harness.notificationsFor(user.id);
      const reminders = notes.filter((n) => n.type === 'streak_at_risk');
      expect(reminders.length).toBe(1);
      expect(reminders[0].title).toContain('2-day streak');
      expect(await harness.streakReminderSentOn(user.id)).not.toBeNull();

      // A second sweep the same day must add nothing.
      await sweep();
      const after = (await harness.notificationsFor(user.id))
        .filter((n) => n.type === 'streak_at_risk');
      expect(after.length).toBe(1);
    });

    it('does not remind a user who already submitted today', async () => {
      const user = await harness.createUser({ prefix: 'stSafe' });
      await approvedDay(user, 1);
      await approvedDay(user, 0);

      await sweep();
      const notes = await harness.notificationsFor(user.id);
      expect(notes.some((n) => n.type === 'streak_at_risk')).toBe(false);
    });

    it('does not remind a user with no streak to lose', async () => {
      const user = await harness.createUser({ prefix: 'stNone' });
      await sweep();
      const notes = await harness.notificationsFor(user.id);
      expect(notes.some((n) => n.type === 'streak_at_risk')).toBe(false);
    });
  });
});