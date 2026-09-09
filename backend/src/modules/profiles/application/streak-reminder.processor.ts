import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import type { Job } from 'bullmq';
import { StreakReminderService } from './streak-reminder.service.js';

@Injectable()
@Processor('streak-reminders', { concurrency: 1 })
export class StreakReminderProcessor extends WorkerHost {
  private readonly logger = new Logger(StreakReminderProcessor.name);

  constructor(private readonly reminders: StreakReminderService) {
    super();
  }

  async process(job: Job): Promise<void> {
    const outcome = await this.reminders.sweep();
    this.logger.debug({ jobId: job.id, ...outcome }, 'Streak reminder sweep finished');
  }
}
