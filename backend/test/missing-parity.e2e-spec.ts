import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AuthRepository } from '../src/modules/auth/infrastructure/auth.repository.js';
import { QuestMaintenanceService } from '../src/modules/quests/application/quest-maintenance.service.js';
import { E2eHarness } from './support/e2e-harness.js';

describe('restored legacy parity (e2e)', { timeout: 300_000 }, () => {
  let harness: E2eHarness;
  let maintenance: QuestMaintenanceService;
  let auth: AuthRepository;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    maintenance = harness.app.get(QuestMaintenanceService);
    auth = harness.app.get(AuthRepository);
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  it('expires overdue assignments and sends each timer/expiry notification once', async () => {
    const user = await harness.createUser({ prefix: 'pm1' });
    const quest = await harness.createQuest();
    const assignment = await harness.assignQuest(user, quest.id);

    await harness.database.query(
      `UPDATE user_quests
       SET assigned_at = now() - interval '1 hour', expires_at = now() + interval '30 minutes'
       WHERE id = $1`,
      [assignment.id],
    );
    await maintenance.expireAndWarn();
    await maintenance.expireAndWarn();
    expect(
      await harness.countRows(
        `SELECT count(*) FROM notifications
         WHERE user_id = $1 AND reference_id = $2 AND type = 'quest_timer_warning'`,
        [user.id, assignment.id],
      ),
    ).toBe(1);

    await harness.database.query(
      `UPDATE user_quests SET expires_at = now() - interval '1 second' WHERE id = $1`,
      [assignment.id],
    );
    await maintenance.expireAndWarn();
    await maintenance.expireAndWarn();
    expect(await harness.userQuestStatus(assignment.id)).toBe('expired');
    expect(
      await harness.countRows(
        `SELECT count(*) FROM notifications
         WHERE user_id = $1 AND reference_id = $2 AND type = 'quest_expired'`,
        [user.id, assignment.id],
      ),
    ).toBe(1);
  });

  it('reminds every admin about stale pending review only once per 24 hours', async () => {
    const moderator = await harness.createUser({
      role: 'moderator',
      prefix: 'pm2',
    });
    const author = await harness.createUser({ prefix: 'pm3' });
    const submission = await harness.createSubmission(author);
    await harness.database.query(
      `UPDATE submissions SET submitted_at = now() - interval '25 hours' WHERE id = $1`,
      [submission.id],
    );

    await maintenance.remindPendingReviews();
    await maintenance.remindPendingReviews();
    expect(
      await harness.countRows(
        `SELECT count(*) FROM notifications
         WHERE user_id = $1 AND type = 'pending_review_reminder'`,
        [moderator.id],
      ),
    ).toBe(1);
  });

  it('notifies followers, passed users, and a user entering the top 10 on approval', async () => {
    const moderator = await harness.createUser({
      role: 'moderator',
      prefix: 'pm4',
    });
    const author = await harness.createUser({ prefix: 'pm5' });
    const blockers = [];
    for (let index = 0; index < 10; index += 1) {
      blockers.push(await harness.createUser({ prefix: `p${index}` }));
    }
    await harness.database.query(
      'UPDATE profiles SET xp = 100, level = 2 WHERE id = ANY($1::uuid[])',
      [blockers.map((user) => user.id)],
    );
    await harness
      .post(`/social/users/${author.id}/follow`, blockers[0])
      .send()
      .expect(201);

    const quest = await harness.createQuest({ xpReward: 10_000 });
    const submission = await harness.createSubmission(author, {
      questId: quest.id,
    });
    await harness
      .post(`/submissions/${submission.id}/approve`, moderator)
      .send({})
      .expect(204);

    // All three of these are produced by the outbox worker, not by the
    // approve request, so the read has to wait for the queue rather than
    // assume it has already drained. Same assertions; they just no longer
    // depend on winning a race that a busy queue loses.
    const followerTypes = (
      await harness.awaitNotificationTypes(blockers[0].id, [
        'follow_quest_completed',
        'leaderboard_overtaken',
      ])
    ).map((row) => row.type);
    expect(followerTypes).toContain('follow_quest_completed');
    expect(followerTypes).toContain('leaderboard_overtaken');
    expect(
      (await harness.awaitNotificationTypes(author.id, ['top_10_entry'])).map(
        (row) => row.type,
      ),
    ).toContain('top_10_entry');
  });

  it('links verified providers by email, but requires authenticated confirmation for an unverified account', async () => {
    const verified = await harness.createUser({ prefix: 'pm6' });
    const linked = await auth.findOrCreateOAuthAccount(
      {
        provider: 'google',
        subject: `google-${verified.id}`,
        email: verified.email,
      },
      true,
    );
    expect(linked.id).toBe(verified.id);

    const unverified = await harness.createUser({ prefix: 'pm7' });
    await harness.database.query(
      'UPDATE users SET email_verified_at = NULL WHERE id = $1',
      [unverified.id],
    );
    const identity = {
      provider: 'apple' as const,
      subject: `apple-${unverified.id}`,
      email: unverified.email,
    };
    await expect(
      auth.findOrCreateOAuthAccount(identity, true),
    ).rejects.toMatchObject({
      response: expect.objectContaining({
        code: 'ACCOUNT_LINK_CONFIRMATION_REQUIRED',
      }),
    });
    await expect(
      auth.linkOAuthIdentity(unverified.id, identity, true),
    ).resolves.toBeUndefined();
    expect(
      await harness.countRows(
        `SELECT count(*) FROM auth_identities
         WHERE user_id = $1 AND provider = 'apple' AND provider_subject = $2`,
        [unverified.id, identity.subject],
      ),
    ).toBe(1);
  });
});
