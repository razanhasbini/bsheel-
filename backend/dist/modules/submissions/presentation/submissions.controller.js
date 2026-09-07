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
import { Body, Controller, Get, HttpCode, Param, Patch, Post, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import { IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Roles } from '../../../common/auth/roles.decorator.js';
import { SubmissionsService } from '../application/submissions.service.js';
import { AppealSubmissionDto, CreateSubmissionDto, RejectSubmissionDto, ReviewSubmissionDto, SetVisibilityDto } from './submission.dto.js';
class SubmissionListQuery {
    limit = 50;
    offset = 0;
}
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(100),
    __metadata("design:type", Object)
], SubmissionListQuery.prototype, "limit", void 0);
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(0),
    __metadata("design:type", Object)
], SubmissionListQuery.prototype, "offset", void 0);
class SubmissionIdParam {
    id;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], SubmissionIdParam.prototype, "id", void 0);
let SubmissionsController = class SubmissionsController {
    service;
    constructor(service) {
        this.service = service;
    }
    create(user, body) { return this.service.create(user.id, body); }
    listUser(user, params, query) {
        return this.service.listUser(params.id, user.id, query.limit, query.offset);
    }
    pending(query) { return this.service.listPending(query.limit, query.offset); }
    detail(user, params) { return this.service.detail(params.id, user.id); }
    appeal(user, params, body) {
        return this.service.appeal(user.id, params.id, body.appealNote);
    }
    approve(user, params, body) {
        return this.service.approve(user.id, params.id, body.reviewNote);
    }
    reject(user, params, body) {
        return this.service.reject(user.id, params.id, body.reviewNote);
    }
    visibility(user, params, body) {
        return this.service.visibility(user.id, params.id, body.visibility);
    }
};
__decorate([
    Post(),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, CreateSubmissionDto]),
    __metadata("design:returntype", void 0)
], SubmissionsController.prototype, "create", null);
__decorate([
    Get('user/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, SubmissionIdParam, SubmissionListQuery]),
    __metadata("design:returntype", void 0)
], SubmissionsController.prototype, "listUser", null);
__decorate([
    Roles('moderator', 'super_admin'),
    Get('admin/pending'),
    __param(0, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [SubmissionListQuery]),
    __metadata("design:returntype", void 0)
], SubmissionsController.prototype, "pending", null);
__decorate([
    Get(':id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, SubmissionIdParam]),
    __metadata("design:returntype", void 0)
], SubmissionsController.prototype, "detail", null);
__decorate([
    HttpCode(204),
    Post(':id/appeal'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, SubmissionIdParam, AppealSubmissionDto]),
    __metadata("design:returntype", void 0)
], SubmissionsController.prototype, "appeal", null);
__decorate([
    HttpCode(204),
    Roles('moderator', 'super_admin'),
    Post(':id/approve'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, SubmissionIdParam, ReviewSubmissionDto]),
    __metadata("design:returntype", void 0)
], SubmissionsController.prototype, "approve", null);
__decorate([
    HttpCode(204),
    Roles('moderator', 'super_admin'),
    Post(':id/reject'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, SubmissionIdParam, RejectSubmissionDto]),
    __metadata("design:returntype", void 0)
], SubmissionsController.prototype, "reject", null);
__decorate([
    HttpCode(204),
    Patch(':id/visibility'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, SubmissionIdParam, SetVisibilityDto]),
    __metadata("design:returntype", void 0)
], SubmissionsController.prototype, "visibility", null);
SubmissionsController = __decorate([
    ApiTags('submissions'),
    Controller({ path: 'submissions', version: '1' }),
    __metadata("design:paramtypes", [SubmissionsService])
], SubmissionsController);
export { SubmissionsController };
//# sourceMappingURL=submissions.controller.js.map