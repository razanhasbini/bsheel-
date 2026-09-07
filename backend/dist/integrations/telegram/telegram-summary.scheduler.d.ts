import { type OnApplicationBootstrap } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Queue } from 'bullmq';
import type { Environment } from '../../config/environment.js';
export declare class TelegramSummaryScheduler implements OnApplicationBootstrap {
    private readonly config;
    private readonly queue;
    constructor(config: ConfigService<Environment, true>, queue: Queue<Record<string, unknown>, unknown, string>);
    onApplicationBootstrap(): Promise<void>;
}
