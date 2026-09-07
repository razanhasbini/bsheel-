var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var __param = (this && this.__param) || function (paramIndex, decorator) {
    return function (target, key) { decorator(target, key, paramIndex); }
};
var OutboxPublisher_1;
import { InjectQueue } from '@nestjs/bullmq';
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../database/database.service.js';
let OutboxPublisher = OutboxPublisher_1 = class OutboxPublisher {
    database;
    config;
    queue;
    logger = new Logger(OutboxPublisher_1.name);
    timer;
    draining = false;
    constructor(database, config, queue) {
        this.database = database;
        this.config = config;
        this.queue = queue;
    }
    onApplicationBootstrap() {
        const interval = this.config.get('OUTBOX_POLL_MS', { infer: true });
        this.timer = setInterval(() => void this.drain(), interval);
        this.timer.unref();
        void this.drain();
    }
    onModuleDestroy() {
        if (this.timer)
            clearInterval(this.timer);
    }
    async drain() {
        if (this.draining)
            return;
        this.draining = true;
        try {
            const events = await this.claimBatch();
            for (const event of events)
                await this.publish(event);
        }
        catch (error) {
            this.logger.error(error, 'Outbox drain failed');
        }
        finally {
            this.draining = false;
        }
    }
    async claimBatch() {
        const batchSize = this.config.get('OUTBOX_BATCH_SIZE', { infer: true });
        const result = await this.database.query(`WITH candidate AS (
         SELECT id FROM outbox_events
         WHERE processed_at IS NULL AND available_at <= now()
         ORDER BY occurred_at
         FOR UPDATE SKIP LOCKED LIMIT $1
       )
       UPDATE outbox_events event
       SET attempts = event.attempts + 1, available_at = now() + interval '30 seconds'
       FROM candidate WHERE event.id = candidate.id
       RETURNING event.id, event.event_type, event.payload, event.attempts`, [batchSize]);
        return result.rows;
    }
    async publish(event) {
        try {
            await this.queue.add(event.event_type, event.payload, {
                jobId: event.id,
                attempts: 8,
                backoff: { type: 'exponential', delay: 1000 },
                removeOnComplete: { age: 86_400, count: 10_000 },
                removeOnFail: { age: 604_800, count: 50_000 },
            });
            await this.database.query('UPDATE outbox_events SET processed_at = now(), last_error = NULL WHERE id = $1', [event.id]);
        }
        catch (error) {
            const delaySeconds = Math.min(300, 2 ** Math.min(event.attempts, 8));
            await this.database.query(`UPDATE outbox_events SET last_error = $2, available_at = now() + make_interval(secs => $3)
         WHERE id = $1 AND processed_at IS NULL`, [event.id, error instanceof Error ? error.message.slice(0, 2000) : 'Unknown publish error', delaySeconds]);
        }
    }
};
OutboxPublisher = OutboxPublisher_1 = __decorate([
    Injectable(),
    __param(2, InjectQueue('domain-events')),
    __metadata("design:paramtypes", [DatabaseService,
        ConfigService, Function])
], OutboxPublisher);
export { OutboxPublisher };
//# sourceMappingURL=outbox.publisher.js.map