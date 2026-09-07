import { DatabaseService } from '../../infrastructure/database/database.service.js';
import { RedisService } from '../../infrastructure/redis/redis.service.js';
export declare class HealthController {
    private readonly database;
    private readonly redis;
    constructor(database: DatabaseService, redis: RedisService);
    live(): {
        status: 'ok';
    };
    ready(): Promise<{
        status: 'ok';
        dependencies: Record<string, 'up'>;
    }>;
}
