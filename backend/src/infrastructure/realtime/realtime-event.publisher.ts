import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { RedisService } from '../redis/redis.service.js';

export interface RealtimeDomainEvent {
  readonly messageId: string;
  readonly type: string;
  readonly data: Record<string, unknown>;
  /**
   * Aggregate identity and time, carried from the outbox row.
   *
   * These were dropped on the way out, and the Flutter client's
   * `RealtimeDomainEvent.tryParse` requires all three — so it returned null
   * for every event ever sent and the whole realtime feature was inert
   * across 22 files in both apps. Fixed here rather than in the client
   * because the mobile build already in TestFlight has the strict parser
   * compiled in, and a server-side payload change revives it without
   * shipping a new release.
   */
  readonly aggregateType: string;
  readonly aggregateId: string;
  readonly occurredAt: string;
}

@Injectable()
export class RealtimeEventPublisher {
  private readonly channel: string;

  constructor(
    private readonly redis: RedisService,
    config: ConfigService<Environment, true>,
  ) {
    this.channel = `${config.get('REDIS_KEY_PREFIX', { infer: true })}realtime-events`;
  }

  async publish(event: RealtimeDomainEvent): Promise<void> {
    await this.redis.client.publish(this.channel, JSON.stringify(event));
  }
}
