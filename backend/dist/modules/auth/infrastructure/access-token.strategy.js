var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { AuthRepository } from './auth.repository.js';
let AccessTokenStrategy = class AccessTokenStrategy extends PassportStrategy(Strategy, 'jwt') {
    repository;
    constructor(config, repository) {
        super({
            jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
            secretOrKey: config.get('JWT_ACCESS_SECRET', { infer: true }),
            ignoreExpiration: false,
        });
        this.repository = repository;
    }
    async validate(payload) {
        if (payload.type !== 'access')
            throw new UnauthorizedException();
        const account = await this.repository.findActiveAccountById(payload.sub);
        if (!account || account.tokenVersion !== payload.tokenVersion) {
            throw new UnauthorizedException({ code: 'SESSION_REVOKED', message: 'Session is no longer valid' });
        }
        return { id: account.id, email: account.email, role: account.role, tokenVersion: account.tokenVersion };
    }
};
AccessTokenStrategy = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService,
        AuthRepository])
], AccessTokenStrategy);
export { AccessTokenStrategy };
//# sourceMappingURL=access-token.strategy.js.map