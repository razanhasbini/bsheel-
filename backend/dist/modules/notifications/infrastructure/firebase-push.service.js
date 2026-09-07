var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { createPrivateKey, sign } from 'node:crypto';
import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
let FirebasePushService = class FirebasePushService {
    config;
    enabled;
    account;
    projectId;
    timeoutMs;
    accessToken;
    accessTokenExpiresAt = 0;
    accessTokenRequest;
    constructor(config) {
        this.config = config;
        this.enabled = config.get('PUSH_NOTIFICATIONS_ENABLED', { infer: true });
        this.timeoutMs = config.get('FIREBASE_TIMEOUT_MS', { infer: true });
        const rawAccount = config.get('FIREBASE_SERVICE_ACCOUNT', { infer: true });
        if (rawAccount)
            this.account = this.parseAccount(rawAccount);
        this.projectId = config.get('FIREBASE_PROJECT_ID', { infer: true }) || this.account?.project_id || 'bitsheel';
    }
    async send(token, title, body) {
        if (!this.enabled)
            throw new Error('Push notifications are disabled');
        return this.sendWithAuthentication(token, title, body, true);
    }
    async sendWithAuthentication(token, title, body, retryAuthentication) {
        const response = await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(this.projectId)}/messages:send`, {
            method: 'POST',
            headers: {
                'content-type': 'application/json',
                authorization: `Bearer ${await this.getAccessToken()}`,
            },
            body: JSON.stringify({
                message: {
                    token,
                    apns: {
                        headers: { 'apns-priority': '10' },
                        payload: { aps: { alert: { title, body }, sound: 'quest_notification.caf' } },
                    },
                    android: { notification: { title, body, sound: 'quest_notification' } },
                    data: { type: 'notification', title, body },
                },
            }),
            signal: AbortSignal.timeout(this.timeoutMs),
        });
        const payload = await this.readJson(response);
        if (response.ok) {
            return {
                invalidToken: false,
                messageName: typeof payload.name === 'string' ? payload.name : undefined,
            };
        }
        if (response.status === 401 && retryAuthentication) {
            this.accessToken = undefined;
            this.accessTokenExpiresAt = 0;
            return this.sendWithAuthentication(token, title, body, false);
        }
        if (this.isInvalidToken(response.status, payload))
            return { invalidToken: true };
        throw new Error(`FCM request failed with status ${response.status}`);
    }
    async getAccessToken() {
        const now = Math.floor(Date.now() / 1000);
        if (this.accessToken && now < this.accessTokenExpiresAt - 300)
            return this.accessToken;
        this.accessTokenRequest ??= this.requestAccessToken(now).finally(() => {
            this.accessTokenRequest = undefined;
        });
        return this.accessTokenRequest;
    }
    async requestAccessToken(now) {
        if (!this.account)
            throw new Error('Firebase service account is not configured');
        const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
        const claims = Buffer.from(JSON.stringify({
            iss: this.account.client_email,
            scope: 'https://www.googleapis.com/auth/firebase.messaging',
            aud: this.account.token_uri ?? 'https://oauth2.googleapis.com/token',
            iat: now,
            exp: now + 3600,
        })).toString('base64url');
        const unsigned = `${header}.${claims}`;
        const assertion = `${unsigned}.${sign('RSA-SHA256', Buffer.from(unsigned), createPrivateKey(this.account.private_key)).toString('base64url')}`;
        const tokenUri = this.account.token_uri ?? 'https://oauth2.googleapis.com/token';
        const response = await fetch(tokenUri, {
            method: 'POST',
            headers: { 'content-type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
                assertion,
            }),
            signal: AbortSignal.timeout(this.timeoutMs),
        });
        const payload = await this.readJson(response);
        if (!response.ok || typeof payload.access_token !== 'string') {
            throw new Error(`Firebase OAuth request failed with status ${response.status}`);
        }
        this.accessToken = payload.access_token;
        this.accessTokenExpiresAt = now + (typeof payload.expires_in === 'number' ? payload.expires_in : 3600);
        return this.accessToken;
    }
    parseAccount(raw) {
        let candidate;
        try {
            candidate = JSON.parse(raw);
        }
        catch {
            throw new Error('FIREBASE_SERVICE_ACCOUNT must be valid JSON');
        }
        if (typeof candidate !== 'object' || candidate === null ||
            !('client_email' in candidate) || typeof candidate.client_email !== 'string' ||
            !('private_key' in candidate) || typeof candidate.private_key !== 'string') {
            throw new Error('FIREBASE_SERVICE_ACCOUNT is missing client_email or private_key');
        }
        return candidate;
    }
    async readJson(response) {
        try {
            const value = await response.json();
            return typeof value === 'object' && value !== null ? value : {};
        }
        catch {
            return {};
        }
    }
    isInvalidToken(status, payload) {
        if (status === 404)
            return true;
        const serialized = JSON.stringify(payload);
        return serialized.includes('UNREGISTERED') || serialized.includes('registration-token-not-registered');
    }
};
FirebasePushService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService])
], FirebasePushService);
export { FirebasePushService };
//# sourceMappingURL=firebase-push.service.js.map