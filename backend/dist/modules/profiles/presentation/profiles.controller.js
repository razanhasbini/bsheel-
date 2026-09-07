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
import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, Max, Min } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { ProfilesService } from '../application/profiles.service.js';
import { AnalyticsConsentDto, UpdateProfileDto } from './profile.dto.js';
class ProfileListQuery {
    limit = 200;
}
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(200),
    __metadata("design:type", Object)
], ProfileListQuery.prototype, "limit", void 0);
let ProfilesController = class ProfilesController {
    service;
    constructor(service) {
        this.service = service;
    }
    xpStats(user) { return this.service.xpStats(user.id); }
    me(user) { return this.service.ownProfile(user.id); }
    update(user, body) { return this.service.update(user.id, body); }
    async analyticsConsent(user, body) {
        return { analytics_consent_at: await this.service.setAnalyticsConsent(user.id, body.consented) };
    }
    async acceptTerms(user) {
        return { accepted_terms_at: await this.service.acceptTerms(user.id) };
    }
    accountStatus(user) { return this.service.accountStatus(user.id); }
    list(query) { return this.service.list(query.limit); }
    get(id) { return this.service.publicProfile(id); }
};
__decorate([
    Get('me/xp-stats'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], ProfilesController.prototype, "xpStats", null);
__decorate([
    Get('me'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], ProfilesController.prototype, "me", null);
__decorate([
    Patch('me'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UpdateProfileDto]),
    __metadata("design:returntype", void 0)
], ProfilesController.prototype, "update", null);
__decorate([
    Patch('me/analytics-consent'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, AnalyticsConsentDto]),
    __metadata("design:returntype", Promise)
], ProfilesController.prototype, "analyticsConsent", null);
__decorate([
    Post('me/accept-terms'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], ProfilesController.prototype, "acceptTerms", null);
__decorate([
    Get('me/account-status'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], ProfilesController.prototype, "accountStatus", null);
__decorate([
    Get(),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [ProfileListQuery]),
    __metadata("design:returntype", void 0)
], ProfilesController.prototype, "list", null);
__decorate([
    Get(':id'),
    __param(0, Param('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], ProfilesController.prototype, "get", null);
ProfilesController = __decorate([
    ApiTags('profiles'),
    Controller({ path: 'profiles', version: '1' }),
    __metadata("design:paramtypes", [ProfilesService])
], ProfilesController);
export { ProfilesController };
//# sourceMappingURL=profiles.controller.js.map