import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

// The admin dashboard reads these three routes directly. The notification
// feed has to exclude admin-authored announcements (they have their own
// page), the XP audit is the only way to spot a profile whose stored total has
// drifted from its approved history, and the profile editor is a privileged
// write that must be audited and must not be able to steal a username.
describe('admin dashboard surfaces (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let superAdmin: TestUser;
  let moderator: TestUser;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    superAdmin = await harness.createUser({ role: 'super_admin', prefix: 'd0' });
    moderator = await harness.createUser({ role: 'moderator', prefix: 'd1' });
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  describe('GET /admin/notifications', () => {
    let recipient: TestUser;
    let systemTitle: string;
    let announcementTitle: string;

    beforeAll(async () => {
      recipient = await harness.createUser({ prefix: 'd2' });
      systemTitle = `e2e system notice ${recipient.username}`;
      announcementTitle = `e2e announcement ${recipient.username}`;

      await harness
        .post('/admin/notifications', moderator)
        .send({
          targetUserId: recipient.id,
          title: systemTitle,
          body: 'A non-announcement notification the dashboard should list',
          type: 'e2e_system_event',
        })
        .expect(201);

      // No explicit type means 'announcement', which is exactly the kind the
      // dashboard feed filters out.
      await harness
        .post('/admin/notifications', moderator)
        .send({
          targetUserId: recipient.id,
          title: announcementTitle,
          body: 'An announcement the dashboard should not list',
        })
        .expect(201);
    }, 300_000);

    it('lists automatic notifications and excludes announcements', async () => {
      const response = await harness.get('/admin/notifications?limit=200', moderator).expect(200);
      const titles = response.body.data.map((row: { title: string }) => row.title);

      expect(titles).toContain(systemTitle);
      expect(titles).not.toContain(announcementTitle);
      expect(response.body.data.every((row: { type: string }) => row.type !== 'announcement')).toBe(true);
    });

    it('returns the newest first', async () => {
      const response = await harness.get('/admin/notifications?limit=200', moderator).expect(200);
      const times = response.body.data.map((row: { created_at: string }) => Date.parse(row.created_at));
      expect([...times].sort((a: number, b: number) => b - a)).toEqual(times);
    });

    it('joins the recipient username onto each row', async () => {
      const response = await harness.get('/admin/notifications?limit=200', moderator).expect(200);
      const row = response.body.data.find((candidate: { title: string }) => candidate.title === systemTitle);
      expect(row.user_id).toBe(recipient.id);
      expect(row.username).toBe(recipient.username);
      expect(row.body).toBeTruthy();
    });

    // FINDING: this route is the only admin list ordered by a single column
    // (created_at DESC) with no id tiebreaker, and one submission inserts a
    // notification per admin inside a single transaction, so tied rows share
    // an identical created_at and their relative order is not stable between
    // requests. Row-identity paging cannot be asserted against it; adding
    // `, n.id DESC` in admin.repository.notifications would make it exact.
    it('caps the page size and validates the range', async () => {
      const head = await harness.get('/admin/notifications?limit=2', moderator).expect(200);
      expect(head.body.data.length).toBeLessThanOrEqual(2);

      // An offset past the end of the table is the one offset assertion that
      // cannot race with rows other suites are appending at the head.
      const past = await harness.get('/admin/notifications?limit=1&offset=1000000', moderator).expect(200);
      expect(past.body.data).toEqual([]);

      await harness.get('/admin/notifications?limit=201', moderator).expect(400);
      await harness.get('/admin/notifications?limit=0', moderator).expect(400);
      await harness.get('/admin/notifications?offset=-1', moderator).expect(400);
    });

    it('requires an admin token', async () => {
      await harness.get('/admin/notifications').expect(401);
      const plain = await harness.createUser({ prefix: 'd3' });
      const response = await harness.get('/admin/notifications', plain).expect(403);
      expect(response.body.error.code).toBe('INSUFFICIENT_PERMISSION');
    });
  });

  describe('GET /admin/xp-audit', () => {
    let drifted: TestUser;
    let untouched: TestUser;

    const questXp = 250;
    const storedXp = 987_654;

    beforeAll(async () => {
      drifted = await harness.createUser({ prefix: 'd4' });
      untouched = await harness.createUser({ prefix: 'd5' });

      const submission = await harness.createApprovedPost(drifted, superAdmin, {
        questId: (await harness.createQuest({ xpReward: questXp })).id,
      });
      expect(submission.id).toBeTruthy();

      // Deliberately desynchronise the stored totals from the approved
      // history. The high value also keeps the row near the top of the
      // xp-DESC ordering the route uses.
      await harness
        .patch(`/admin/users/${drifted.id}/xp`, superAdmin)
        .send({ xp: storedXp, level: 50, questsCompleted: 9, reason: 'e2e xp audit drift' })
        .expect(204);
      await harness
        .patch(`/admin/users/${untouched.id}/xp`, superAdmin)
        .send({ xp: storedXp - 1, level: 40, questsCompleted: 3, reason: 'e2e xp audit no history' })
        .expect(204);
    }, 300_000);

    const auditRow = async (userId: string) => {
      const response = await harness.get('/admin/xp-audit?limit=200', superAdmin).expect(200);
      return response.body.data.find((row: { user_id: string }) => row.user_id === userId);
    };

    it('reports the stored totals next to what the approved history implies', async () => {
      const row = await auditRow(drifted.id);
      expect(row).toBeDefined();
      expect(row.username).toBe(drifted.username);
      expect(row.current_xp).toBe(storedXp);
      // The stored level is derived from xp, not taken from the request. It
      // used to be an independent field, and a mismatched pair made
      // xp_to_next_level negative — so asking for level 50 alongside this xp
      // now stores the derived level instead.
      expect(row.current_level).toBe(Math.floor(storedXp / 100) + 1);
      expect(row.current_quests).toBe(9);
      expect(row.expected_xp).toBe(questXp);
      expect(row.expected_quests).toBe(1);
    });

    it('derives expected_level as expected_xp / 100 + 1', async () => {
      const row = await auditRow(drifted.id);
      expect(row.expected_level).toBe(Math.floor(questXp / 100) + 1);
    });

    it('reports zero expectations for a user with no approved quests', async () => {
      const row = await auditRow(untouched.id);
      expect(row).toBeDefined();
      expect(row.expected_xp).toBe(0);
      expect(row.expected_quests).toBe(0);
      // With no history the floor of the formula is level 1, not level 0.
      expect(row.expected_level).toBe(1);
    });

    it('orders by stored XP descending', async () => {
      const response = await harness.get('/admin/xp-audit?limit=200', superAdmin).expect(200);
      const stored = response.body.data.map((row: { current_xp: number }) => row.current_xp);
      expect([...stored].sort((a: number, b: number) => b - a)).toEqual(stored);
    });

    it('is restricted to super_admin', async () => {
      await harness.get('/admin/xp-audit').expect(401);
      const response = await harness.get('/admin/xp-audit', moderator).expect(403);
      expect(response.body.error.code).toBe('INSUFFICIENT_PERMISSION');
      const plain = await harness.createUser({ prefix: 'd6' });
      await harness.get('/admin/xp-audit', plain).expect(403);
    });
  });

  describe('PATCH /admin/users/:id/profile', () => {
    let subject: TestUser;
    let neighbour: TestUser;

    beforeAll(async () => {
      subject = await harness.createUser({ prefix: 'd7' });
      neighbour = await harness.createUser({ prefix: 'd8' });
    }, 300_000);

    it('applies identity and progression fields in one audited write', async () => {
      const renamed = `${subject.username}r`.slice(0, 30);
      await harness
        .patch(`/admin/users/${subject.id}/profile`, superAdmin)
        .send({
          username: renamed,
          displayName: 'Renamed By Admin',
          bio: 'Edited by the e2e suite',
          xp: 420,
          level: 5,
          questsCompleted: 4,
          reason: 'e2e profile edit',
        })
        .expect(204);

      const stored = await harness.database.query<{
        username: string;
        display_name: string;
        bio: string | null;
        xp: number;
        level: number;
        quests_completed: number;
      }>(
        'SELECT username::text, display_name, bio, xp, level, quests_completed FROM profiles WHERE id = $1',
        [subject.id],
      );
      expect(stored.rows[0]).toEqual({
        username: renamed,
        display_name: 'Renamed By Admin',
        bio: 'Edited by the e2e suite',
        xp: 420,
        level: 5,
        quests_completed: 4,
      });

      const audit = await harness.auditRows('user.update_profile', subject.id);
      expect(audit).toHaveLength(1);
      expect(audit[0].actor_id).toBe(superAdmin.id);
      expect(audit[0].before_state).toMatchObject({ username: subject.username, xp: 0 });
      expect(audit[0].after_state).toMatchObject({
        username: renamed,
        xp: 420,
        reason: 'e2e profile edit',
      });
    });

    it('normalises the username to lower case', async () => {
      const mixed = `Mixed${neighbour.username}`.slice(0, 30);
      await harness
        .patch(`/admin/users/${neighbour.id}/profile`, superAdmin)
        .send({ username: mixed, reason: 'e2e case normalisation' })
        .expect(204);

      expect((await harness.profile(neighbour.id)).username).toBe(mixed.toLowerCase());
    });

    it('returns USERNAME_TAKEN when the new handle already belongs to someone', async () => {
      const target = await harness.profile(neighbour.id);
      const response = await harness
        .patch(`/admin/users/${subject.id}/profile`, superAdmin)
        .send({ username: target.username, reason: 'e2e collision' })
        .expect(409);
      expect(response.body.error.code).toBe('USERNAME_TAKEN');

      // The failed write must not have applied anything else either.
      const audit = await harness.auditRows('user.update_profile', subject.id);
      expect(audit).toHaveLength(1);
    });

    it('rejects an empty change set with NO_PROFILE_CHANGES', async () => {
      const response = await harness
        .patch(`/admin/users/${subject.id}/profile`, superAdmin)
        .send({ reason: 'e2e nothing to change' })
        .expect(409);
      expect(response.body.error.code).toBe('NO_PROFILE_CHANGES');
    });

    it('clears the bio when an empty string is supplied', async () => {
      await harness
        .patch(`/admin/users/${subject.id}/profile`, superAdmin)
        .send({ bio: '   ', reason: 'e2e clear bio' })
        .expect(204);
      const stored = await harness.database.query<{ bio: string | null }>(
        'SELECT bio FROM profiles WHERE id = $1',
        [subject.id],
      );
      expect(stored.rows[0].bio).toBeNull();
    });

    it('returns PROFILE_NOT_FOUND for an unknown user', async () => {
      const response = await harness
        .patch('/admin/users/00000000-0000-4000-8000-000000000000/profile', superAdmin)
        .send({ displayName: 'Nobody', reason: 'e2e missing profile' })
        .expect(404);
      expect(response.body.error.code).toBe('PROFILE_NOT_FOUND');
    });

    it('validates the payload before touching the database', async () => {
      await harness
        .patch(`/admin/users/${subject.id}/profile`, superAdmin)
        .send({ displayName: 'No Reason Given' })
        .expect(400);
      await harness
        .patch(`/admin/users/${subject.id}/profile`, superAdmin)
        .send({ username: 'has spaces', reason: 'e2e invalid username' })
        .expect(400);
      await harness
        .patch(`/admin/users/${subject.id}/profile`, superAdmin)
        .send({ xp: -1, reason: 'e2e negative xp' })
        .expect(400);
      await harness
        .patch(`/admin/users/${subject.id}/profile`, superAdmin)
        .send({ displayName: 'Extra Field', reason: 'e2e unknown field', role: 'super_admin' })
        .expect(400);
    });

    it('is restricted to super_admin', async () => {
      await harness
        .patch(`/admin/users/${subject.id}/profile`)
        .send({ displayName: 'Anonymous', reason: 'e2e no token' })
        .expect(401);
      const response = await harness
        .patch(`/admin/users/${subject.id}/profile`, moderator)
        .send({ displayName: 'Moderator Edit', reason: 'e2e wrong role' })
        .expect(403);
      expect(response.body.error.code).toBe('INSUFFICIENT_PERMISSION');

      const plain = await harness.createUser({ prefix: 'd9' });
      await harness
        .patch(`/admin/users/${subject.id}/profile`, plain)
        .send({ displayName: 'Self Promotion', reason: 'e2e plain user' })
        .expect(403);
    });
  });
});
