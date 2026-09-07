var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { createHash } from 'node:crypto';
import { Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';
import { createRemoteJWKSet, jwtVerify } from 'jose';
let OAuthIdentityVerifier = class OAuthIdentityVerifier {
    google;
    googleAudiences;
    appleAudiences;
    appleKeys;
    constructor(config) {
        this.google = new OAuth2Client({
            transporterOptions: { timeout: config.get('OAUTH_TIMEOUT_MS', { infer: true }) },
        });
        this.googleAudiences = splitValues(config.get('OAUTH_GOOGLE_CLIENT_IDS', { infer: true }));
        this.appleAudiences = splitValues(config.get('OAUTH_APPLE_CLIENT_IDS', { infer: true }));
        this.appleKeys = createRemoteJWKSet(new URL('https://appleid.apple.com/auth/keys'), {
            timeoutDuration: config.get('OAUTH_TIMEOUT_MS', { infer: true }),
            cooldownDuration: 30_000,
            cacheMaxAge: 3_600_000,
        });
    }
    async verify(provider, idToken, nonce, displayName) {
        return provider === 'google'
            ? this.verifyGoogle(idToken, displayName)
            : this.verifyApple(idToken, nonce, displayName);
    }
    async verifyGoogle(idToken, displayName) {
        if (!this.googleAudiences.length)
            this.notConfigured('Google');
        try {
            const ticket = await this.google.verifyIdToken({
                idToken,
                audience: [...this.googleAudiences],
            });
            const payload = ticket.getPayload();
            if (!payload?.sub || !payload.email || payload.email_verified !== true)
                this.invalid();
            return {
                provider: 'google',
                subject: payload.sub,
                email: payload.email.trim().toLowerCase(),
                displayName: cleanName(displayName) ?? cleanName(payload.name),
            };
        }
        catch (error) {
            if (error instanceof ServiceUnavailableException || error instanceof UnauthorizedException)
                throw error;
            this.invalid();
        }
    }
    async verifyApple(idToken, nonce, displayName) {
        if (!this.appleAudiences.length)
            this.notConfigured('Apple');
        try {
            const verified = await jwtVerify(idToken, this.appleKeys, {
                algorithms: ['RS256'],
                issuer: 'https://appleid.apple.com',
                audience: [...this.appleAudiences],
            });
            const subject = verified.payload.sub;
            const email = verified.payload.email;
            const emailVerified = verified.payload.email_verified;
            const expectedNonce = nonce ? createHash('sha256').update(nonce, 'utf8').digest('hex') : undefined;
            if (!subject || typeof email !== 'string' ||
                !(emailVerified === true || emailVerified === 'true') ||
                !expectedNonce || verified.payload.nonce !== expectedNonce)
                this.invalid();
            return {
                provider: 'apple',
                subject,
                email: email.trim().toLowerCase(),
                displayName: cleanName(displayName),
            };
        }
        catch (error) {
            if (error instanceof ServiceUnavailableException || error instanceof UnauthorizedException)
                throw error;
            this.invalid();
        }
    }
    invalid() {
        throw new UnauthorizedException({ code: 'INVALID_ID_TOKEN', message: 'The identity token is invalid or expired' });
    }
    notConfigured(provider) {
        throw new ServiceUnavailableException({
            code: 'OAUTH_PROVIDER_UNAVAILABLE',
            message: `${provider} sign-in is not configured`,
        });
    }
};
OAuthIdentityVerifier = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService])
], OAuthIdentityVerifier);
export { OAuthIdentityVerifier };
function splitValues(raw) {
    return raw.split(',').map((value) => value.trim()).filter(Boolean);
}
function cleanName(raw) {
    const value = raw?.trim();
    return value ? value.slice(0, 50) : undefined;
}
//# sourceMappingURL=oauth-identity-verifier.js.map