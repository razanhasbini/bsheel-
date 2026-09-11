import { InjectQueue, Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Job, Queue } from 'bullmq';
import type { Environment } from '../../../config/environment.js';
import { SubmissionsService } from '../../submissions/application/submissions.service.js';
import { SubmissionVerificationService } from '../application/submission-verification.service.js';
import { AgentRunsRepository } from './agent-runs.repository.js';

interface SubmissionVerifyPayload {
  readonly submissionId: string;
  /// Present only on a re-run triggered by late evidence (#15); it re-opens
  /// the idempotency key for exactly that generation of evidence.
  readonly evidenceGeneration?: string;
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
    @InjectQueue('submission-verification') private readonly queue: Queue,
  ) {
    super();
  }

  async process(job: Job<Record<string, unknown>, unknown, string>): Promise<void> {
    // The late-evidence sweep (#15): re-verifies submissions whose geofence
    // event arrived after the agent had already escalated them. It runs on
    // this queue rather than its own because it produces exactly the work
    // this processor already does.
    if (job.name === 'submission.verify.recovered') {
      // Enqueues rather than verifying inline, so every run — first pass or
      // re-run — goes through the one branch below that applies the decision
      // and only then finishes the run. A sweep that did the work itself
      // would leave its runs 'running' until the lease expired, because
      // nothing downstream would ever finalise them.
      const recovered = await this.service.findRecoveredEvidence(
        this.config.get('AGENT_RECOVERY_SWEEP_BATCH_SIZE', { infer: true }),
      );
      for (const { submissionId, evidenceGeneration } of recovered) {
        await this.queue.add(
          'submission.verify',
          { submissionId, evidenceGeneration },
          {
            // Keyed on the evidence generation, so the same late event
            // enqueued twice is one job. BullMQ rejects ':' in a custom id.
            jobId: `submission-${submissionId}-verification-ev-${evidenceGeneration}`,
            attempts: 3,
            backoff: { type: 'exponential', delay: 5_000 },
            removeOnComplete: { age: 86_400, count: 10_000 },
            removeOnFail: { age: 604_800, count: 50_000 },
          },
        );
      }
      this.logger.debug({ jobId: job.id, enqueued: recovered.length }, 'Late-evidence sweep finished');
      return;
    }
    if (job.name !== 'submission.verify') {
      throw new Error(`Unknown submission-verification job: ${job.name}`);
    }
    const payload = this.payload(job.data);
    const outcome = await this.service.verify(payload.submissionId, payload.evidenceGeneration);
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
        // The run is still 'running' here, and it must not become
        // 'succeeded': the service is deliberately not allowed to write to
        // submissions itself, so a run whose apply threw carries a decision
        // nobody carried out. Left succeeded, BullMQ's retry would find a
        // held idempotency key and do nothing at all — the decision dropped
        // in silence.
        //
        // Marking the run failed is what makes the retry a retry: start()
        // reclaims a failed row, so the next attempt evaluates and applies
        // again. Rethrowing is what makes BullMQ attempt it. (A worker that
        // dies here instead of throwing leaves the row 'running' and its
        // lease expiry does the same job.)
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

    // The run is finished only now, once the decision has been carried out —
    // or established as needing no action, which HUMAN_REVIEW, a skip and
    // shadow mode all are. Until this line the run is 'running', so a worker
    // that dies anywhere above leaves a claim the lease reclaims rather than
    // a 'succeeded' run whose decision nobody ever applied.
    if (!outcome.skipped) {
      await this.agentRuns.succeed(outcome.runId, outcome.decision);
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
    return {
      submissionId: data.submissionId,
      ...(typeof data.evidenceGeneration === 'string'
        ? { evidenceGeneration: data.evidenceGeneration }
        : {}),
    };
  }
}
