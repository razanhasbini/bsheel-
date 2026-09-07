import { Injectable, Logger, OnApplicationBootstrap, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Redis } from 'ioredis';
import type { Environment } from '../../config/environment.js';
import { RedisService } from '../redis/redis.service.js';
import type { RealtimeDomainEvent } from './realtime-event.publisher.js';
import { RealtimeGateway } from './realtime.gateway.js';

@Injectable()
export class RealtimeEventSubscriber implements OnApplicationBootstrap, OnModuleDestroy {
  private readonly logger = new Logger(RealtimeEventSubscriber.name);
  private readonly channel: string;
  private subscriber?: Redis;

  constructor(
    private readonly redis: RedisService,
    private readonly gateway: RealtimeGateway,
    config: ConfigService<Environment, true>,
  ) {
    this.channel = `${config.get('REDIS_KEY_PREFIX', { infer: true })}realtime-events`;
  }

  async onApplicationBootstrap(): Promise<void> {
    this.subscriber = this.redis.client.duplicate();
    this.subscriber.on('message', (channel, raw) => {
      if (channel !== this.channel) return;
      try {
        this.gateway.broadcast(JSON.parse(raw) as RealtimeDomainEvent);
      } catch (error) {
        this.logger.warn(error, 'Discarded malformed realtime event');
      }
    });
    await this.subscriber.subscribe(this.channel);
  }

  async onModuleDestroy(): Promise<void> {
    if (!this.subscriber || this.subscriber.status === 'end') return;
    await this.subscriber.unsubscribe(this.channel);
    await this.subscriber.quit();
  }
}
