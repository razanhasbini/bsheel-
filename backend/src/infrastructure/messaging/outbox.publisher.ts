import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger, OnApplicationBootstrap, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Queue } from 'bullmq';
import type { Environment } from '../../config/environment.js';
import { DatabaseService } from '../database/database.service.js';

interface OutboxRow {
  id: string;
  event_type: string;
  payload: Record<string, unknown>;
  attempts: number;
}

@Injectable()
export class OutboxPublisher implements OnApplicationBootstrap, OnModuleDestroy {
  private readonly logger = new Logger(OutboxPublisher.name);
  private timer?: NodeJS.Timeout;
  private draining = false;

  constructor(
    private readonly database: DatabaseService,
    private readonly config: ConfigService<Environment, true>,
    @InjectQueue('domain-events') private readonly queue: Queue,
  ) {}

  onApplicationBootstrap(): void {
    const interval = this.config.get('OUTBOX_POLL_MS', { infer: true });
    this.timer = setInterval(() => void this.drain(), interval);
    this.timer.unref();
    void this.drain();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  async drain(): Promise<void> {
    if (this.draining) return;
    this.draining = true;
    try {
      const events = await this.claimBatch();
      for (const event of events) await this.publish(event);
    } catch (error) {
      this.logger.error(error, 'Outbox drain failed');
    } finally {
      this.draining = false;
    }
  }

  private async claimBatch(): Promise<readonly OutboxRow[]> {
    const batchSize = this.config.get('OUTBOX_BATCH_SIZE', { infer: true });
    const result = await this.database.query<OutboxRow>(
      `WITH candidate AS (
         SELECT id FROM outbox_events
         WHERE processed_at IS NULL AND available_at <= now()
         ORDER BY occurred_at
         FOR UPDATE SKIP LOCKED LIMIT $1
       )
       UPDATE outbox_events event
       SET attempts = event.attempts + 1, available_at = now() + interval '30 seconds'
       FROM candidate WHERE event.id = candidate.id
       RETURNING event.id, event.event_type, event.payload, event.attempts`,
      [batchSize],
    );
    return result.rows;
  }

  private async publish(event: OutboxRow): Promise<void> {
    try {
      await this.queue.add(event.event_type, event.payload, {
        jobId: event.id,
        attempts: 8,
        backoff: { type: 'exponential', delay: 1000 },
        removeOnComplete: { age: 86_400, count: 10_000 },
        removeOnFail: { age: 604_800, count: 50_000 },
      });
      await this.database.query(
        'UPDATE outbox_events SET processed_at = now(), last_error = NULL WHERE id = $1',
        [event.id],
      );
    } catch (error) {
      const delaySeconds = Math.min(300, 2 ** Math.min(event.attempts, 8));
      await this.database.query(
        `UPDATE outbox_events SET last_error = $2, available_at = now() + make_interval(secs => $3)
         WHERE id = $1 AND processed_at IS NULL`,
        [event.id, error instanceof Error ? error.message.slice(0, 2000) : 'Unknown publish error', delaySeconds],
      );
    }
  }
}

