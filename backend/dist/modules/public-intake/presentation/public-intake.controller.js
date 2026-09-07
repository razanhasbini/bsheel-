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
import { Body, Controller, Post } from '@nestjs/common';
import { Throttle } from '@nestjs/throttler';
import { ApiTags } from '@nestjs/swagger';
import { Public } from '../../../common/auth/public.decorator.js';
import { PublicIntakeService } from '../application/public-intake.service.js';
import { JoinWaitlistDto, SubmitQuestSuggestionDto } from './public-intake.dto.js';
let PublicIntakeController = class PublicIntakeController {
    service;
    constructor(service) {
        this.service = service;
    }
    joinWaitlist(body) { return this.service.joinWaitlist(body.email, body.source); }
    suggest(body) { return this.service.submitSuggestion(body); }
};
__decorate([
    Post('waitlist'),
    __param(0, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [JoinWaitlistDto]),
    __metadata("design:returntype", void 0)
], PublicIntakeController.prototype, "joinWaitlist", null);
__decorate([
    Post('quest-suggestions'),
    __param(0, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [SubmitQuestSuggestionDto]),
    __metadata("design:returntype", void 0)
], PublicIntakeController.prototype, "suggest", null);
PublicIntakeController = __decorate([
    Public(),
    Throttle({ default: { limit: 5, ttl: 60_000 } }),
    ApiTags('public intake'),
    Controller({ path: 'public', version: '1' }),
    __metadata("design:paramtypes", [PublicIntakeService])
], PublicIntakeController);
export { PublicIntakeController };
//# sourceMappingURL=public-intake.controller.js.map