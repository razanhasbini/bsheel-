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
import { Body, Controller, Delete, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { IsUUID } from 'class-validator';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import { QuestsService } from '../application/quests.service.js';
import { BulkCreateQuestsDto, CreateQuestDto, DeleteAllQuestsDto, FollowingActiveQueryDto, QuestHistoryQueryDto, QuestIdDto, QuestPickerQueryDto, UpdateQuestDto, UserQuestIdDto } from './quest.dto.js';
class AdminAssignQuestDto {
    userId;
    questId;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], AdminAssignQuestDto.prototype, "userId", void 0);
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], AdminAssignQuestDto.prototype, "questId", void 0);
let QuestsController = class QuestsController {
    service;
    constructor(service) {
        this.service = service;
    }
    active(user) { return this.service.active(user.id); }
    history(user, query) {
        return this.service.history(user.id, query.limit, query.offset);
    }
    picker(user, query) { return this.service.picker(user.id, query.count); }
    qotd() { return this.service.qotd(); }
    followingActive(user, query) {
        return this.service.followingActive(user.id, query.limit);
    }
    async rerollsRemaining(user) { return { remaining: await this.service.rerollsRemaining(user.id) }; }
    async reroll(user) { return { remaining: await this.service.reroll(user.id) }; }
    assign(user, body) { return this.service.assign(user.id, body.questId); }
    expire(user, body) { return this.service.expire(user.id, body.userQuestId); }
    get(id) { return this.service.getQuest(id); }
    assignForUser(body) {
        return this.service.assignForUser(body.userId, body.questId);
    }
    allAdmin() { return this.service.listAll(); }
    create(user, body) { return this.service.create(body, user.id); }
    createBulk(user, body) {
        return this.service.createBulk(body.quests, user.id);
    }
    update(id, body) { return this.service.update(id, body); }
    delete(user, id) {
        return this.service.delete(id, user.id);
    }
    deleteAll(user, body) {
        return this.service.deleteAll(user.id, body.confirmation);
    }
};
__decorate([
    Get('active'),
    ApiOperation({ summary: "Get the caller's assigned or submitted quest" }),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "active", null);
__decorate([
    Get('history'),
    __param(0, CurrentUser()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, QuestHistoryQueryDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "history", null);
__decorate([
    Get('picker'),
    __param(0, CurrentUser()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, QuestPickerQueryDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "picker", null);
__decorate([
    Get('quest-of-the-day'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "qotd", null);
__decorate([
    Get('following-active'),
    __param(0, CurrentUser()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, FollowingActiveQueryDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "followingActive", null);
__decorate([
    Get('rerolls/remaining'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], QuestsController.prototype, "rerollsRemaining", null);
__decorate([
    Post('rerolls'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", Promise)
], QuestsController.prototype, "reroll", null);
__decorate([
    Post('assign'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, QuestIdDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "assign", null);
__decorate([
    HttpCode(204),
    Post('expire'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UserQuestIdDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "expire", null);
__decorate([
    Get(':id'),
    __param(0, Param('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "get", null);
__decorate([
    Roles('moderator', 'super_admin'),
    Post('admin/assign'),
    __param(0, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [AdminAssignQuestDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "assignForUser", null);
__decorate([
    Roles('super_admin'),
    Get('admin/all'),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", []),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "allAdmin", null);
__decorate([
    Roles('super_admin'),
    Post('admin'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CreateQuestDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "create", null);
__decorate([
    Roles('super_admin'),
    Post('admin/bulk'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, BulkCreateQuestsDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "createBulk", null);
__decorate([
    Roles('super_admin'),
    Patch('admin/:id'),
    __param(0, Param('id')),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [String, UpdateQuestDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "update", null);
__decorate([
    Roles('super_admin'),
    HttpCode(204),
    Delete('admin/:id'),
    __param(0, CurrentUser()),
    __param(1, Param('id')),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, String]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "delete", null);
__decorate([
    Roles('super_admin'),
    Delete('admin'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, DeleteAllQuestsDto]),
    __metadata("design:returntype", void 0)
], QuestsController.prototype, "deleteAll", null);
QuestsController = __decorate([
    ApiTags('quests'),
    Controller({ path: 'quests', version: '1' }),
    __metadata("design:paramtypes", [QuestsService])
], QuestsController);
export { QuestsController };
//# sourceMappingURL=quests.controller.js.map