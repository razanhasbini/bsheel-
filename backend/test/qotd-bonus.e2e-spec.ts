import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

// The Quest-of-the-Day ticket advertises "+N XP" on the home screen before a
// user accepts it. That promise was decorative: bonus_xp was written by the
// admin and read only for display, so approval paid the base reward and the
// bonus silently evaporated. Issue #45.
//
// The bonus is deliberately tied to the day the quest was *taken on*, not the
// day it is reviewed, so a moderation backlog cannot change what a user earns
// — and so yesterday's QOTD quest, rolled randomly today, pays base only.
describe('Quest of the Day bonus XP (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let moderator: TestUser;
  // quest_of_the_day.quest_id is a foreign key, so any row scheduled here
  // must go before the harness deletes the quests it created. A Set because
  // the upsert is keyed on display_date: scheduling "today" twice returns the
  // same row, and deleting it twice would 404.
  const scheduled = new Set<string>();

  const questXp = 120;
  const bonusXp = 50;
  const today = () => new Date().toISOString().slice(0, 10);

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    moderator = await harness.createUser({ role: 'super_admin', prefix: 'qotdmod' });
  }, 300_000);

  afterAll(async () => {
    for (const id of scheduled) {
      // 404 is fine: an earlier upsert on the same date may already have
      // replaced and released this row.
      const response = await harness.delete(`/admin/qotd/${id}`, moderator);
      expect([204, 404]).toContain(response.status);
    }
    await harness?.close();
  });

  async function scheduleQotd(questId: string, displayDate: string) {
    const response = await harness
      .put('/admin/qotd', moderator)
      .send({ questId, displayDate, bonusXp })
      .expect(200);
    const id = response.body.data?.id ?? response.body.id;
    if (id) scheduled.add(id);
    return id as string;
  }

  async function submitAndApprove(user: TestUser) {
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
    return created.body.data.id as string;
  }

  it('pays base reward plus the advertised bonus, and records the total', async () => {
    const quest = await harness.createQuest({ xpReward: questXp });
    await scheduleQotd(quest.id, today());

    const user = await harness.createUser({ prefix: 'qotd1' });
    const before = await harness.profile(user.id);
    await harness.assignQuest(user, quest.id);
    const submissionId = await submitAndApprove(user);

    const after = await harness.profile(user.id);
    expect(after.xp - before.xp).toBe(questXp + bonusXp);

    // The recorded amount must include the bonus, because takedown and
    // restore refund from xp_awarded_amount rather than recomputing.
    const row = await harness.submission(submissionId);
    expect(row.xp_awarded_amount).toBe(questXp + bonusXp);
  });

  it('still notifies the user on approval of a bonus quest', async () => {
    const quest = await harness.createQuest({ xpReward: questXp });
    await scheduleQotd(quest.id, today());

    const user = await harness.createUser({ prefix: 'qotd2' });
    await harness.assignQuest(user, quest.id);
    const submissionId = await submitAndApprove(user);

    // The harness exposes notification type and title but not the body, so
    // the "+N XP (base + bonus)" wording is asserted through
    // xp_awarded_amount above rather than by reading the copy here.
    const notes = await harness.notificationsFor(user.id, submissionId);
    expect(notes.some((n) => n.type === 'submission_approved')).toBe(true);
  });

  it('pays base only for a quest that is not the Quest of the Day', async () => {
    const quest = await harness.createQuest({ xpReward: questXp });
    const user = await harness.createUser({ prefix: 'qotd3' });
    const before = await harness.profile(user.id);
    await harness.assignQuest(user, quest.id);
    await submitAndApprove(user);

    const after = await harness.profile(user.id);
    expect(after.xp - before.xp).toBe(questXp);
  });

  it('does not pay the bonus for a quest scheduled on a different day', async () => {
    const quest = await harness.createQuest({ xpReward: questXp });
    const tomorrow = new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);
    await scheduleQotd(quest.id, tomorrow);

    const user = await harness.createUser({ prefix: 'qotd4' });
    const before = await harness.profile(user.id);
    await harness.assignQuest(user, quest.id);
    await submitAndApprove(user);

    const after = await harness.profile(user.id);
    expect(after.xp - before.xp).toBe(questXp);
  });
});
