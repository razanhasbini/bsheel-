import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import type { Job } from 'bullmq';
import { ProofVerificationService } from './proof-verification.service.js';

/// Runs the AI proof verification catch-up sweep (#47).
///
/// Concurrency 1: the sweep claims a batch and analyses it serially, and two
/// overlapping sweeps would spend vision calls racing for the same rows.
@Injectable()
@Processor('proof-verification', { concurrency: 1 })
export class ProofVerificationProcessor extends WorkerHost {
  private readonly logger = new Logger(ProofVerificationProcessor.name);

  constructor(private readonly verification: ProofVerificationService) {
    super();
  }

  async process(job: Job): Promise<void> {
    const outcome = await this.verification.sweep();
    this.logger.debug({ jobId: job.id, ...outcome }, 'Proof verification sweep finished');
  }
}
