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
import { Body, Controller, Delete, Get, HttpCode, Param, Post, Put, Query } from '@nestjs/common';
import { Transform, Type } from 'class-transformer';
import { IsBoolean, IsInt, IsOptional, IsUUID, Max, Min } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { SocialService } from '../application/social.service.js';
import { AddCommentDto, BlockUserDto, ReportContentDto, VoteDto } from './social.dto.js';
class IdParam {
    id;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], IdParam.prototype, "id", void 0);
class ListQuery {
    limit = 50;
    offset = 0;
}
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(1),
    Max(200),
    __metadata("design:type", Object)
], ListQuery.prototype, "limit", void 0);
__decorate([
    IsOptional(),
    Type(() => Number),
    IsInt(),
    Min(0),
    __metadata("design:type", Object)
], ListQuery.prototype, "offset", void 0);
class ConnectionQuery extends ListQuery {
    followers = true;
}
__decorate([
    Transform(({ value }) => value === true || value === 'true'),
    IsBoolean(),
    __metadata("design:type", Object)
], ConnectionQuery.prototype, "followers", void 0);
let SocialController = class SocialController {
    service;
    constructor(service) {
        this.service = service;
    }
    getVote(u, p) { return this.service.getVote(u.id, p.id); }
    vote(u, p, b) { return this.service.vote(u.id, p.id, b.type); }
    removeVote(u, p) { return this.service.removeVote(u.id, p.id); }
    comments(p, q) { return this.service.comments(p.id, q.limit, q.offset); }
    addComment(u, p, b) { return this.service.addComment(u.id, p.id, b.body, b.parentId); }
    deleteComment(u, p) { return this.service.deleteComment(u.id, u.role, p.id); }
    async isFollowing(u, p) { return { following: await this.service.isFollowing(u.id, p.id) }; }
    async follow(u, p) { return { id: await this.service.follow(u.id, p.id) }; }
    unfollow(u, p) { return this.service.unfollow(u.id, p.id); }
    connections(p, q) { return this.service.connections(p.id, q.followers, q.limit, q.offset); }
    counts(p) { return this.service.counts(p.id); }
    block(u, p, b) { return this.service.block(u.id, p.id, b.reason); }
    unblock(u, p) { return this.service.unblock(u.id, p.id); }
    blockedUsers(u, q) { return this.service.blockedUsers(u.id, q.limit, q.offset); }
    async report(u, b) { return { id: await this.service.report(u.id, b.reportedType, b.reportedId, b.reason) }; }
    savedPosts(u, q) { return this.service.savedPosts(u.id, q.limit, q.offset); }
    async isPostSaved(u, p) { return { saved: await this.service.isPostSaved(u.id, p.id) }; }
    savePost(u, p) { return this.service.savePost(u.id, p.id, true); }
    unsavePost(u, p) { return this.service.savePost(u.id, p.id, false); }
    savedQuests(u, q) { return this.service.savedQuests(u.id, q.limit, q.offset); }
    async isQuestSaved(u, p) { return { saved: await this.service.isQuestSaved(u.id, p.id) }; }
    saveQuest(u, p) { return this.service.saveQuest(u.id, p.id, true); }
    unsaveQuest(u, p) { return this.service.saveQuest(u.id, p.id, false); }
};
__decorate([
    Get('posts/:id/vote'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "getVote", null);
__decorate([
    Put('posts/:id/vote'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam, VoteDto]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "vote", null);
__decorate([
    HttpCode(204),
    Delete('posts/:id/vote'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "removeVote", null);
__decorate([
    Get('posts/:id/comments'),
    __param(0, Param()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [IdParam, ListQuery]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "comments", null);
__decorate([
    Post('posts/:id/comments'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam, AddCommentDto]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "addComment", null);
__decorate([
    HttpCode(204),
    Delete('comments/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "deleteComment", null);
__decorate([
    Get('users/:id/following'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", Promise)
], SocialController.prototype, "isFollowing", null);
__decorate([
    Post('users/:id/follow'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", Promise)
], SocialController.prototype, "follow", null);
__decorate([
    HttpCode(204),
    Delete('users/:id/follow'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "unfollow", null);
__decorate([
    Get('users/:id/connections'),
    __param(0, Param()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [IdParam, ConnectionQuery]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "connections", null);
__decorate([
    Get('users/:id/follow-counts'),
    __param(0, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "counts", null);
__decorate([
    HttpCode(204),
    Post('users/:id/block'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __param(2, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam, BlockUserDto]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "block", null);
__decorate([
    HttpCode(204),
    Delete('users/:id/block'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "unblock", null);
__decorate([
    Get('blocked-users'),
    __param(0, CurrentUser()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, ListQuery]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "blockedUsers", null);
__decorate([
    Post('reports'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, ReportContentDto]),
    __metadata("design:returntype", Promise)
], SocialController.prototype, "report", null);
__decorate([
    Get('saved/posts'),
    __param(0, CurrentUser()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, ListQuery]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "savedPosts", null);
__decorate([
    Get('saved/posts/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", Promise)
], SocialController.prototype, "isPostSaved", null);
__decorate([
    HttpCode(204),
    Put('saved/posts/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "savePost", null);
__decorate([
    HttpCode(204),
    Delete('saved/posts/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "unsavePost", null);
__decorate([
    Get('saved/quests'),
    __param(0, CurrentUser()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, ListQuery]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "savedQuests", null);
__decorate([
    Get('saved/quests/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", Promise)
], SocialController.prototype, "isQuestSaved", null);
__decorate([
    HttpCode(204),
    Put('saved/quests/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "saveQuest", null);
__decorate([
    HttpCode(204),
    Delete('saved/quests/:id'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, IdParam]),
    __metadata("design:returntype", void 0)
], SocialController.prototype, "unsaveQuest", null);
SocialController = __decorate([
    ApiTags('social'),
    Controller({ path: 'social', version: '1' }),
    __metadata("design:paramtypes", [SocialService])
], SocialController);
export { SocialController };
//# sourceMappingURL=social.controller.js.map