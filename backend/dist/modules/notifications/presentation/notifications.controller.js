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
import { IsUUID } from 'class-validator';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { NotificationsService } from '../application/notifications.service.js';
import { DeleteDeviceTokenDto, NotificationListQueryDto, RegisterDeviceTokenDto } from './notifications.dto.js';
class NotificationIdParam {
    id;
}
__decorate([
    IsUUID(),
    __metadata("design:type", String)
], NotificationIdParam.prototype, "id", void 0);
let NotificationsController = class NotificationsController {
    service;
    constructor(service) {
        this.service = service;
    }
    list(user, query) {
        return this.service.list(user.id, query.limit, query.cursor);
    }
    unreadCount(user) { return this.service.unreadCount(user.id); }
    markRead(user, param) {
        return this.service.markRead(user.id, param.id);
    }
    markAllRead(user) { return this.service.markAllRead(user.id); }
    registerDevice(user, body) {
        return this.service.registerDevice(user.id, body.token, body.platform);
    }
    deleteDevice(user, body) {
        return this.service.deleteDevice(user.id, body.token);
    }
};
__decorate([
    Get(),
    __param(0, CurrentUser()),
    __param(1, Query()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, NotificationListQueryDto]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "list", null);
__decorate([
    Get('unread-count'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "unreadCount", null);
__decorate([
    HttpCode(204),
    Patch(':id/read'),
    __param(0, CurrentUser()),
    __param(1, Param()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, NotificationIdParam]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "markRead", null);
__decorate([
    Patch('read-all'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "markAllRead", null);
__decorate([
    Post('devices'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, RegisterDeviceTokenDto]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "registerDevice", null);
__decorate([
    HttpCode(204),
    Delete('devices'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, DeleteDeviceTokenDto]),
    __metadata("design:returntype", void 0)
], NotificationsController.prototype, "deleteDevice", null);
NotificationsController = __decorate([
    ApiTags('notifications'),
    Controller({ path: 'notifications', version: '1' }),
    __metadata("design:paramtypes", [NotificationsService])
], NotificationsController);
export { NotificationsController };
//# sourceMappingURL=notifications.controller.js.map