import { Processor, WorkerHost } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import type { Job } from 'bullmq';
import { MediaReclaimService } from './media-reclaim.service.js';

@Injectable()
@Processor('media-reclaim', { concurrency: 1 })
export class MediaReclaimProcessor extends WorkerHost {
  private readonly logger = new Logger(MediaReclaimProcessor.name);

  constructor(private readonly reclaim: MediaReclaimService) {
    super();
  }

  async process(job: Job): Promise<void> {
    const outcome = await this.reclaim.sweep();
    this.logger.debug({ jobId: job.id, ...outcome }, 'Media reclaim sweep finished');
  }
}
