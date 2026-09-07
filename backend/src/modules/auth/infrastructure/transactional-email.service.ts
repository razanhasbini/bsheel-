import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';

@Injectable()
export class TransactionalEmailService {
  private readonly endpoint?: string;
  private readonly secret?: string;
  private readonly publicUrl: string;
  private readonly timeoutMs: number;

  constructor(config: ConfigService<Environment, true>) {
    this.endpoint = config.get('EMAIL_DELIVERY_WEBHOOK_URL', { infer: true });
    this.secret = config.get('EMAIL_DELIVERY_WEBHOOK_SECRET', { infer: true });
    this.publicUrl = config.get('APP_PUBLIC_URL', { infer: true });
    this.timeoutMs = config.get('EMAIL_TIMEOUT_MS', { infer: true });
  }

  async sendPasswordRecovery(email: string, token: string): Promise<void> {
    await this.sendActionEmail('password_recovery', email, '/reset-password', token);
  }

  async sendEmailConfirmation(email: string, token: string): Promise<void> {
    await this.sendActionEmail('email_confirmation', email, '/confirm-email', token);
  }

  private async sendActionEmail(
    template: 'password_recovery' | 'email_confirmation',
    email: string,
    path: string,
    token: string,
  ): Promise<void> {
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
    if (!response.ok) throw new Error(`Email delivery failed with status ${response.status}`);
  }
}
