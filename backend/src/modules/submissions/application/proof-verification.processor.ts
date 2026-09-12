import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import type { Job } from 'bullmq';
import { PosterFrameService } from './poster-frame.service.js';
import { ProofVerificationService } from './proof-verification.service.js';

/// Runs the AI proof verification catch-up sweep (#47).
///
/// Concurrency 1: the sweep claims a batch and analyses it serially, and two
/// overlapping sweeps would spend vision calls racing for the same rows.
@Injectable()
@Processor('proof-verification', { concurrency: 1 })
export class ProofVerificationProcessor extends WorkerHost {
  private readonly logger = new Logger(ProofVerificationProcessor.name);

  constructor(
    private readonly verification: ProofVerificationService,
    private readonly posters: PosterFrameService,
  ) {
    super();
  }

  async process(job: Job): Promise<void> {
    const outcome = await this.verification.sweep();
    this.logger.debug({ jobId: job.id, ...outcome }, 'Proof verification sweep finished');

    // Rides this sweep rather than owning a queue: both are small, bounded,
    // ffmpeg-adjacent catch-up work on the same rows, and a second scheduler
    // would be a second thing to turn off. A poster failure must never fail
    // the job — verification is the reason this queue exists, and a missing
    // map thumbnail is not worth a retry storm against it.
    try {
      const posters = await this.posters.sweep();
      if (posters.considered > 0) this.logger.debug({ jobId: job.id, ...posters }, 'Poster sweep finished');
    } catch (error) {
      this.logger.warn(
        { jobId: job.id, err: error instanceof Error ? error.message : String(error) },
        'Poster sweep failed; videos keep their category tint until the next pass',
      );
    }
  }
}
