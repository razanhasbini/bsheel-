import { ConfigService } from '@nestjs/config';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AgentRunsRepository } from '../src/modules/agent/infrastructure/agent-runs.repository.js';
import { ProofVerificationRepository } from '../src/modules/submissions/infrastructure/proof-verification.repository.js';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// Leases on the two claims that guard expensive work (#47).
///
/// Both used to be labels rather than leases, and both failed in the same
/// direction: a worker killed while holding one left the submission
/// permanently unprocessable, with no error and nothing in the queue to say
/// so. `claim()` additionally let two callers hold the same submission at
/// once, which meant paying for the same vision call twice.
describe('verification claim leases (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let proof: ProofVerificationRepository;
  let runs: AgentRunsRepository;

  const MAX_ATTEMPTS = 5;
  const LEASE = 600;

  /// Ages an existing claim past the lease, standing in for a worker that
  /// took the row and never came back.
  const abandonClaim = (submissionId: string, seconds: number) =>
    harness.database.query(
      `UPDATE submission_verifications
       SET claimed_at = now() - make_interval(secs => $2)
       WHERE submission_id = $1`,
      [submissionId, seconds],
    );

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    proof = harness.app.get(ProofVerificationRepository);
    // AgentModule lives on WorkerModule, not the API app; the repository
    // takes only the database, so it is built directly rather than booting a
    // second application to reach it.
    runs = new AgentRunsRepository(harness.database);
  });

  /// A fresh author per case.
  ///
  /// Sharing one user across the suite couples the cases through the
  /// one-active-quest index: a case that fails partway leaves a quest
  /// assigned, every later `createSubmission` for that user throws
  /// ACTIVE_QUEST_EXISTS, and two real bugs report as seven failures with
  /// five of them lying about their cause.
  const submissionFor = async (caption: string): Promise<{ id: string }> => {
    const author: TestUser = await harness.createUser({ prefix: 'lease' });
    return harness.createSubmission(author, { caption });
  };

  afterAll(async () => {
    await harness?.close();
  });

  describe('the vision pass claim', () => {
    it('grants the claim once and refuses it while the lease holds', async () => {
      const submission = await submissionFor('lease held');

      expect(await proof.claim(submission.id, MAX_ATTEMPTS, LEASE)).not.toBeNull();
      // The second caller is the catch-up sweep arriving while the inline
      // consumer is still in a vision call. Before the lease it got the row
      // too, and both paid for the same photograph.
      expect(await proof.claim(submission.id, MAX_ATTEMPTS, LEASE)).toBeNull();
    });

    it('grants it again once the claim has expired', async () => {
      const submission = await submissionFor('lease expired');

      expect(await proof.claim(submission.id, MAX_ATTEMPTS, LEASE)).not.toBeNull();
      await abandonClaim(submission.id, LEASE + 60);
      // A worker killed mid-analysis must not strand the submission; the
      // expired claim is taken rather than respected.
      expect(await proof.claim(submission.id, MAX_ATTEMPTS, LEASE)).not.toBeNull();
    });

    // The lease must not become a way around the attempt ceiling: a
    // submission whose analysis crashes the worker every time has to stop
    // being retried eventually, or it loops forever on someone's money.
    it('still stops at the attempt ceiling however often the lease expires', async () => {
      const submission = await submissionFor('attempts exhausted');

      for (let attempt = 0; attempt < 2; attempt += 1) {
        expect(await proof.claim(submission.id, 2, LEASE), `attempt ${attempt}`).not.toBeNull();
        await abandonClaim(submission.id, LEASE + 60);
      }
      expect(await proof.claim(submission.id, 2, LEASE)).toBeNull();
    });
  });

  describe('the agent run claim', () => {
    const runInput = (submissionId: string, key: string) => ({
      kind: 'submission_verification' as const,
      subjectType: 'submission' as const,
      subjectId: submissionId,
      idempotencyKey: key,
      model: 'test-model',
      promptVersion: 'v1',
      policyVersion: 'v1',
      inputSnapshot: { note: 'lease fixture' },
    });

    it('grants the claim once and refuses it while the lease holds', async () => {
      const submission = await submissionFor('agent lease held');
      const key = `lease:${submission.id}:held`;

      expect(await runs.start(runInput(submission.id, key), LEASE)).not.toBeNull();
      expect(await runs.start(runInput(submission.id, key), LEASE)).toBeNull();
    });

    // The bug this exists for. `start()`'s reclaim clause read
    // `WHERE status = 'failed'` alone, so a row left 'running' by a restart
    // or an OOM could never be started again: the submission was
    // permanently unevaluable, and the processor logged "nothing to verify"
    // and acknowledged the job.
    it('reclaims a run abandoned in the running state', async () => {
      const submission = await submissionFor('agent lease expired');
      const key = `lease:${submission.id}:expired`;

      const first = await runs.start(runInput(submission.id, key), LEASE);
      expect(first).not.toBeNull();
      expect(first!.status).toBe('running');

      await harness.database.query(
        `UPDATE agent_runs SET started_at = now() - make_interval(secs => $2)
         WHERE idempotency_key = $1`,
        [key, LEASE + 60],
      );

      const reclaimed = await runs.start(runInput(submission.id, key), LEASE);
      expect(reclaimed).not.toBeNull();
      // The same row, restarted — not a duplicate run for one submission.
      expect(reclaimed!.id).toBe(first!.id);
    });

    // A finished run is finished. The lease governs abandonment, never a
    // conclusion, or every expiry would re-spend the model on a submission
    // that already has an answer.
    it('never reclaims a succeeded run, however old', async () => {
      const submission = await submissionFor('agent succeeded');
      const key = `lease:${submission.id}:succeeded`;

      const run = await runs.start(runInput(submission.id, key), LEASE);
      await runs.succeed(run!.id, { decision: 'HUMAN_REVIEW' });
      await harness.database.query(
        `UPDATE agent_runs SET started_at = now() - interval '30 days' WHERE idempotency_key = $1`,
        [key],
      );

      expect(await runs.start(runInput(submission.id, key), LEASE)).toBeNull();
    });

    // What makes a BullMQ retry a retry. The processor marks the run failed
    // when applying the decision throws, and a failed run is reclaimable
    // immediately — waiting out a lease there would delay a decision that
    // has already been made.
    it('reclaims a failed run without waiting for the lease', async () => {
      const submission = await submissionFor('agent apply failed');
      const key = `lease:${submission.id}:failed`;

      const run = await runs.start(runInput(submission.id, key), LEASE);
      await runs.fail(run!.id, 'APPLY_FAILED', 'approve threw');

      expect(await runs.start(runInput(submission.id, key), LEASE)).not.toBeNull();
    });
  });

  /// The lease values are config, not constants, so a deployment can widen
  /// them for a slow provider — and the floors stop someone setting a lease
  /// shorter than a single vision call, which would guarantee the double
  /// spend the lease exists to prevent.
  it('bounds both leases in configuration', () => {
    const config = harness.app.get(ConfigService);
    expect(config.get('AI_VERIFICATION_CLAIM_LEASE_SECONDS')).toBeGreaterThanOrEqual(30);
    expect(config.get('AGENT_RUN_LEASE_SECONDS')).toBeGreaterThanOrEqual(30);
  });
});
