var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Controller, Get } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { SkipThrottle } from '@nestjs/throttler';
import { DatabaseService } from '../../infrastructure/database/database.service.js';
import { RedisService } from '../../infrastructure/redis/redis.service.js';
import { Public } from '../../common/auth/public.decorator.js';
let HealthController = class HealthController {
    database;
    redis;
    constructor(database, redis) {
        this.database = database;
        this.redis = redis;
    }
    live() {
        return { status: 'ok' };
    }
    async ready() {
        await Promise.all([this.database.ping(), this.redis.ping()]);
        return { status: 'ok', dependencies: { postgres: 'up', redis: 'up' } };
    }
};
__decorate([
    Get('live'),
    ApiOperation({ summary: 'Process liveness probe' }),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Object)
], HealthController.prototype, "live", null);
__decorate([
    Get('ready'),
    ApiOperation({ summary: 'Dependency readiness probe' }),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", Promise)
], HealthController.prototype, "ready", null);
HealthController = __decorate([
    ApiTags('health'),
    Controller({ path: 'health', version: '1' }),
    SkipThrottle(),
    Public(),
    __metadata("design:paramtypes", [DatabaseService,
        RedisService])
], HealthController);
export { HealthController };
//# sourceMappingURL=health.controller.js.map