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
import { Body, Controller, Delete, Get, HttpCode, Param, Post, Put } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { CollabService } from '../application/collab.service.js';
import { CollabAssignmentParam, CollabCodeParam, CollabVoteParam, CreateCollabGroupDto, JoinCollabGroupDto } from './collab.dto.js';
let CollabController = class CollabController {
    service;
    constructor(service) {
        this.service = service;
    }
    create(user, body) {
        return this.service.create(user.id, body.userQuestId, body.mode);
    }
    preview(param) { return this.service.preview(param.code); }
    join(user, body) {
        return this.service.join(user.id, body.code);
    }
    status(user, param) {
        return this.service.status(user.id, param.id);
    }
    abandon(user, param) {
        return this.service.abandon(user.id, param.id);
    }
    vote(user, param) {
        return this.service.vote(user.id, param.groupId, param.submissionId);
    }
    unvote(user, param) {
        return this.service.unvote(user.id, param.groupId, param.submissionId);
    }
};
__decorate([
    Post('groups'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CreateCollabGroupDto]),
    __metadata("design:returntype", void 0)
], CollabController.prototype, "create", null);
__decorate([
    Get('groups/preview/:code'),
    __param(0, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [CollabCodeParam]),
    __metadata("design:returntype", void 0)
], CollabController.prototype, "preview", null);
__decorate([
    Post('groups/join'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, JoinCollabGroupDto]),
    __metadata("design:returntype", void 0)
], CollabController.prototype, "join", null);
__decorate([
    Get('assignments/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CollabAssignmentParam]),
    __metadata("design:returntype", void 0)
], CollabController.prototype, "status", null);
__decorate([
    HttpCode(204),
    Post('assignments/:id/abandon'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CollabAssignmentParam]),
    __metadata("design:returntype", void 0)
], CollabController.prototype, "abandon", null);
__decorate([
    HttpCode(204),
    Put('groups/:groupId/votes/:submissionId'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CollabVoteParam]),
    __metadata("design:returntype", void 0)
], CollabController.prototype, "vote", null);
__decorate([
    HttpCode(204),
    Delete('groups/:groupId/votes/:submissionId'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CollabVoteParam]),
    __metadata("design:returntype", void 0)
], CollabController.prototype, "unvote", null);
CollabController = __decorate([
    ApiTags('collaboration'),
    Controller({ path: 'collab', version: '1' }),
    __metadata("design:paramtypes", [CollabService])
], CollabController);
export { CollabController };
//# sourceMappingURL=collab.controller.js.map