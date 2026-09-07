import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { RedisService } from '../redis/redis.service.js';

export interface RealtimeDomainEvent {
  readonly messageId: string;
  readonly type: string;
  readonly data: Record<string, unknown>;
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
