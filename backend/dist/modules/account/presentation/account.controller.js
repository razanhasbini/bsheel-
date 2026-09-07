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
import { Body, Controller, Get, HttpCode, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { AccountService } from '../application/account.service.js';
import { RequestDeletionDto } from './account.dto.js';
let AccountController = class AccountController {
    service;
    constructor(service) {
        this.service = service;
    }
    requestExport(user) { return this.service.requestExport(user.id); }
    exports(user) { return this.service.exports(user.id); }
    requestDeletion(user, _body) { return this.service.requestDeletion(user.id); }
};
__decorate([
    Post('exports'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AccountController.prototype, "requestExport", null);
__decorate([
    Get('exports'),
    __param(0, CurrentUser()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object]),
    __metadata("design:returntype", void 0)
], AccountController.prototype, "exports", null);
__decorate([
    HttpCode(202),
    Post('deletion'),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, RequestDeletionDto]),
    __metadata("design:returntype", void 0)
], AccountController.prototype, "requestDeletion", null);
AccountController = __decorate([
    ApiTags('account privacy'),
    Controller({ path: 'account', version: '1' }),
    __metadata("design:paramtypes", [AccountService])
], AccountController);
export { AccountController };
//# sourceMappingURL=account.controller.js.map