import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ProofVerificationRepository } from '../src/modules/submissions/infrastructure/proof-verification.repository.js';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// Scoring the agent against decisions people already made (#47).
///
/// The eval's ground truth is a human decision, and `verify()` refuses to
/// analyse anything already reviewed — so the ordinary path can only
/// accumulate forward and a database full of moderation history is invisible
/// to it. The backfill reads that history instead.
///
/// Everything here guards one of three properties, each of which makes the
/// difference between a tool you can point at production and one you cannot:
/// it selects only human decisions, it alerts nobody, and it changes nothing.
describe('eval backfill (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let repository: ProofVerificationRepository;
  let moderator: TestUser;

  const analysis = (overrides: Record<string, unknown> = {}) => ({
    tier: 'triage' as const,
    verdict: 'unclear' as const,
    confidence: 0.4,
    relevance: null,
    observations: [],
    rationale: 'backfilled rationale',
    escalationReason: 'could not tell',
    model: 'gpt-5.6-luna',
    inputTokens: 10,
    outputTokens: 5,
    ...overrides,
  });

  /// A submission a moderator really decided, through the real endpoint, so
  /// `reviewed_by` is a genuine actor id rather than a fixture's guess.
  const decidedByHuman = async (
    decision: 'approve' | 'reject',
  ): Promise<{ id: string; userId: string }> => {
    const author = await harness.createUser({ prefix: 'bfill' });
    const submission = await harness.createSubmission(author, { caption: 'decided by a person' });
    if (decision === 'approve') {
      await harness.post(`/submissions/${submission.id}/approve`, moderator).send({}).expect(204);
    } else {
      await harness
        .post(`/submissions/${submission.id}/reject`, moderator)
        .send({ reviewNote: 'Not convincing.' })
        .expect(204);
    }
    return { id: submission.id, userId: author.id };
  };

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    repository = harness.app.get(ProofVerificationRepository);
    moderator = await harness.createUser({ role: 'moderator', prefix: 'bfmod' });
  });

  afterAll(async () => {
    await harness?.close();
  });

  describe('what it selects', () => {
    it('offers a submission a person decided', async () => {
      const submission = await decidedByHuman('approve');
      const ids = await repository.decidedWithoutVerdict(500);
      expect(ids).toContain(submission.id);
    });

    // The guard that makes the whole exercise mean anything. Both automated
    // deciders pass a null actor deliberately, so `reviewed_by IS NOT NULL`
    // is proof a person decided — and without it the agent would be scored
    // against its own past decisions and report near-perfect agreement
    // however wrong it is.
    it('never offers a submission automation decided', async () => {
      const author = await harness.createUser({ prefix: 'bfauto' });
      const submission = await harness.createSubmission(author, { caption: 'decided by a machine' });
      // How both automated paths record a decision: the same repository call
      // a moderator's click uses, with a null actor.
      await harness.database.query(
        `UPDATE submissions SET status = 'approved', reviewed_by = NULL, reviewed_at = now()
         WHERE id = $1`,
        [submission.id],
      );

      expect(await repository.decidedWithoutVerdict(500)).not.toContain(submission.id);
      expect(await repository.evalSubject(submission.id)).toBeNull();
    });

    it('never offers a submission nobody has decided', async () => {
      const author = await harness.createUser({ prefix: 'bfpend' });
      const submission = await harness.createSubmission(author, { caption: 'still pending' });

      expect(await repository.decidedWithoutVerdict(500)).not.toContain(submission.id);
      expect(await repository.evalSubject(submission.id)).toBeNull();
    });

    it('stops offering one once it carries a verdict', async () => {
      const submission = await decidedByHuman('reject');
      expect(await repository.decidedWithoutVerdict(500)).toContain(submission.id);

      await repository.completeForEval(submission.id, analysis(), 'triage', 'fail', 12);
      expect(await repository.decidedWithoutVerdict(500)).not.toContain(submission.id);
    });
  });

  describe('what it writes', () => {
    // The behaviour that would be catastrophic rather than merely wrong.
    // `complete()` alerts every admin when a verdict is 'unclear', in the
    // same transaction, so a live escalation cannot exist without the alert
    // that makes someone look at it. Backfilling a year of history through
    // that path would notify every admin about every old submission the
    // agent found ambiguous — for submissions a human settled long ago.
    it('alerts nobody, however ambiguous the verdict', async () => {
      const submission = await decidedByHuman('approve');
      const before = await harness.countRows(
        "SELECT count(*) FROM notifications WHERE type = 'proof_unclear'",
        [],
      );

      await repository.completeForEval(submission.id, analysis(), 'triage', 'unclear', 20);

      const after = await harness.countRows(
        "SELECT count(*) FROM notifications WHERE type = 'proof_unclear'",
        [],
      );
      expect(after).toBe(before);
      expect(
        await harness.countRows(
          "SELECT count(*) FROM notifications WHERE reference_id = $1 AND type = 'proof_unclear'",
          [submission.id],
        ),
      ).toBe(0);
    });

    // `acted = false` is what marks a row as honest eval data, and a
    // backfilled verdict is the cleanest kind there is: the decision it is
    // scored against was recorded before the verdict existed, so it cannot
    // have influenced it even in principle.
    it('records the verdict as never acted on', async () => {
      const submission = await decidedByHuman('approve');
      await repository.completeForEval(
        submission.id,
        analysis({ verdict: 'pass', relevance: 0.82, observations: [
          { kind: 'action' as const, label: 'a sunrise', present: true, confidence: 0.9 },
        ] }),
        'deep',
        'pass',
        33,
      );

      const row = await repository.contentEvidenceFor(submission.id);
      expect(row?.state).toBe('complete');
      expect(row?.verdict).toBe('pass');
      expect(row?.relevance).toBeCloseTo(0.82, 2);
      expect(row?.observations[0].label).toBe('a sunrise');
      expect(
        await harness.countRows(
          'SELECT count(*) FROM submission_verifications WHERE submission_id = $1 AND acted = false',
          [submission.id],
        ),
      ).toBe(1);
    });

    // Re-runnable, because a backfill is not work the pipeline owes anyone.
    it('can be re-run over the same submission', async () => {
      const submission = await decidedByHuman('reject');
      await repository.completeForEval(submission.id, analysis(), 'triage', 'unclear', 10);
      await repository.completeForEval(submission.id, analysis({ confidence: 0.9 }), 'deep', 'fail', 11);

      const row = await repository.contentEvidenceFor(submission.id);
      expect(row?.verdict).toBe('fail');
      expect(row?.stage).toBe('deep');
    });
  });

  describe('what it must never touch', () => {
    // A backfill that moved review state or paid XP would rewrite the very
    // history it exists to measure.
    it('leaves the decision, the XP and the attempt counter alone', async () => {
      const submission = await decidedByHuman('approve');
      const before = await harness.submission(submission.id);
      const profileBefore = await harness.profile(submission.userId);

      await repository.completeForEval(submission.id, analysis(), 'forensics', 'fail', 15);

      const after = await harness.submission(submission.id);
      expect(after.status).toBe(before.status);
      expect(after.reviewed_by).toBe(before.reviewed_by);
      expect(after.xp_awarded).toBe(before.xp_awarded);
      expect(after.xp_awarded_amount).toBe(before.xp_awarded_amount);
      expect((await harness.profile(submission.userId))?.xp).toBe(profileBefore?.xp);

      // No claim: the attempts a live submission would need are untouched.
      expect(
        await harness.countRows(
          'SELECT count(*) FROM submission_verifications WHERE submission_id = $1 AND attempts = 0',
          [submission.id],
        ),
      ).toBe(1);
    });

    // The unclear queue is for submissions still awaiting a human. A
    // backfilled escalation on a settled submission must not appear there,
    // or scoring history would fill the moderators' queue with work that was
    // finished months ago.
    it('keeps backfilled escalations out of the moderator queue', async () => {
      const submission = await decidedByHuman('reject');
      await repository.completeForEval(submission.id, analysis(), 'triage', 'unclear', 18);

      const queue = await harness.get('/submissions/admin/unclear?limit=100', moderator).expect(200);
      const ids = (queue.body.data as { submission_id: string }[]).map((row) => row.submission_id);
      expect(ids).not.toContain(submission.id);
    });
  });
});
