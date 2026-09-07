import { OnApplicationBootstrap, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { RedisService } from '../redis/redis.service.js';
import { RealtimeGateway } from './realtime.gateway.js';
export declare class RealtimeEventSubscriber implements OnApplicationBootstrap, OnModuleDestroy {
    private readonly redis;
    private readonly gateway;
    private readonly logger;
    private readonly channel;
    private subscriber?;
    constructor(redis: RedisService, gateway: RealtimeGateway, config: ConfigService<Environment, true>);
    onApplicationBootstrap(): Promise<void>;
    onModuleDestroy(): Promise<void>;
}
