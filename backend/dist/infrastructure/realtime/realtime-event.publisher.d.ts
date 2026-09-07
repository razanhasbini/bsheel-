import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { RedisService } from '../redis/redis.service.js';
export interface RealtimeDomainEvent {
    readonly messageId: string;
    readonly type: string;
    readonly data: Record<string, unknown>;
}
export declare class RealtimeEventPublisher {
    private readonly redis;
    private readonly channel;
    constructor(redis: RedisService, config: ConfigService<Environment, true>);
    publish(event: RealtimeDomainEvent): Promise<void>;
}
