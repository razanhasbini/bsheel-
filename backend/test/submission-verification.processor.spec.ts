import { describe, expect, it, vi } from 'vitest';
import type { ConfigService } from '@nestjs/config';
import type { Job, Queue } from 'bullmq';
import type { Environment } from '../src/config/environment.js';
import type { VerificationDecision } from '../src/modules/agent/domain/agent.schemas.js';
import { SubmissionVerificationProcessor } from '../src/modules/agent/infrastructure/submission-verification.processor.js';
import type { AgentRunsRepository } from '../src/modules/agent/infrastructure/agent-runs.repository.js';
import type { SubmissionVerificationService } from '../src/modules/agent/application/submission-verification.service.js';
import type { SubmissionsService } from '../src/modules/submissions/application/submissions.service.js';

const decision = (value: VerificationDecision['decision']): VerificationDecision => ({
  decision: value,
  confidence: 0.99,
  reasons: ['Evidence assessment completed.'],
  evidenceAssessment: { cv: 'SUPPORTS', locationVerification: 'SUPPORTS', locationRetrieval: 'SUPPORTS', geofencing: 'SUPPORTS', timing: 'SUPPORTS' },
  additionalCapabilitiesUsed: [],
  conflicts: [],
  ...(value === 'HUMAN_REVIEW' ? { humanReviewReason: 'Needs review.' } : {}),
});

function build(options: {
  outcome: unknown;
  shadow?: boolean;
  approveThrows?: boolean;
  recovered?: readonly { submissionId: string; evidenceGeneration: string }[];
}) {
  const calls: string[] = [];
  const submissions = {
    approve: vi.fn(async () => {
      calls.push('approve');
      if (options.approveThrows) throw new Error('approve exploded');
    }),
    reject: vi.fn(async () => { calls.push('reject'); }),
  } as unknown as SubmissionsService;
  const agentRuns = {
    succeed: vi.fn(async () => { calls.push('succeed'); }),
    fail: vi.fn(async () => { calls.push('fail'); }),
  } as unknown as AgentRunsRepository;
  const service = {
    verify: vi.fn(async () => options.outcome),
    findRecoveredEvidence: vi.fn(async () => options.recovered ?? []),
  } as unknown as SubmissionVerificationService;
  const queue = { add: vi.fn(async () => undefined) } as unknown as Queue;
  const config = {
    get: vi.fn((key: keyof Environment) =>
      key === 'AI_VERIFICATION_SHADOW_MODE' ? (options.shadow ?? false) : 25),
  } as unknown as ConfigService<Environment, true>;

  return {
    processor: new SubmissionVerificationProcessor(service, submissions, config, agentRuns, queue),
    calls, submissions, agentRuns, service, queue,
  };
}

const job = (name: string, data: Record<string, unknown> = {}) =>
  ({ id: 'job-1', name, data }) as unknown as Job<Record<string, unknown>, unknown, string>;

