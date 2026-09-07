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
import { Redis } from 'ioredis';
let RedisService = class RedisService {
    client;
    constructor(config) {
        this.client = new Redis(config.get('REDIS_URL', { infer: true }), {
            keyPrefix: config.get('REDIS_KEY_PREFIX', { infer: true }),
            maxRetriesPerRequest: 2,
            enableReadyCheck: true,
            lazyConnect: true,
        });
    }
    async ping() {
        if (this.client.status === 'wait')
            await this.client.connect();
        await this.client.ping();
    }
    async onModuleDestroy() {
        if (this.client.status !== 'end')
            await this.client.quit();
    }
};
RedisService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService])
], RedisService);
export { RedisService };
//# sourceMappingURL=redis.service.js.map