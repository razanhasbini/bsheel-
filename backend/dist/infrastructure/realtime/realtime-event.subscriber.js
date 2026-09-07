var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
var RealtimeEventSubscriber_1;
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RedisService } from '../redis/redis.service.js';
import { RealtimeGateway } from './realtime.gateway.js';
let RealtimeEventSubscriber = RealtimeEventSubscriber_1 = class RealtimeEventSubscriber {
    redis;
    gateway;
    logger = new Logger(RealtimeEventSubscriber_1.name);
    channel;
    subscriber;
    constructor(redis, gateway, config) {
        this.redis = redis;
        this.gateway = gateway;
        this.channel = `${config.get('REDIS_KEY_PREFIX', { infer: true })}realtime-events`;
    }
    async onApplicationBootstrap() {
        this.subscriber = this.redis.client.duplicate();
        this.subscriber.on('message', (channel, raw) => {
            if (channel !== this.channel)
                return;
            try {
                this.gateway.broadcast(JSON.parse(raw));
            }
            catch (error) {
                this.logger.warn(error, 'Discarded malformed realtime event');
            }
        });
        await this.subscriber.subscribe(this.channel);
    }
    async onModuleDestroy() {
        if (!this.subscriber || this.subscriber.status === 'end')
            return;
        await this.subscriber.unsubscribe(this.channel);
        await this.subscriber.quit();
    }
};
RealtimeEventSubscriber = RealtimeEventSubscriber_1 = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [RedisService,
        RealtimeGateway,
        ConfigService])
], RealtimeEventSubscriber);
export { RealtimeEventSubscriber };
//# sourceMappingURL=realtime-event.subscriber.js.map