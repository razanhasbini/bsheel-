import { InjectQueue } from '@nestjs/bullmq';
import { Controller, Get, HttpCode, Param, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import type { Queue } from 'bullmq';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Matches, Max, Min } from 'class-validator';
import { Roles } from '../../../common/auth/roles.decorator.js';
import {
  AgentEvidenceRepository,
  type VerificationDossier,
} from '../infrastructure/agent-evidence.repository.js';

export class DossierQuery {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100) limit = 25;
  @IsOptional() @Type(() => Number) @IsInt() @Min(0) offset = 0;
}

export class SubmissionIdParam {
  @Matches(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i)
  id!: string;
}

/**
 * What the agent concluded, and the evidence it concluded it from.
 *
 * Every piece of this was already being recorded and none of it was
 * readable: a moderator was asked to second-guess a decision whose
 * reasoning they could not see, and the CAMARA integration had no surface
 * where anybody could watch it work.
 *
 * Moderator as well as super_admin, because the people who need it most are
 * the ones reviewing what the agent escalated.
 */
@ApiTags('agent-evidence')
@Controller({ path: 'agent/evidence', version: '1' })
export class AgentEvidenceController {
  constructor(
    private readonly repository: AgentEvidenceRepository,
    // The same queue the outbox feeds; the worker's processor picks the job
    // up, gathers CAMARA + CV evidence and applies policy exactly as it
    // would for a fresh submission.
    @InjectQueue('submission-verification') private readonly queue: Queue,
  ) {}

  /**
   * Runs (or re-runs) the network check for one submission, on demand.
   *
   * Exists for the submissions the pipeline never saw: everything submitted
   * while automated verification was paused from the dashboard, or before
   * CAMARA was configured. A moderator looking at one of those has a review
   * card with no location evidence and no way to ask for it — this is the
   * way. It enqueues rather than verifying inline, so the run goes through
   * the one branch that applies the decision and then finishes the run.
   *
   * The evidence generation is a fresh timestamp, which re-opens the
   * idempotency key for exactly this run: a submission already verified
   * gets one more look, and a double click within the same second is still
   * one job.
   */
  @Roles('moderator', 'super_admin')
  @HttpCode(202)
  @Post('submissions/:id/rerun')
  @ApiOperation({ summary: 'Queue a (re-)verification of one submission: CAMARA location evidence + policy' })
  async rerun(@Param() param: SubmissionIdParam): Promise<{ queued: true; evidenceGeneration: string }> {
    const evidenceGeneration = `manual-${Math.floor(Date.now() / 1000)}`;
    await this.queue.add(
      'submission.verify',
      { submissionId: param.id, evidenceGeneration },
      {
        // BullMQ rejects ':' in a custom id.
        jobId: `submission-${param.id}-verification-ev-${evidenceGeneration}`,
        attempts: 3,
        backoff: { type: 'exponential', delay: 5_000 },
        removeOnComplete: { age: 86_400, count: 10_000 },
        removeOnFail: { age: 604_800, count: 50_000 },
      },
    );
    return { queued: true, evidenceGeneration };
  }

  @Roles('moderator', 'super_admin')
  @Get()
  @ApiOperation({ summary: 'Recent verifications with their decision and evidence' })
  recent(@Query() query: DossierQuery): Promise<readonly VerificationDossier[]> {
    return this.repository.recent(query.limit, query.offset);
  }

  @Roles('moderator', 'super_admin')
  @Get('submissions/:id')
  @ApiOperation({ summary: 'The full evidence behind one submission decision' })
  forSubmission(@Param() param: SubmissionIdParam): Promise<VerificationDossier | null> {
    return this.repository.forSubmission(param.id);
  }
}
