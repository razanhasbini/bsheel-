var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
let TransactionalEmailService = class TransactionalEmailService {
    endpoint;
    secret;
    publicUrl;
    timeoutMs;
    constructor(config) {
        this.endpoint = config.get('EMAIL_DELIVERY_WEBHOOK_URL', { infer: true });
        this.secret = config.get('EMAIL_DELIVERY_WEBHOOK_SECRET', { infer: true });
        this.publicUrl = config.get('APP_PUBLIC_URL', { infer: true });
        this.timeoutMs = config.get('EMAIL_TIMEOUT_MS', { infer: true });
    }
    async sendPasswordRecovery(email, token) {
        await this.sendActionEmail('password_recovery', email, '/reset-password', token);
    }
    async sendEmailConfirmation(email, token) {
        await this.sendActionEmail('email_confirmation', email, '/confirm-email', token);
    }
    async sendActionEmail(template, email, path, token) {
        if (!this.endpoint || !this.secret) {
            throw new ServiceUnavailableException({
                code: 'EMAIL_DELIVERY_UNAVAILABLE',
                message: 'Transactional email delivery is not configured',
            });
        }
        const actionUrl = new URL(path, this.publicUrl);
        actionUrl.searchParams.set('token', token);
        const response = await fetch(this.endpoint, {
            method: 'POST',
            headers: {
                'content-type': 'application/json',
                authorization: `Bearer ${this.secret}`,
            },
            body: JSON.stringify({
                template,
                to: email,
                variables: template === 'password_recovery'
                    ? { resetUrl: actionUrl.toString() }
                    : { confirmationUrl: actionUrl.toString() },
            }),
            signal: AbortSignal.timeout(this.timeoutMs),
        });
        if (!response.ok)
            throw new Error(`Email delivery failed with status ${response.status}`);
    }
};
TransactionalEmailService = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [ConfigService])
], TransactionalEmailService);
export { TransactionalEmailService };
//# sourceMappingURL=transactional-email.service.js.map