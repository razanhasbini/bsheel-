import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

interface QueueRow {
  readonly id: string;
  readonly email: string;
  readonly note: string | null;
  readonly created_at: string;
  readonly handled_at: string | null;
  readonly matched_user_id: string | null;
  readonly matched_username: string | null;
  readonly handled_by_email: string | null;
}

/**
 * The operator surface over `public_deletion_requests`.
 *
 * Rows land here from the signed-out compliance page, which cannot erase
 * anything: an unauthenticated endpoint that deleted an account by email
 * address would let anyone erase anyone. They are a work queue — verify the
 * requester, then run the authenticated flow. Until this surface existed the
 * queue was invisible, so GDPR/CCPA erasure requests arrived and sat in a
 * table nobody read: the same failure mode as an audit log nothing can open.
 */
describe('public deletion-request queue (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let user: TestUser;
  let moderator: TestUser;
  let superAdmin: TestUser;

  /// Every row this file creates, so teardown can remove exactly them. The
  /// table has no foreign key back to a fixture user, so nothing about it
  /// cascades.
  const requestIds: string[] = [];
  const emailTag = randomUUID().replaceAll('-', '').slice(0, 10);

  /// Seeds a queue row directly, at a chosen age.
  ///
  /// Inserted rather than posted: `POST /public/deletion-requests` is
  /// throttled to three per five minutes (it is an unauthenticated write keyed
  /// on someone else's address), and the ordering assertion needs four rows
  /// with known ages. One row below does go through the real endpoint, to
  /// prove the two halves meet.
  async function seed(
    label: string,
    options: { ageMinutes: number; handled?: boolean } ,
  ): Promise<string> {
    const result = await harness.database.query<{ id: string }>(
      `INSERT INTO public_deletion_requests (email, note, created_at, handled_at)
       VALUES ($1::citext, $2, now() - ($3 || ' minutes')::interval, $4)
       RETURNING id`,
      [
        `${label}.${emailTag}@example.test`,
        `seeded by the deletion-queue e2e suite (${label})`,
        options.ageMinutes,
        options.handled ? new Date() : null,
      ],
    );
    const id = result.rows[0].id;
    requestIds.push(id);
    // Tracked so the harness also clears the audit rows keyed to this id.
    harness.track(id);
    return id;
  }

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    user = await harness.createUser({ prefix: 'q0' });
    moderator = await harness.createUser({ role: 'moderator', prefix: 'q1' });
    superAdmin = await harness.createUser({ role: 'super_admin', prefix: 'q2' });
  }, 300_000);

  afterAll(async () => {
    if (requestIds.length) {
      await harness?.database.query(
        'DELETE FROM public_deletion_requests WHERE id = ANY($1::uuid[])',
        [requestIds],
      );
    }
    await harness?.database.query(
      'DELETE FROM public_deletion_requests WHERE email::text LIKE $1',
      [`%${emailTag}@example.test`],
    );
    await harness?.close();
  });

  describe('GET /admin/deletion-requests', () => {
    it('is refused to an ordinary user', async () => {
      const response = await harness.get('/admin/deletion-requests', user).expect(403);
      expect(response.body.error.code).toBe('INSUFFICIENT_PERMISSION');
    });

    it('is refused without a session', async () => {
      await harness.get('/admin/deletion-requests').expect(401);
    });

    it('is refused to a moderator', async () => {
      // super_admin, not moderator: every row is the email address of a
      // person asking to be erased. That is personal data belonging to
      // someone who may not even have an account, not moderation material,
      // and the operator who acts on it is the one who can also run the
      // erasure.
      const response = await harness.get('/admin/deletion-requests', moderator).expect(403);
      expect(response.body.error.code).toBe('INSUFFICIENT_PERMISSION');
    });

    it('lists unhandled requests first, oldest of those at the top', async () => {
      const oldest = await seed('oldest', { ageMinutes: 90 });
      const middle = await seed('middle', { ageMinutes: 60 });
      const newest = await seed('newest', { ageMinutes: 30 });
      const alreadyHandled = await seed('handled', { ageMinutes: 120, handled: true });

      const response = await harness
        .get('/admin/deletion-requests?limit=200', superAdmin)
        .expect(200);
      const rows: QueueRow[] = response.body.data;
      const positions = new Map(rows.map((row, index) => [row.id, index]));

      // The queue is a work order: the person who has waited longest is at
      // the top, and anything already dealt with is out of the way.
      expect(positions.get(oldest)!).toBeLessThan(positions.get(middle)!);
      expect(positions.get(middle)!).toBeLessThan(positions.get(newest)!);
      expect(positions.get(newest)!).toBeLessThan(positions.get(alreadyHandled)!);
    });

    it('says whether the address matched an account', async () => {
      // The whole reason the column exists: the operator can see there is
      // something to erase without running a lookup of their own — and can
      // see when there is not, which is the more common case for a typo.
      await harness
        .post('/public/deletion-requests')
        .send({ email: user.email, confirmation: 'DELETE' })
        .expect(202);
      const matchedRow = await harness.database.query<{ id: string }>(
        'SELECT id FROM public_deletion_requests WHERE email = $1::citext',
        [user.email],
      );
      requestIds.push(matchedRow.rows[0].id);
      harness.track(matchedRow.rows[0].id);

      const strangerId = await seed('stranger', { ageMinutes: 10 });

      const rows: QueueRow[] = (
        await harness.get('/admin/deletion-requests?limit=200', superAdmin).expect(200)
      ).body.data;

      const matched = rows.find((row) => row.id === matchedRow.rows[0].id)!;
      expect(matched.matched_user_id).toBe(user.id);
      expect(matched.matched_username).toBe(user.username);

      const stranger = rows.find((row) => row.id === strangerId)!;
      expect(stranger.matched_user_id).toBeNull();
      expect(stranger.matched_username).toBeNull();
    });
  });

  describe('PATCH /admin/deletion-requests/:id', () => {
    it('is refused to a moderator, and leaves the row untouched', async () => {
      const id = await seed('modattempt', { ageMinutes: 20 });

      await harness.patch(`/admin/deletion-requests/${id}`, moderator).send({}).expect(403);

      const row = await harness.database.query<{ handled_at: Date | null }>(
        'SELECT handled_at FROM public_deletion_requests WHERE id = $1',
        [id],
      );
      expect(row.rows[0].handled_at).toBeNull();
    });

    it('records who handled it, when, and an audit row naming them', async () => {
      const id = await seed('handleme', { ageMinutes: 15 });

      await harness.patch(`/admin/deletion-requests/${id}`, superAdmin).send({}).expect(204);

      const row = await harness.database.query<{
        handled_at: Date | null;
        handled_by: string | null;
      }>(
        'SELECT handled_at, handled_by FROM public_deletion_requests WHERE id = $1',
        [id],
      );
      expect(row.rows[0].handled_at).not.toBeNull();
      // "Handled" is a claim that a named human verified the requester's
      // identity. Recording who made it is the whole value of the record.
      expect(row.rows[0].handled_by).toBe(superAdmin.id);

      const audit = await harness.auditRows('deletion_request.handled', id);
      expect(audit).toHaveLength(1);
      expect(audit[0].actor_id).toBe(superAdmin.id);

      // And the queue now shows it as handled, by whom.
      const rows: QueueRow[] = (
        await harness.get('/admin/deletion-requests?limit=200', superAdmin).expect(200)
      ).body.data;
      const listed = rows.find((entry) => entry.id === id)!;
      expect(listed.handled_at).not.toBeNull();
      expect(listed.handled_by_email).toBe(superAdmin.email);
    });

    it('answers 404 for an id that is not in the queue', async () => {
      const response = await harness
        .patch(`/admin/deletion-requests/${randomUUID()}`, superAdmin)
        .send({})
        .expect(404);
      expect(response.body.error.code).toBe('DELETION_REQUEST_NOT_FOUND');
    });

    it('does not erase the matched account', async () => {
      // The table's own comment is explicit that this queue cannot and must
      // not delete an account. Marking a request handled is a note that a
      // human has taken it on; the erasure runs through the authenticated
      // account flow, which needs the account holder's own session.
      const target = await harness.createUser({ prefix: 'q3' });
      const inserted = await harness.database.query<{ id: string }>(
        `INSERT INTO public_deletion_requests (email, matched_user_id)
         VALUES ($1::citext, $2) RETURNING id`,
        [target.email, target.id],
      );
      requestIds.push(inserted.rows[0].id);
      harness.track(inserted.rows[0].id);

      await harness
        .patch(`/admin/deletion-requests/${inserted.rows[0].id}`, superAdmin)
        .send({})
        .expect(204);

      const status = await harness.database.query<{ status: string }>(
        'SELECT status::text FROM users WHERE id = $1',
        [target.id],
      );
      expect(status.rows[0]?.status).toBe('active');
      await harness.get('/profiles/me', target).expect(200);
    });
  });
});
