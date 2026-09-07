var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { RedisService } from '../redis/redis.service.js';
let RealtimeEventPublisher = class RealtimeEventPublisher {
    redis;
    channel;
    constructor(redis, config) {
        this.redis = redis;
        this.channel = `${config.get('REDIS_KEY_PREFIX', { infer: true })}realtime-events`;
    }
    async publish(event) {
        await this.redis.client.publish(this.channel, JSON.stringify(event));
    }
};
RealtimeEventPublisher = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [RedisService,
        ConfigService])
], RealtimeEventPublisher);
export { RealtimeEventPublisher };
//# sourceMappingURL=realtime-event.publisher.js.map