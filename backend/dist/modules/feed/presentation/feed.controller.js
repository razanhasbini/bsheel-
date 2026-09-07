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
import { Controller, Get, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { FeedService } from '../application/feed.service.js';
import { FeedQueryDto } from './feed.dto.js';
let FeedController = class FeedController {
    service;
    constructor(service) {
        this.service = service;
    }
    list(user, query) { return this.service.list(user.id, query); }
};
__decorate([
    Get(),
    __param(0, CurrentUser()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, FeedQueryDto]),
    __metadata("design:returntype", void 0)
], FeedController.prototype, "list", null);
FeedController = __decorate([
    ApiTags('feed'),
    Controller({ path: 'feed', version: '1' }),
    __metadata("design:paramtypes", [FeedService])
], FeedController);
export { FeedController };
//# sourceMappingURL=feed.controller.js.map