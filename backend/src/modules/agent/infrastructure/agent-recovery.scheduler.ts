import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, type OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Queue } from 'bullmq';
import type { Environment } from '../../../config/environment.js';

/**
 * Schedules the late-evidence sweep (#15).
 *
 * A geofence entry event can arrive after the agent has already escalated
 * the submission for want of it — a webhook retry, a provider backlog, or
 * our own downtime separates when the device crossed the boundary from when
 * we heard about it. Nothing re-ran those, so a submission waited on a human
 * for evidence that had since turned up.
 *
 * Removes its own schedule when the pipeline is off, so disabling the agent
 * stops the job rather than leaving a repeatable that no-ops on every fire —
 * the same shape as ProofVerificationScheduler.
 */
@Injectable()
export class AgentRecoveryScheduler implements OnApplicationBootstrap {
  constructor(
    private readonly config: ConfigService<Environment, true>,
    @InjectQueue('submission-verification') private readonly queue: Queue,
  ) {}

  async onApplicationBootstrap(): Promise<void> {
    if (!this.config.get('AGENT_SUBMISSION_VERIFICATION_ENABLED', { infer: true })) {
      await this.queue.removeJobScheduler('agent-recovery-sweep');
      return;
    }
    await this.queue.upsertJobScheduler(
      'agent-recovery-sweep',
      { every: this.config.get('AGENT_RECOVERY_SWEEP_INTERVAL_MS', { infer: true }) },
      {
        name: 'submission.verify.recovered',
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
