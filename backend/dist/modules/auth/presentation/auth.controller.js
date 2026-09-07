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
import { Body, Controller, HttpCode, Post, Req } from '@nestjs/common';
import { ApiOperation, ApiTags } from '@nestjs/swagger';
import { CurrentUser } from '../../../common/auth/current-user.decorator.js';
import { Public } from '../../../common/auth/public.decorator.js';
import { AuthService } from '../application/auth.service.js';
import { CompleteEmailConfirmationDto, CompletePasswordRecoveryDto, LoginDto, LogoutDto, OAuthSignInDto, RefreshTokenDto, RegisterDto, RequestEmailConfirmationDto, RequestPasswordRecoveryDto, UpdatePasswordDto, } from './auth.dto.js';
let AuthController = class AuthController {
    service;
    constructor(service) {
        this.service = service;
    }
    register(body, request) {
        return this.service.register(body, request);
    }
    login(body, request) {
        return this.service.login(body, request);
    }
    oauth(body, request) {
        return this.service.oauth(body, request);
    }
    updatePassword(user, body) {
        return this.service.updatePassword(user.id, body.newPassword);
    }
    async requestPasswordRecovery(body) {
        await this.service.requestPasswordRecovery(body.email);
    }
    async completePasswordRecovery(body) {
        await this.service.completePasswordRecovery(body.token, body.newPassword);
    }
    async requestEmailConfirmation(body) {
        await this.service.requestEmailConfirmation(body.email);
    }
    async completeEmailConfirmation(body) {
        await this.service.completeEmailConfirmation(body.token);
    }
    refresh(body, request) {
        return this.service.refresh(body.refreshToken, request);
    }
    async logout(_user, body) {
        await this.service.logout(body.refreshToken);
    }
};
__decorate([
    Public(),
    Post('register'),
    ApiOperation({ summary: 'Create a password account and queue confirmation when required' }),
    __param(0, Body()),
    __param(1, Req()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [RegisterDto, Object]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "register", null);
__decorate([
    Public(),
    HttpCode(200),
    Post('login'),
    ApiOperation({ summary: 'Create a session using email and password' }),
    __param(0, Body()),
    __param(1, Req()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [LoginDto, Object]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "login", null);
__decorate([
    Public(),
    HttpCode(200),
    Post('oauth'),
    ApiOperation({ summary: 'Verify a Google or Apple ID token and create a session' }),
    __param(0, Body()),
    __param(1, Req()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [OAuthSignInDto, Object]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "oauth", null);
__decorate([
    HttpCode(200),
    Post('password'),
    ApiOperation({ summary: 'Change the signed-in user password' }),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, UpdatePasswordDto]),
    __metadata("design:returntype", void 0)
], AuthController.prototype, "updatePassword", null);
__decorate([
    Public(),
    HttpCode(202),
    Post('password-recovery'),
    ApiOperation({ summary: 'Queue a password-recovery email without revealing account existence' }),
    __param(0, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [RequestPasswordRecoveryDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "requestPasswordRecovery", null);
__decorate([
    Public(),
    HttpCode(204),
    Post('password-recovery/complete'),
    ApiOperation({ summary: 'Consume a one-time recovery token and replace the account password' }),
    __param(0, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [CompletePasswordRecoveryDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "completePasswordRecovery", null);
__decorate([
    Public(),
    HttpCode(202),
    Post('email-confirmation/resend'),
    ApiOperation({ summary: 'Queue another confirmation email without revealing account existence' }),
    __param(0, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [RequestEmailConfirmationDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "requestEmailConfirmation", null);
__decorate([
    Public(),
    HttpCode(204),
    Post('email-confirmation/complete'),
    ApiOperation({ summary: 'Consume a one-time token and confirm the account email' }),
    __param(0, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [CompleteEmailConfirmationDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "completeEmailConfirmation", null);
__decorate([
    Public(),
    HttpCode(200),
    Post('refresh'),
    ApiOperation({ summary: 'Rotate a refresh token and issue a new token pair' }),
    __param(0, Body()),
    __param(1, Req()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [RefreshTokenDto, Object]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "refresh", null);
__decorate([
    HttpCode(204),
    Post('logout'),
    ApiOperation({ summary: 'Revoke one refresh session; idempotent' }),
    __param(0, CurrentUser()),
    __param(1, Body()),
    __metadata("design:type", Function),
    __metadata("design:paramtypes", [Object, LogoutDto]),
    __metadata("design:returntype", Promise)
], AuthController.prototype, "logout", null);
AuthController = __decorate([
    ApiTags('auth'),
    Controller({ path: 'auth', version: '1' }),
    __metadata("design:paramtypes", [AuthService])
], AuthController);
export { AuthController };
//# sourceMappingURL=auth.controller.js.map