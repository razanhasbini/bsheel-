import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Job } from 'bullmq';
import type { Environment } from '../../../config/environment.js';
import { SubmissionsService } from '../../submissions/application/submissions.service.js';
import { SubmissionVerificationService } from '../application/submission-verification.service.js';
import { AgentRunsRepository } from './agent-runs.repository.js';

interface SubmissionVerifyPayload {
  readonly submissionId: string;
}

// @Processor concurrency must be a literal at decoration time (no DI
// container yet), so this reads the raw env var directly — same
// non-critical, safely-defaulted tuning knob as MEDIA_RECLAIM_BATCH_SIZE,
// just not one Zod can validate at this point in the module graph.
const CONCURRENCY = Number(process.env.SUBMISSION_VERIFICATION_CONCURRENCY) || 2;

@Injectable()
@Processor('submission-verification', { concurrency: CONCURRENCY })
export class SubmissionVerificationProcessor extends WorkerHost {
  private readonly logger = new Logger(SubmissionVerificationProcessor.name);

  constructor(
    private readonly service: SubmissionVerificationService,
    private readonly submissions: SubmissionsService,
    private readonly config: ConfigService<Environment, true>,
    private readonly agentRuns: AgentRunsRepository,
  ) {
    super();
  }

  async process(job: Job<Record<string, unknown>, unknown, string>): Promise<void> {
    // The late-evidence sweep (#15): re-verifies submissions whose geofence
    // event arrived after the agent had already escalated them. It runs on
    // this queue rather than its own because it produces exactly the work
    // this processor already does.
    if (job.name === 'submission.verify.recovered') {
      const outcome = await this.service.sweepRecoveredEvidence(
        this.config.get('AGENT_RECOVERY_SWEEP_BATCH_SIZE', { infer: true }),
      );
      this.logger.debug({ jobId: job.id, ...outcome }, 'Late-evidence sweep finished');
      return;
    }
    if (job.name !== 'submission.verify') {
      throw new Error(`Unknown submission-verification job: ${job.name}`);
    }
    const payload = this.payload(job.data);
    const outcome = await this.service.verify(payload.submissionId);
    if (!outcome) {
      this.logger.debug({ submissionId: payload.submissionId }, 'No agent context; nothing to verify');
      return;
    }
    // Shadow mode governs this path too, and that is the point of it.
    //
    // It used to govern only the #47 cascade, which was harmless while the
    // agent had no computer-vision evidence: `finalizeDecision` refuses to
    // act without it, so every submission became HUMAN_REVIEW and this branch
    // was unreachable. Binding a CV provider makes it reachable — so without
    // this check, giving the agent eyes would also, silently, be the change
    // that started approving real users' quests automatically on a deployment
    // that had only ever set AGENT_SUBMISSION_VERIFICATION_ENABLED.
    //
    // One switch for "may automation act", read by both verifiers, is also
    // the honest shape: the eval slice is only honest data while nothing has
    // acted, and two independent authority flags could disagree about that.
    const shadow = this.config.get('AI_VERIFICATION_SHADOW_MODE', { infer: true });
    if (!outcome.skipped && outcome.decision.decision !== 'HUMAN_REVIEW' && !shadow) {
      const note = outcome.decision.reasons.join(' | ');
      const source = { decision_source: 'openai_agent', agent_run_id: outcome.runId };
      try {
        if (outcome.decision.decision === 'APPROVED') {
          await this.submissions.approve(null, payload.submissionId, note, source);
        } else {
          await this.submissions.reject(null, payload.submissionId, note, source);
        }
      } catch (error) {
        // The run is already marked 'succeeded' by the time this branch is
        // reached — the service records its decision before handing it back,
        // because it is deliberately not allowed to write to submissions
        // itself. So an apply that throws leaves a succeeded run whose
        // decision was never carried out, and BullMQ's retry then finds a
        // held idempotency key and does nothing at all. The decision is
        // dropped in silence.
        //
        // Marking the run failed is what makes the retry a retry: start()
        // reclaims a failed row, so the next attempt evaluates and applies
        // again. Rethrowing is what makes BullMQ attempt it.
        //
        // Failing safe either way — the submission stays pending and a
        // moderator sees it in the ordinary queue — but "safe" and "silent"
        // are different things, and only one of them is acceptable.
        await this.agentRuns.fail(
          outcome.runId,
          'APPLY_FAILED',
          error instanceof Error ? error.message : 'Applying the agent decision failed',
        );
        this.logger.error(
          {
            submissionId: payload.submissionId,
            runId: outcome.runId,
            decision: outcome.decision.decision,
            errorName: error instanceof Error ? error.name : 'UnknownError',
          },
          'Agent decision could not be applied; run marked failed so the retry re-evaluates',
        );
        throw error;
      }
    }
    this.logger.log(
      {
        submissionId: payload.submissionId,
        runId: outcome.runId,
        decision: outcome.decision.decision,
        confidence: outcome.decision.confidence,
        skipped: outcome.skipped,
        shadow,
      },
      shadow ? 'Shadow mode: agent decision recorded, not acted on' : 'Submission verification run recorded',
    );
  }

  private payload(data: Record<string, unknown>): SubmissionVerifyPayload {
    if (typeof data.submissionId !== 'string') {
      throw new Error('submission.verify payload is malformed');
    }
    return { submissionId: data.submissionId };
  }
}