/// The order these happen in is the whole point.
///
/// The run used to be marked succeeded inside the service, before the
/// decision was applied. A worker that died in that window — one await wide —
/// left a 'succeeded' run whose decision had never been carried out, and
/// `start()` will not reclaim a succeeded run, so the retry short-circuited
/// and the submission waited on a human forever with no record of why.
describe('SubmissionVerificationProcessor', () => {
  it('applies the decision before finishing the run', async () => {
    const { processor, calls } = build({
      outcome: { runId: 'run-1', decision: decision('APPROVED') },
    });

    await processor.process(job('submission.verify', { submissionId: 'sub-1' }));

    // Not just "both happened" — the order is the invariant.
    expect(calls).toEqual(['approve', 'succeed']);
  });

  it('finishes the run when there is nothing to apply', async () => {
    const { processor, calls } = build({
      outcome: { runId: 'run-1', decision: decision('HUMAN_REVIEW') },
    });

    await processor.process(job('submission.verify', { submissionId: 'sub-1' }));

    // HUMAN_REVIEW is a finished run with no action, not an unfinished one.
    expect(calls).toEqual(['succeed']);
  });

  it('finishes the run in shadow mode without acting', async () => {
    const { processor, calls } = build({
      outcome: { runId: 'run-1', decision: decision('APPROVED') },
      shadow: true,
    });

    await processor.process(job('submission.verify', { submissionId: 'sub-1' }));

    expect(calls).toEqual(['succeed']);
  });

  // An apply that throws must leave the run reclaimable, never succeeded —
  // otherwise the BullMQ retry finds a held idempotency key and does nothing.
  it('fails the run and rethrows when applying throws, and never marks it succeeded', async () => {
    const { processor, calls } = build({
      outcome: { runId: 'run-1', decision: decision('APPROVED') },
      approveThrows: true,
    });

    await expect(
      processor.process(job('submission.verify', { submissionId: 'sub-1' })),
    ).rejects.toThrow('approve exploded');

    expect(calls).toEqual(['approve', 'fail']);
    expect(calls).not.toContain('succeed');
  });

  it('finishes nothing for a run it skipped', async () => {
    const { processor, calls } = build({
      outcome: { runId: '', decision: decision('HUMAN_REVIEW'), skipped: 'ALREADY_RUN' },
    });

    await processor.process(job('submission.verify', { submissionId: 'sub-1' }));

    // A skip carries no run id — succeeding it would finish someone else's.
    expect(calls).toEqual([]);
  });

  it('does nothing at all when there is no context', async () => {
    const { processor, calls } = build({ outcome: null });

    await processor.process(job('submission.verify', { submissionId: 'sub-1' }));

    expect(calls).toEqual([]);
  });

  it('passes the evidence generation through on a re-run', async () => {
    const { processor, service } = build({
      outcome: { runId: 'run-1', decision: decision('HUMAN_REVIEW') },
    });

    await processor.process(
      job('submission.verify', { submissionId: 'sub-1', evidenceGeneration: 'event-9' }),
    );

    expect(service.verify).toHaveBeenCalledWith('sub-1', 'event-9', {
      personaId: undefined,
      demo: undefined,
    });
  });

  it('records a demo evaluation and applies nothing', async () => {
    // The whole mechanism that makes the hackathon demo non-authoritative is
    // this branch returning before the apply below it. A demo run that
    // reaches approve/reject would award XP, complete a quest and advance a
    // journey on the strength of a simulator device somebody picked from a
    // menu — so this is the test that matters most in the file.
    const { processor, service, submissions, agentRuns } = build({
      outcome: { runId: 'run-1', decision: decision('APPROVED'), expectedXp: null },
    });

    await processor.process(
      job('submission.verify', {
        submissionId: 'sub-1',
        evidenceGeneration: 'demo-LOCATION_INSIDE-1',
        personaId: 'LOCATION_INSIDE',
        demo: true,
      }),
    );

    expect(service.verify).toHaveBeenCalledWith('sub-1', 'demo-LOCATION_INSIDE-1', {
      personaId: 'LOCATION_INSIDE',
      demo: true,
    });
    // Approved, and nothing approved.
    expect(submissions.approve).not.toHaveBeenCalled();
    expect(submissions.reject).not.toHaveBeenCalled();
    // Still recorded, so an operator can audit it in the same history.
    // Stored in the SAME shape a real run uses — the decision spread flat,
    // not nested — because the dossier reads `output.decision` as a string.
    // Nesting it made a demo run invisible to the Agent Evidence page, which
    // is the one place it has to be visible.
    expect(agentRuns.succeed).toHaveBeenCalledWith(
      'run-1',
      expect.objectContaining({ decision: 'APPROVED', demo: true, persona: 'LOCATION_INSIDE' }),
    );
  });

  it('still applies an ordinary run, so the demo branch is not a blanket off-switch', async () => {
    const { processor, submissions } = build({
      outcome: { runId: 'run-2', decision: decision('APPROVED') },
    });

    await processor.process(job('submission.verify', { submissionId: 'sub-2' }));

    expect(submissions.approve).toHaveBeenCalled();
  });

  /// The sweep enqueues; it does not verify inline. A sweep that did the work
  /// itself would leave its runs 'running' until the lease expired, because
  /// nothing downstream would finalise them.
  describe('the late-evidence sweep', () => {
    it('enqueues one job per recovered submission, keyed on the evidence', async () => {
      const { processor, queue, submissions } = build({
        outcome: null,
        recovered: [{ submissionId: 'sub-7', evidenceGeneration: 'event-42' }],
      });

      await processor.process(job('submission.verify.recovered'));

      expect(queue.add).toHaveBeenCalledWith(
        'submission.verify',
        { submissionId: 'sub-7', evidenceGeneration: 'event-42' },
        // BullMQ rejects ':' in a custom job id — it reserves the colon for
        // its own Redis key namespacing and throws.
        expect.objectContaining({ jobId: 'submission-sub-7-verification-ev-event-42' }),
      );
      expect(submissions.approve).not.toHaveBeenCalled();
    });

    it('enqueues nothing when there is nothing to recover', async () => {
      const { processor, queue } = build({ outcome: null, recovered: [] });

      await processor.process(job('submission.verify.recovered'));

      expect(queue.add).not.toHaveBeenCalled();
    });
  });

  it('refuses a job name it does not know', async () => {
    const { processor } = build({ outcome: null });

    await expect(processor.process(job('submission.something-else'))).rejects.toThrow(/Unknown/);
  });
});
