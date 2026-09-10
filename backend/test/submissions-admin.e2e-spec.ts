import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestSubmission, type TestUser } from './support/e2e-harness.js';

// The three admin read surfaces replaced client-side filtering: the moderation
// screens used to pull every submission and derive status, duplicate hints and
// retake badges in Dart. Those derivations now live in SQL, so the filters and
// the computed columns are the contract the admin app depends on.
describe('admin submission surfaces (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let moderator: TestUser;

  interface AdminRow {
    id: string;
    status: string;
    visibility: string;
    appealed: boolean;
    submitted_at: string;
    username: string;
    quest_title: string;
  }

  const adminList = async (query: string): Promise<AdminRow[]> => {
    const response = await harness.get(`/submissions/admin${query}`, moderator).expect(200);
    return response.body.data;
  };

  /// The queue is global and paginated, so a fixture row is looked up across
  /// pages rather than assumed to be on the first one.
  const findInReviewQueue = async (submissionId: string): Promise<Record<string, unknown> | undefined> => {
    for (let offset = 0; offset < 300; offset += 100) {
      const response = await harness
        .get(`/submissions/admin/review-queue?limit=100&offset=${offset}`, moderator)
        .expect(200);
      const match = response.body.data.find((row: { id: string }) => row.id === submissionId);
      if (match) return match;
      if (response.body.data.length < 100) return undefined;
    }
    return undefined;
  };

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    moderator = await harness.createUser({ role: 'moderator', prefix: 'x0' });
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  describe('GET /submissions/admin filters', () => {
    let pending: TestSubmission;
    let approved: TestSubmission;
    let rejected: TestSubmission;
    let appealed: TestSubmission;
    let hidden: TestSubmission;
    let removed: TestSubmission;
    let mine: string[];

    beforeAll(async () => {
      // A user may only hold one quest at a time, so each state needs its own
      // author to be able to leave a submission parked in that state.
      const authors = await Promise.all(
        ['x1', 'x2', 'x3', 'x4', 'x5', 'x6'].map((prefix) => harness.createUser({ prefix })),
      );

      pending = await harness.createSubmission(authors[0]);

      approved = await harness.createApprovedPost(authors[1], moderator);

      rejected = await harness.createSubmission(authors[2]);
      await harness.post(`/submissions/${rejected.id}/reject`, moderator).send({ reviewNote: 'no' }).expect(204);

      appealed = await harness.createSubmission(authors[3]);
      await harness.post(`/submissions/${appealed.id}/reject`, moderator).send({ reviewNote: 'no' }).expect(204);
      await harness
        .post(`/submissions/${appealed.id}/appeal`, authors[3])
        .send({ appealNote: 'please look again' })
        .expect(204);

      hidden = await harness.createApprovedPost(authors[4], moderator);
      await harness
        .patch(`/submissions/${hidden.id}/visibility`, authors[4])
        .send({ visibility: 'hidden_from_feed' })
        .expect(204);

      removed = await harness.createApprovedPost(authors[5], moderator);
      await harness
        .post(`/admin/submissions/${removed.id}/remove`, moderator)
        .send({ reason: 'e2e removed content view' })
        .expect(204);

      mine = [pending.id, approved.id, rejected.id, appealed.id, hidden.id, removed.id];
    }, 300_000);

    it('defaults to the pending queue', async () => {
      const rows = await adminList('?limit=100');
      expect(rows.every((row) => row.status === 'pending')).toBe(true);
      const ids = rows.map((row) => row.id);
      expect(ids).toContain(pending.id);
      expect(ids).toContain(appealed.id);
      expect(ids).not.toContain(approved.id);
      expect(ids).not.toContain(rejected.id);
    });

    it('filters status=approved, including posts that were later hidden or removed', async () => {
      const rows = await adminList('?status=approved&limit=100&order=desc');
      expect(rows.every((row) => row.status === 'approved')).toBe(true);
      const ids = rows.map((row) => row.id);
      expect(ids).toContain(approved.id);
      // Visibility and review status are independent: taking a post down does
      // not move it out of the approved history.
      expect(ids).toContain(hidden.id);
      expect(ids).toContain(removed.id);
      expect(ids).not.toContain(pending.id);
    });

    it('filters status=rejected', async () => {
      const rows = await adminList('?status=rejected&limit=100&order=desc');
      expect(rows.every((row) => row.status === 'rejected')).toBe(true);
      const ids = rows.map((row) => row.id);
      expect(ids).toContain(rejected.id);
      expect(ids).not.toContain(appealed.id);
    });

    it('returns every status for status=all', async () => {
      const rows = await adminList('?status=all&limit=100&order=desc');
      const ids = rows.map((row) => row.id);
      for (const id of mine) expect(ids).toContain(id);
    });

    it('filters appealed=true and appealed=false', async () => {
      const appealedRows = await adminList('?status=all&appealed=true&limit=100&order=desc');
      expect(appealedRows.every((row) => row.appealed === true)).toBe(true);
      expect(appealedRows.map((row) => row.id)).toContain(appealed.id);

      const plainRows = await adminList('?status=all&appealed=false&limit=100&order=desc');
      expect(plainRows.every((row) => row.appealed === false)).toBe(true);
      expect(plainRows.map((row) => row.id)).not.toContain(appealed.id);
      expect(plainRows.map((row) => row.id)).toContain(pending.id);
    });

    it('filters each concrete visibility value', async () => {
      const visible = await adminList('?status=all&visibility=visible&limit=100&order=desc');
      expect(visible.every((row) => row.visibility === 'visible')).toBe(true);
      expect(visible.map((row) => row.id)).toContain(approved.id);
      expect(visible.map((row) => row.id)).not.toContain(hidden.id);

      const hiddenRows = await adminList('?status=all&visibility=hidden_from_feed&limit=100&order=desc');
      expect(hiddenRows.every((row) => row.visibility === 'hidden_from_feed')).toBe(true);
      expect(hiddenRows.map((row) => row.id)).toContain(hidden.id);

      const deletedRows = await adminList('?status=all&visibility=deleted&limit=100&order=desc');
      expect(deletedRows.every((row) => row.visibility === 'deleted')).toBe(true);
      expect(deletedRows.map((row) => row.id)).toContain(removed.id);
    });

    it('treats visibility=not_visible as the removed-content view', async () => {
      const rows = await adminList('?status=all&visibility=not_visible&limit=100&order=desc');
      expect(rows.every((row) => row.visibility !== 'visible')).toBe(true);
      const ids = rows.map((row) => row.id);
      expect(ids).toContain(hidden.id);
      expect(ids).toContain(removed.id);
      expect(ids).not.toContain(approved.id);
    });

    it('orders by submitted_at in the requested direction', async () => {
      const ascending = await adminList('?status=all&order=asc&limit=100');
      const descending = await adminList('?status=all&order=desc&limit=100');

      const ascTimes = ascending.map((row) => Date.parse(row.submitted_at));
      expect([...ascTimes].sort((a, b) => a - b)).toEqual(ascTimes);
      const descTimes = descending.map((row) => Date.parse(row.submitted_at));
      expect([...descTimes].sort((a, b) => b - a)).toEqual(descTimes);
    });

    it('paginates with limit and offset', async () => {
      // Ascending order keeps the head of the list stable while other suites
      // append newer rows.
      const head = await adminList('?status=all&order=asc&limit=2');
      expect(head).toHaveLength(2);

      const first = await adminList('?status=all&order=asc&limit=1&offset=0');
      const second = await adminList('?status=all&order=asc&limit=1&offset=1');
      expect(first[0].id).toBe(head[0].id);
      expect(second[0].id).toBe(head[1].id);
      expect(first[0].id).not.toBe(second[0].id);
    });

    it('joins the author profile and the quest onto every row', async () => {
      const rows = await adminList('?status=all&limit=100&order=desc');
      const row = rows.find((candidate) => candidate.id === approved.id);
      expect(row?.username).toBeTruthy();
      expect(row?.quest_title).toBeTruthy();
    });

    it('rejects out-of-range and unknown query values', async () => {
      await harness.get('/submissions/admin?limit=0', moderator).expect(400);
      await harness.get('/submissions/admin?limit=101', moderator).expect(400);
      await harness.get('/submissions/admin?status=bogus', moderator).expect(400);
      await harness.get('/submissions/admin?visibility=bogus', moderator).expect(400);
      await harness.get('/submissions/admin?order=sideways', moderator).expect(400);
      await harness.get('/submissions/admin?appealed=maybe', moderator).expect(400);
    });

    it('requires an admin token', async () => {
      await harness.get('/submissions/admin').expect(401);
      const plain = await harness.createUser({ prefix: 'x7' });
      const response = await harness.get('/submissions/admin', plain).expect(403);
      expect(response.body.error.code).toBe('INSUFFICIENT_PERMISSION');
    });

    it('serves the dedicated pending route as pending only', async () => {
      const response = await harness.get('/submissions/admin/pending?limit=100', moderator).expect(200);
      expect(response.body.data.every((row: AdminRow) => row.status === 'pending')).toBe(true);
      await harness.get('/submissions/admin/pending').expect(401);
    });
  });

  describe('GET /submissions/admin/review-queue', () => {
    it('flags a duplicate when the user already had the same media rejected', async () => {
      const user = await harness.createUser({ prefix: 'x8' });
      const mediaUrl = await harness.createMediaObject(user);

      const firstTry = await harness.createSubmission(user, { mediaUrl, caption: 'first attempt' });
      await harness.post(`/submissions/${firstTry.id}/reject`, moderator).send({ reviewNote: 'no' }).expect(204);

      // The same verified object re-used on a new quest is the exact shape the
      // DUPLICATE badge exists to catch.
      const retry = await harness.createSubmission(user, { mediaUrl, caption: 'a different caption entirely' });

      const row = await findInReviewQueue(retry.id);
      expect(row).toBeDefined();
      expect(row?.is_duplicate).toBe(true);
      expect(row?.user_rejected_count).toBe(1);
      expect(row?.user_approved_count).toBe(0);
    }, 300_000);

    it('flags a duplicate on an identical caption of at least eight characters and reports both counts', async () => {
      const user = await harness.createUser({ prefix: 'x9' });
      const caption = 'identical caption text';

      const good = await harness.createSubmission(user, { caption: 'an approved one' });
      await harness.post(`/submissions/${good.id}/approve`, moderator).send({}).expect(204);

      const bad = await harness.createSubmission(user, { caption });
      await harness.post(`/submissions/${bad.id}/reject`, moderator).send({ reviewNote: 'no' }).expect(204);

      const retry = await harness.createSubmission(user, { caption });

      const row = await findInReviewQueue(retry.id);
      expect(row).toBeDefined();
      expect(row?.is_duplicate).toBe(true);
      expect(row?.user_approved_count).toBe(1);
      expect(row?.user_rejected_count).toBe(1);
      expect(row?.username).toBe(user.username);
      expect(row?.quest_title).toBeTruthy();
    }, 300_000);

    it('does not flag a duplicate when neither the media nor a long caption matches', async () => {
      const user = await harness.createUser({ prefix: 'xa' });

      // Four characters, so it stays under the eight-character caption rule.
      const first = await harness.createSubmission(user, { caption: 'tiny' });
      await harness.post(`/submissions/${first.id}/reject`, moderator).send({ reviewNote: 'no' }).expect(204);

      const second = await harness.createSubmission(user, { caption: 'a completely unrelated caption' });

      const row = await findInReviewQueue(second.id);
      expect(row).toBeDefined();
      expect(row?.is_duplicate).toBe(false);
      expect(row?.user_rejected_count).toBe(1);
    }, 300_000);

    it('lists only pending submissions, oldest first', async () => {
      const response = await harness.get('/submissions/admin/review-queue?limit=100', moderator).expect(200);
      expect(response.body.data.every((row: AdminRow) => row.status === 'pending')).toBe(true);
      const times = response.body.data.map((row: AdminRow) => Date.parse(row.submitted_at));
      expect([...times].sort((a: number, b: number) => a - b)).toEqual(times);
    });

    it('requires an admin token', async () => {
      await harness.get('/submissions/admin/review-queue').expect(401);
      const plain = await harness.createUser({ prefix: 'xb' });
      await harness.get('/submissions/admin/review-queue', plain).expect(403);
    });
  });

  describe('GET /submissions/admin/:id', () => {
    it('returns the profile, the quest and is_retake=false for a first attempt', async () => {
      const user = await harness.createUser({ prefix: 'xc' });
      const quest = await harness.createQuest({ xpReward: 120, durationHours: 6 });
      const submission = await harness.createSubmission(user, { questId: quest.id, caption: 'detail fixture' });

      const response = await harness.get(`/submissions/admin/${submission.id}`, moderator).expect(200);
      const detail = response.body.data;

      expect(detail.id).toBe(submission.id);
      expect(detail.username).toBe(user.username);
      expect(detail.display_name).toBe(user.displayName);
      expect(detail.xp).toBe(0);
      expect(detail.level).toBe(1);
      expect(detail.quest_id).toBe(quest.id);
      expect(detail.quest_title).toBe(quest.title);
      expect(detail.quest_xp_reward).toBe(120);
      expect(detail.quest_duration_hours).toBe(6);
      expect(detail.quest_category).toBe('learning');
      expect(detail.quest_difficulty).toBe('easy');
      expect(detail.user_quest_status).toBe('submitted');
      expect(detail.assigned_at).toBeTruthy();
      expect(detail.expires_at).toBeTruthy();
      expect(detail.is_retake).toBe(false);
      expect(detail.collab_group_id).toBeNull();
      expect(detail.collab_mode).toBeNull();
    }, 300_000);

    it('reports is_retake when the user already had the same quest approved', async () => {
      const user = await harness.createUser({ prefix: 'xd' });
      const quest = await harness.createQuest();

      const firstAttempt = await harness.createSubmission(user, { questId: quest.id });
      await harness.post(`/submissions/${firstAttempt.id}/approve`, moderator).send({}).expect(204);

      const retake = await harness.createSubmission(user, { questId: quest.id });

      expect((await harness.get(`/submissions/admin/${retake.id}`, moderator).expect(200)).body.data.is_retake).toBe(true);
      // The earlier attempt is not itself a retake: the flag looks for a
      // *different* previously approved run of the same quest.
      expect(
        (await harness.get(`/submissions/admin/${firstAttempt.id}`, moderator).expect(200)).body.data.is_retake,
      ).toBe(false);
    }, 300_000);

    it('surfaces the collaboration group id and mode when the quest was a collab', async () => {
      const user = await harness.createUser({ prefix: 'xe' });
      const quest = await harness.createQuest();
      const submission = await harness.createSubmission(user, { questId: quest.id });

      // The collab module owns group creation; the group is inserted directly
      // so this assertion stays about what the detail route joins.
      const group = await harness.database.query<{ id: string }>(
        `INSERT INTO collab_groups (quest_id, creator_id, code, mode, expires_at)
         VALUES ($1, $2, $3, 'versus', now() + interval '4 hours') RETURNING id`,
        [quest.id, user.id, randomUUID().slice(0, 8)],
      );
      await harness.database.query(
        'INSERT INTO collab_group_members (group_id, user_id, user_quest_id) VALUES ($1, $2, $3)',
        [group.rows[0].id, user.id, submission.user_quest_id],
      );

      const detail = (await harness.get(`/submissions/admin/${submission.id}`, moderator).expect(200)).body.data;
      expect(detail.collab_group_id).toBe(group.rows[0].id);
      expect(detail.collab_mode).toBe('versus');
      expect(detail.collab_status).toBe('open');
    }, 300_000);

    it('returns SUBMISSION_NOT_FOUND for an unknown id', async () => {
      const response = await harness
        .get('/submissions/admin/00000000-0000-4000-8000-000000000000', moderator)
        .expect(404);
      expect(response.body.error.code).toBe('SUBMISSION_NOT_FOUND');
    });

    it('rejects a non-uuid id', async () => {
      await harness.get('/submissions/admin/not-a-uuid', moderator).expect(400);
    });

    it('requires an admin token', async () => {
      await harness.get('/submissions/admin/00000000-0000-4000-8000-000000000000').expect(401);
      const plain = await harness.createUser({ prefix: 'xf' });
      await harness.get('/submissions/admin/00000000-0000-4000-8000-000000000000', plain).expect(403);
    });
  });
});
