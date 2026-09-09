import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, type OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Queue } from 'bullmq';
import type { Environment } from '../../../config/environment.js';

/// Schedules the catch-up sweep for AI proof verification (#47).
///
/// The outbox consumer analyses each submission as it arrives; this exists
/// only for the submissions that path missed — a worker that died between
/// claiming and completing, or a provider outage that failed a batch. Without
/// it those stay unanalysed forever, because nothing re-emits
/// `submission.created`.
///
/// Removes its own schedule when the feature is off, so turning
/// AI_VERIFICATION_ENABLED off stops the job rather than leaving a repeatable
/// that no-ops on every fire.
@Injectable()
export class ProofVerificationScheduler implements OnApplicationBootstrap {
  constructor(
    private readonly config: ConfigService<Environment, true>,
    @InjectQueue('proof-verification') private readonly queue: Queue,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    if (!this.config.get('AI_VERIFICATION_ENABLED', { infer: true })) {
      await this.queue.removeJobScheduler('proof-verification-sweep');
      return;
    }
    await this.queue.upsertJobScheduler(
      'proof-verification-sweep',
      { every: this.config.get('AI_VERIFICATION_SWEEP_INTERVAL_MS', { infer: true }) },
      {
        name: 'proof.verification.sweep',
        data: {},
        opts: {
          attempts: 3,
          backoff: { type: 'exponential', delay: 5_000 },
          removeOnComplete: 100,
          removeOnFail: 1_000,
        },
      },
    );
  }
}
