var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthService } from './application/auth.service.js';
import { AccessTokenStrategy } from './infrastructure/access-token.strategy.js';
import { AuthActionTokenCipher } from './infrastructure/auth-action-token-cipher.js';
import { AuthRepository } from './infrastructure/auth.repository.js';
import { OAuthIdentityVerifier } from './infrastructure/oauth-identity-verifier.js';
import { AuthController } from './presentation/auth.controller.js';
let AuthModule = class AuthModule {
};
AuthModule = __decorate([
    Module({
        imports: [PassportModule, JwtModule.register({})],
        controllers: [AuthController],
        providers: [
            AuthService,
            AuthRepository,
            OAuthIdentityVerifier,
            AuthActionTokenCipher,
            AccessTokenStrategy,
        ],
        exports: [AuthService, AuthRepository, AuthActionTokenCipher],
    })
], AuthModule);
export { AuthModule };
//# sourceMappingURL=auth.module.js.map