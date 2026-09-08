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
import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Public } from '../../../common/auth/public.decorator.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import { AdminService } from '../application/admin.service.js';
import { AdminListQueryDto, ConfigKeyParam, CreateUserDto, ForceResetPasswordDto, InjectQuestDto, RemovePostDto, ReportsQueryDto, ReviewReportDto, SendNotificationDto, SetAccountStatusDto, SetAdminRoleDto, SetConfigDto, SetQotdDto, SetUserXpDto, UpdateUserProfileDto, SuggestionStatusDto, SuggestionsQueryDto, UserIdParam } from './admin.dto.js';
let PublicConfigController = class PublicConfigController {
    service;
    constructor(service) {
        this.service = service;
    }
    publicConfig() { return this.service.publicConfig(); }
};
__decorate([
    Public(),
    Get(),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], PublicConfigController.prototype, "publicConfig", null);
PublicConfigController = __decorate([
    ApiTags('configuration'),
    Controller({ path: 'config', version: '1' }),
    __metadata("design:paramtypes", [AdminService])
], PublicConfigController);
export { PublicConfigController };
let AdminController = class AdminController {
    service;
    constructor(service) {
        this.service = service;
    }
    me(user) { return this.service.me(user.id); }
    stats() { return this.service.stats(); }
    xpAudit(query) { return this.service.xpAudit(query.limit, query.offset); }
    users(query) { return this.service.users(query.q, query.limit, query.offset); }
    createUser(user, body) {
        return this.service.createUser(user.id, body);
    }
    deleteUser(user, param) {
        return this.service.deleteUser(user.id, param.id);
    }
    setAdminRole(user, param, body) {
        return this.service.setAdminRole(user.id, param.id, body.role);
    }
    forceResetPassword(user, param, body) {
        return this.service.forceResetPassword(user.id, param.id, body.newPassword);
    }
    requestPasswordRecovery(user, param) {
        return this.service.requestPasswordRecovery(user.id, param.id);
    }
    setStatus(user, param, body) { return this.service.setStatus(user.id, param.id, body.status, body.reason); }
    updateUserProfile(user, param, body) {
        return this.service.updateUserProfile(user.id, param.id, body);
    }
    setXp(user, param, body) { return this.service.setXp(user.id, param.id, body.xp, body.level, body.questsCompleted, body.reason); }
    reports(query) { return this.service.reports(query.status, query.limit, query.offset); }
    reviewReport(user, param, body) { return this.service.reviewReport(user.id, param.id, body.status, body.adminNote); }
    removePost(user, param, body) {
        return this.service.removePost(user.id, param.id, body.reason);
    }
    injections(query) { return this.service.injections(query.limit, query.offset); }
    inject(user, body) { return this.service.inject(user.id, body); }
    cancelInjection(user, param) { return this.service.cancelInjection(user.id, param.id); }
    notify(user, body) { return this.service.notify(user.id, body.targetUserId, body.title, body.body, body.type); }
    notifications(query) {
        return this.service.notifications(query.limit, query.offset);
    }
    config() { return this.service.config(); }
    setConfig(user, param, body) { return this.service.setConfig(user.id, param.key, body.value, body.description, body.isPublic); }
    qotd(query) { return this.service.qotd(query.limit, query.offset); }
    setQotd(user, body) { return this.service.setQotd(user.id, body); }
    deleteQotd(param) { return this.service.deleteQotd(param.id); }
    waitlist(query) { return this.service.waitlist(query.limit, query.offset); }
    suggestions(query) { return this.service.suggestions(query.status, query.limit, query.offset); }
    reviewSuggestion(user, param, body) { return this.service.reviewSuggestion(user.id, param.id, body.status, body.xpReward, body.durationHours); }
};
__decorate([
    Get('me'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "me", null);
__decorate([
    Get('stats'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "stats", null);
__decorate([
    Roles('super_admin'),
    Get('xp-audit'),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [AdminListQueryDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "xpAudit", null);
__decorate([
    Get('users'),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [AdminListQueryDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "users", null);
__decorate([
    Throttle({ default: { limit: 10, ttl: 60_000 } }),
    Post('users'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CreateUserDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "createUser", null);
__decorate([
    Roles('super_admin'),
    Throttle({ default: { limit: 5, ttl: 60_000 } }),
    HttpCode(202),
    Delete('users/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "deleteUser", null);
__decorate([
    Roles('super_admin'),
    Throttle({ default: { limit: 5, ttl: 60_000 } }),
    HttpCode(204),
    Put('users/:id/role'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam, SetAdminRoleDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "setAdminRole", null);
__decorate([
    Roles('super_admin'),
    Throttle({ default: { limit: 3, ttl: 60_000 } }),
    HttpCode(204),
    Post('users/:id/password'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam,
        ForceResetPasswordDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "forceResetPassword", null);
__decorate([
    Throttle({ default: { limit: 3, ttl: 60_000 } }),
    HttpCode(202),
    Post('users/:id/password-recovery'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "requestPasswordRecovery", null);
__decorate([
    Roles('super_admin'),
    HttpCode(204),
    Patch('users/:id/status'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam, SetAccountStatusDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "setStatus", null);
__decorate([
    Roles('super_admin'),
    HttpCode(204),
    Patch('users/:id/profile'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam, UpdateUserProfileDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "updateUserProfile", null);
__decorate([
    Roles('super_admin'),
    HttpCode(204),
    Patch('users/:id/xp'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam, SetUserXpDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "setXp", null);
__decorate([
    Get('reports'),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [ReportsQueryDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "reports", null);
__decorate([
    HttpCode(204),
    Patch('reports/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam, ReviewReportDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "reviewReport", null);
__decorate([
    HttpCode(204),
    Post('submissions/:id/remove'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam, RemovePostDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "removePost", null);
__decorate([
    Get('injections'),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [AdminListQueryDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "injections", null);
__decorate([
    Post('injections'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, InjectQuestDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "inject", null);
__decorate([
    HttpCode(204),
    Delete('injections/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "cancelInjection", null);
__decorate([
    Post('notifications'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, SendNotificationDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "notify", null);
__decorate([
    Get('notifications'),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [AdminListQueryDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "notifications", null);
__decorate([
    Roles('super_admin'),
    Get('config'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "config", null);
__decorate([
    Roles('super_admin'),
    Put('config/:key'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, ConfigKeyParam, SetConfigDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "setConfig", null);
__decorate([
    Get('qotd'),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [AdminListQueryDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "qotd", null);
__decorate([
    Put('qotd'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, SetQotdDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "setQotd", null);
__decorate([
    HttpCode(204),
    Delete('qotd/:id'),
    __param(0, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [UserIdParam]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "deleteQotd", null);
__decorate([
    Get('waitlist'),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [AdminListQueryDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "waitlist", null);
__decorate([
    Get('suggestions'),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [SuggestionsQueryDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "suggestions", null);
__decorate([
    Patch('suggestions/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserIdParam, SuggestionStatusDto]),
    __metadata("design:returntype", void 0)
], AdminController.prototype, "reviewSuggestion", null);
AdminController = __decorate([
    ApiTags('admin'),
    Roles('moderator', 'super_admin'),
    Controller({ path: 'admin', version: '1' }),
    __metadata("design:paramtypes", [AdminService])
], AdminController);
export { AdminController };
//# sourceMappingURL=admin.controller.js.map