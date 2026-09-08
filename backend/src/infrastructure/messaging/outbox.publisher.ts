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
  private activeDrain?: Promise<void>;
  private stopping = false;

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

  async onModuleDestroy(): Promise<void> {
    this.stopping = true;
    if (this.timer) clearInterval(this.timer);
    await this.activeDrain;
  }

  drain(): Promise<void> {
    if (this.stopping) return Promise.resolve();
    if (this.activeDrain) return this.activeDrain;
    this.activeDrain = this.drainBatch().finally(() => { this.activeDrain = undefined; });
    return this.activeDrain;
  }

  private async drainBatch(): Promise<void> {
    try {
      const events = await this.claimBatch();
      if (events.length > 0) await this.publish(events);
    } catch (error) {
      this.logger.error(error, 'Outbox drain failed');
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

  private async publish(events: readonly OutboxRow[]): Promise<void> {
    const ids = events.map((event) => event.id);
    try {
      // BullMQ adds the batch atomically. Stable IDs make retries safe if the
      // Redis write succeeds but the subsequent PostgreSQL acknowledgement fails.
      await this.queue.addBulk(events.map((event) => ({
        name: event.event_type,
        data: event.payload,
        opts: {
          jobId: event.id,
          attempts: 8,
          backoff: { type: 'exponential', delay: 1000 },
          removeOnComplete: { age: 86_400, count: 10_000 },
          removeOnFail: { age: 604_800, count: 50_000 },
        },
      })));
      await this.database.query(
        'UPDATE outbox_events SET processed_at = now(), last_error = NULL WHERE id = ANY($1::uuid[])',
        [ids],
      );
    } catch (error) {
      await this.database.query(
        `UPDATE outbox_events SET last_error = $2,
           available_at = now() + make_interval(secs => LEAST(300, power(2, LEAST(attempts, 8)))::double precision)
         WHERE id = ANY($1::uuid[]) AND processed_at IS NULL`,
        [ids, error instanceof Error ? error.message.slice(0, 2000) : 'Unknown publish error'],
      );
    }
  }
}
