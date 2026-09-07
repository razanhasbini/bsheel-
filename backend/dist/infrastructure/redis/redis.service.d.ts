import { OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Redis } from 'ioredis';
import type { Environment } from '../../config/environment.js';
export declare class RedisService implements OnModuleDestroy {
    readonly client: Redis;
    constructor(config: ConfigService<Environment, true>);
    ping(): Promise<void>;
    onModuleDestroy(): Promise<void>;
}
