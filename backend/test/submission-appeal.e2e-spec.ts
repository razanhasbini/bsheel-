import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestSubmission, type TestUser } from './support/e2e-harness.js';

// An appeal puts a rejected submission back in front of a moderator, so it is
// the one user-triggered way to re-enter the review queue. It has to be
// one-shot: a user who can appeal repeatedly can keep a moderator busy on the
// same post forever, and a post that was taken down must not be able to come
// back through the appeal door at all.
describe('submission appeals (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let moderator: TestUser;
  let owner: TestUser;

  const appealNote = 'The proof is there, please look again';

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    moderator = await harness.createUser({ role: 'moderator', prefix: 'ap0' });
    owner = await harness.createUser({ prefix: 'ap1' });
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  /// Leaves the owner with a freshly rejected submission and no active quest.
  const rejectedSubmission = async (user: TestUser): Promise<TestSubmission> => {
    const submission = await harness.createSubmission(user);
    await harness
      .post(`/submissions/${submission.id}/reject`, moderator)
      .send({ reviewNote: 'Needs better proof' })
      .expect(204);
    return submission;
  };

  describe('the happy path', () => {
    let submission: TestSubmission;

    beforeAll(async () => {
      submission = await rejectedSubmission(owner);
    }, 300_000);

    it('accepts one appeal and puts the submission back into the queue', async () => {
      await harness.post(`/submissions/${submission.id}/appeal`, owner).send({ appealNote }).expect(204);

      const row = await harness.submission(submission.id);
      expect(row.status).toBe('pending');
      expect(row.appealed).toBe(true);
      expect(row.appeal_note).toBe(appealNote);
      expect(await harness.userQuestStatus(submission.user_quest_id)).toBe('submitted');

      // The prior verdict is cleared so the queue does not show a stale
      // reviewer against a pending item.
      const cleared = await harness.database.query<{ reviewed_by: string | null; review_note: string | null; reviewed_at: Date | null }>(
        'SELECT reviewed_by, review_note, reviewed_at FROM submissions WHERE id = $1',
        [submission.id],
      );
      expect(cleared.rows[0]).toEqual({ reviewed_by: null, review_note: null, reviewed_at: null });

      expect(await harness.outboxEvents(submission.id, 'submission.appealed')).toHaveLength(1);
      const moderatorNotifications = await harness.notificationsFor(moderator.id, submission.id);
      expect(moderatorNotifications.map((row) => row.type)).toContain('appeal_submitted');
    });

    // FINDING (divergence from the stated invariant): a second appeal *is*
    // refused, but not with ALREADY_APPEALED. The first appeal moves the
    // submission back to `pending`, and appeal() checks the status before it
    // checks the `appealed` flag, so an immediate retry reports
    // SUBMISSION_NOT_REJECTED. ALREADY_APPEALED only becomes reachable once
    // the appealed submission has been rejected a second time (next test).
    // A client that keys its "you already appealed" copy off
    // ALREADY_APPEALED therefore misses the common case.
    it('refuses a second attempt while the appeal is still in the queue', async () => {
      const response = await harness
        .post(`/submissions/${submission.id}/appeal`, owner)
        .send({ appealNote: 'Trying again' })
        .expect(409);
      expect(response.body.error.code).toBe('SUBMISSION_NOT_REJECTED');

      const row = await harness.submission(submission.id);
      expect(row.appealed).toBe(true);
      expect(row.appeal_note).toBe(appealNote);
      expect(await harness.outboxEvents(submission.id, 'submission.appealed')).toHaveLength(1);
    });

    it('reports ALREADY_APPEALED once the appeal has itself been rejected', async () => {
      await harness
        .post(`/submissions/${submission.id}/reject`, moderator)
        .send({ reviewNote: 'Still not convincing' })
        .expect(204);

      const response = await harness
        .post(`/submissions/${submission.id}/appeal`, owner)
        .send({ appealNote: 'Third time lucky' })
        .expect(409);
      expect(response.body.error.code).toBe('ALREADY_APPEALED');
    });
  });

  describe('guards', () => {
    it('returns SUBMISSION_NOT_REJECTED for a pending submission', async () => {
      const user = await harness.createUser({ prefix: 'ap2' });
      const submission = await harness.createSubmission(user);

      const response = await harness
        .post(`/submissions/${submission.id}/appeal`, user)
        .send({ appealNote })
        .expect(409);
      expect(response.body.error.code).toBe('SUBMISSION_NOT_REJECTED');
      expect((await harness.submission(submission.id)).appealed).toBe(false);
    });

    it('returns SUBMISSION_NOT_REJECTED for an approved submission', async () => {
      const user = await harness.createUser({ prefix: 'ap3' });
      const submission = await harness.createApprovedPost(user, moderator);

      const response = await harness
        .post(`/submissions/${submission.id}/appeal`, user)
        .send({ appealNote })
        .expect(409);
      expect(response.body.error.code).toBe('SUBMISSION_NOT_REJECTED');
    });

    it('returns NOT_SUBMISSION_OWNER for someone else submission', async () => {
      const author = await harness.createUser({ prefix: 'ap4' });
      const stranger = await harness.createUser({ prefix: 'ap5' });
      const submission = await rejectedSubmission(author);

      const response = await harness
        .post(`/submissions/${submission.id}/appeal`, stranger)
        .send({ appealNote })
        .expect(403);
      expect(response.body.error.code).toBe('NOT_SUBMISSION_OWNER');
      expect((await harness.submission(submission.id)).appealed).toBe(false);
    });

    it('returns NOT_SUBMISSION_OWNER even for a moderator', async () => {
      const author = await harness.createUser({ prefix: 'ap6' });
      const submission = await rejectedSubmission(author);

      // Ownership is checked before anything else, so moderation privileges
      // do not let an admin appeal on a user behalf.
      const response = await harness
        .post(`/submissions/${submission.id}/appeal`, moderator)
        .send({ appealNote })
        .expect(403);
      expect(response.body.error.code).toBe('NOT_SUBMISSION_OWNER');
    });

    it('returns DELETED_SUBMISSION once the post has been taken down', async () => {
      const author = await harness.createUser({ prefix: 'ap7' });
      const submission = await rejectedSubmission(author);
      await harness
        .post(`/admin/submissions/${submission.id}/remove`, moderator)
        .send({ reason: 'e2e takedown before appeal' })
        .expect(204);
      expect((await harness.submission(submission.id)).visibility).toBe('deleted');

      const response = await harness
        .post(`/submissions/${submission.id}/appeal`, author)
        .send({ appealNote })
        .expect(409);
      expect(response.body.error.code).toBe('DELETED_SUBMISSION');

      const row = await harness.submission(submission.id);
      expect(row.status).toBe('rejected');
      expect(row.appealed).toBe(false);
      expect(await harness.outboxEvents(submission.id, 'submission.appealed')).toHaveLength(0);
    });

    it('returns SUBMISSION_NOT_FOUND for an unknown id', async () => {
      const response = await harness
        .post('/submissions/00000000-0000-4000-8000-000000000000/appeal', owner)
        .send({ appealNote })
        .expect(404);
      expect(response.body.error.code).toBe('SUBMISSION_NOT_FOUND');
    });

    it('requires a token and a note', async () => {
      const author = await harness.createUser({ prefix: 'ap8' });
      const submission = await rejectedSubmission(author);

      await harness.post(`/submissions/${submission.id}/appeal`).send({ appealNote }).expect(401);
      await harness.post(`/submissions/${submission.id}/appeal`, author).send({}).expect(400);
      await harness.post(`/submissions/${submission.id}/appeal`, author).send({ appealNote: 'no' }).expect(400);
      expect((await harness.submission(submission.id)).appealed).toBe(false);
    });
  });
});
