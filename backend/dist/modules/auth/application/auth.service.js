var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { BadRequestException, ForbiddenException, Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { hash, verify } from 'argon2';
import { randomBytes, randomUUID } from 'node:crypto';
import { AuthRepository } from '../infrastructure/auth.repository.js';
import { AuthActionTokenCipher } from '../infrastructure/auth-action-token-cipher.js';
import { OAuthIdentityVerifier } from '../infrastructure/oauth-identity-verifier.js';
import { assertPasswordPolicy } from '../domain/password-policy.js';
let AuthService = class AuthService {
    repository;
    jwt;
    config;
    oauthVerifier;
    actionTokenCipher;
    constructor(repository, jwt, config, oauthVerifier, actionTokenCipher) {
        this.repository = repository;
        this.jwt = jwt;
        this.config = config;
        this.oauthVerifier = oauthVerifier;
        this.actionTokenCipher = actionTokenCipher;
    }
    async register(input, request) {
        if (!input.ageVerified) {
            throw new ForbiddenException({ code: 'AGE_VERIFICATION_REQUIRED', message: 'You must confirm that you are at least 13 years old' });
        }
        assertPasswordPolicy(input.password, input.username, input.email);
        const confirmationRequired = this.config.get('AUTH_EMAIL_CONFIRMATION_REQUIRED', { infer: true });
        const confirmationToken = confirmationRequired
            ? this.actionTokenCipher.protect(randomBytes(32).toString('base64url'))
            : undefined;
        const account = await this.repository.createPasswordAccount({
            ...input,
            passwordHash: await hash(input.password, { type: 2 }),
            confirmation: confirmationToken ? {
                tokenHash: confirmationToken.hash,
                encryptedToken: confirmationToken.encrypted,
                expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
            } : undefined,
        });
        if (confirmationRequired)
            return { confirmationRequired: true };
        return this.issueTokenPair(account, request);
    }
    async login(input, request) {
        const account = await this.repository.findAccountByEmail(input.email);
        const valid = account?.passwordHash ? await verify(account.passwordHash, input.password) : false;
        if (!account || !valid) {
            throw new UnauthorizedException({ code: 'INVALID_CREDENTIALS', message: 'Invalid email or password' });
        }
        if (!account.emailVerified) {
            throw new ForbiddenException({
                code: 'EMAIL_NOT_CONFIRMED',
                message: 'Please confirm your email before logging in',
            });
        }
        if (account.status !== 'active') {
            throw new ForbiddenException({ code: 'ACCOUNT_RESTRICTED', message: `This account is ${account.status}` });
        }
        await this.repository.touchLastLogin(account.id);
        return this.issueTokenPair(account, request);
    }
    async oauth(input, request) {
        const identity = await this.oauthVerifier.verify(input.provider, input.idToken, input.nonce, input.displayName);
        const account = await this.repository.findOrCreateOAuthAccount(identity, input.ageVerified);
        if (account.status !== 'active') {
            throw new ForbiddenException({ code: 'ACCOUNT_RESTRICTED', message: `This account is ${account.status}` });
        }
        await this.repository.touchLastLogin(account.id);
        return this.issueTokenPair(account, request);
    }
    async updatePassword(userId, newPassword) {
        const identity = await this.repository.passwordIdentity(userId);
        if (!identity)
            throw new UnauthorizedException();
        assertPasswordPolicy(newPassword, identity.username, identity.email);
        const account = await this.repository.updatePassword(userId, await hash(newPassword, { type: 2 }));
        return { id: account.id, email: account.email };
    }
    async requestPasswordRecovery(email) {
        const token = randomBytes(32).toString('base64url');
        const protectedToken = this.actionTokenCipher.protect(token);
        await this.repository.requestPasswordRecovery({
            email,
            tokenHash: protectedToken.hash,
            encryptedToken: protectedToken.encrypted,
            expiresAt: new Date(Date.now() + 60 * 60 * 1000),
        });
    }
    async completePasswordRecovery(token, newPassword) {
        const tokenHash = this.actionTokenCipher.hash(token);
        const identity = await this.repository.recoveryIdentity(tokenHash);
        if (!identity) {
            throw this.invalidRecoveryToken();
        }
        assertPasswordPolicy(newPassword, identity.username, identity.email);
        const completed = await this.repository.completePasswordRecovery(identity.tokenId, tokenHash, await hash(newPassword, { type: 2 }));
        if (!completed)
            throw this.invalidRecoveryToken();
    }
    async requestEmailConfirmation(email) {
        const token = randomBytes(32).toString('base64url');
        const protectedToken = this.actionTokenCipher.protect(token);
        await this.repository.requestEmailConfirmation({
            email,
            tokenHash: protectedToken.hash,
            encryptedToken: protectedToken.encrypted,
            expiresAt: new Date(Date.now() + 24 * 60 * 60 * 1000),
        });
    }
    async completeEmailConfirmation(token) {
        const completed = await this.repository.completeEmailConfirmation(this.actionTokenCipher.hash(token));
        if (!completed) {
            throw new BadRequestException({
                code: 'INVALID_CONFIRMATION_TOKEN',
                message: 'The email confirmation link is invalid or expired',
            });
        }
    }
    async refresh(rawToken, request) {
        let payload;
        try {
            payload = await this.jwt.verifyAsync(rawToken, {
                secret: this.config.get('JWT_REFRESH_SECRET', { infer: true }),
            });
            if (payload.type !== 'refresh')
                throw new Error('Wrong token type');
        }
        catch {
            throw new UnauthorizedException({ code: 'INVALID_REFRESH_TOKEN', message: 'Refresh token is invalid or expired' });
        }
        return this.repository.transaction(async (transaction) => {
            const session = await this.repository.findSessionForUpdate(payload.sid, transaction);
            if (!session || session.revokedAt || session.expiresAt <= new Date()) {
                throw new UnauthorizedException({ code: 'INVALID_REFRESH_SESSION', message: 'Refresh session is no longer valid' });
            }
            if (session.rotatedAt) {
                await this.repository.revokeFamily(session.familyId, transaction);
                throw new UnauthorizedException({ code: 'REFRESH_TOKEN_REUSED', message: 'Refresh token reuse was detected; sign in again' });
            }
            if (!(await verify(session.tokenHash, rawToken)) || session.tokenVersion !== payload.tokenVersion) {
                await this.repository.revokeFamily(session.familyId, transaction);
                throw new UnauthorizedException({ code: 'INVALID_REFRESH_TOKEN', message: 'Refresh token is invalid' });
            }
            const account = await this.repository.findActiveAccountById(session.userId);
            if (!account || account.tokenVersion !== payload.tokenVersion) {
                await this.repository.revokeFamily(session.familyId, transaction);
                throw new UnauthorizedException({ code: 'SESSION_REVOKED', message: 'Session has been revoked' });
            }
            await this.repository.markSessionRotated(session.id, transaction);
            return this.issueTokenPair(account, request, session.familyId, transaction);
        });
    }
    async logout(rawToken) {
        if (!rawToken)
            return;
        try {
            const payload = await this.jwt.verifyAsync(rawToken, {
                secret: this.config.get('JWT_REFRESH_SECRET', { infer: true }),
                ignoreExpiration: true,
            });
            await this.repository.revokeSession(payload.sid);
        }
        catch {
        }
    }
    invalidRecoveryToken() {
        return new BadRequestException({
            code: 'INVALID_RECOVERY_TOKEN',
            message: 'The password recovery link is invalid or expired',
        });
    }
    async issueTokenPair(account, request, familyId = randomUUID(), transaction) {
        const sessionId = randomUUID();
        const refreshTtl = this.config.get('JWT_REFRESH_TTL_SECONDS', { infer: true });
        const accessTtl = this.config.get('JWT_ACCESS_TTL_SECONDS', { infer: true });
        const accessPayload = {
            sub: account.id,
            email: account.email,
            role: account.role,
            tokenVersion: account.tokenVersion,
            type: 'access',
        };
        const refreshPayload = {
            sub: account.id,
            sid: sessionId,
            familyId,
            jti: randomUUID(),
            tokenVersion: account.tokenVersion,
            type: 'refresh',
        };
        const [accessToken, refreshToken] = await Promise.all([
            this.jwt.signAsync(accessPayload, {
                secret: this.config.get('JWT_ACCESS_SECRET', { infer: true }),
                expiresIn: accessTtl,
            }),
            this.jwt.signAsync(refreshPayload, {
                secret: this.config.get('JWT_REFRESH_SECRET', { infer: true }),
                expiresIn: refreshTtl,
            }),
        ]);
        await this.repository.createSession({
            id: sessionId,
            userId: account.id,
            familyId,
            tokenHash: await hash(refreshToken, { type: 2 }),
            expiresAt: new Date(Date.now() + refreshTtl * 1000),
            userAgent: request.headers['user-agent'],
            ipAddress: request.ip,
        }, transaction);
        return { accessToken, refreshToken, expiresIn: accessTtl };
    }
};
AuthService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [AuthRepository,
        JwtService,
        ConfigService,
        OAuthIdentityVerifier,
        AuthActionTokenCipher])
], AuthService);
export { AuthService };
//# sourceMappingURL=auth.service.js.map