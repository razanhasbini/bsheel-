import { OnApplicationBootstrap, OnModuleDestroy } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Queue } from 'bullmq';
import type { Environment } from '../../config/environment.js';
import { DatabaseService } from '../database/database.service.js';
export declare class OutboxPublisher implements OnApplicationBootstrap, OnModuleDestroy {
    private readonly database;
    private readonly config;
    private readonly queue;
    private readonly logger;
    private timer?;
    private draining;
    constructor(database: DatabaseService, config: ConfigService<Environment, true>, queue: Queue);
    onApplicationBootstrap(): void;
    onModuleDestroy(): void;
    drain(): Promise<void>;
    private claimBatch;
    private publish;
}
