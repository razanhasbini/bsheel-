import { createHash } from 'node:crypto';
import { Injectable, ServiceUnavailableException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { OAuth2Client } from 'google-auth-library';
import { createRemoteJWKSet, jwtVerify } from 'jose';
import type { Environment } from '../../../config/environment.js';

export interface OAuthIdentity {
  readonly provider: 'google' | 'apple';
  readonly subject: string;
  readonly email: string;
  readonly displayName?: string;
}

@Injectable()
export class OAuthIdentityVerifier {
  private readonly google: OAuth2Client;
  private readonly googleAudiences: readonly string[];
  private readonly appleAudiences: readonly string[];
  private readonly appleKeys;

  constructor(config: ConfigService<Environment, true>) {
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

  async verify(
    provider: 'google' | 'apple',
    idToken: string,
    nonce?: string,
    displayName?: string,
  ): Promise<OAuthIdentity> {
    return provider === 'google'
      ? this.verifyGoogle(idToken, displayName)
      : this.verifyApple(idToken, nonce, displayName);
  }

  private async verifyGoogle(idToken: string, displayName?: string): Promise<OAuthIdentity> {
    if (!this.googleAudiences.length) this.notConfigured('Google');
    try {
      const ticket = await this.google.verifyIdToken({
        idToken,
        audience: [...this.googleAudiences],
      });
      const payload = ticket.getPayload();
      if (!payload?.sub || !payload.email || payload.email_verified !== true) this.invalid();
      return {
        provider: 'google',
        subject: payload.sub,
        email: payload.email.trim().toLowerCase(),
        displayName: cleanName(displayName) ?? cleanName(payload.name),
      };
    } catch (error) {
      if (error instanceof ServiceUnavailableException || error instanceof UnauthorizedException) throw error;
      this.invalid();
    }
  }

  private async verifyApple(idToken: string, nonce?: string, displayName?: string): Promise<OAuthIdentity> {
    if (!this.appleAudiences.length) this.notConfigured('Apple');
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
      if (
        !subject || typeof email !== 'string' ||
        !(emailVerified === true || emailVerified === 'true') ||
        !expectedNonce || verified.payload.nonce !== expectedNonce
      ) this.invalid();
      return {
        provider: 'apple',
        subject,
        email: email.trim().toLowerCase(),
        displayName: cleanName(displayName),
      };
    } catch (error) {
      if (error instanceof ServiceUnavailableException || error instanceof UnauthorizedException) throw error;
      this.invalid();
    }
  }

  private invalid(): never {
    throw new UnauthorizedException({ code: 'INVALID_ID_TOKEN', message: 'The identity token is invalid or expired' });
  }

  private notConfigured(provider: string): never {
    throw new ServiceUnavailableException({
      code: 'OAUTH_PROVIDER_UNAVAILABLE',
      message: `${provider} sign-in is not configured`,
    });
  }
}

function splitValues(raw: string): readonly string[] {
  return raw.split(',').map((value) => value.trim()).filter(Boolean);
}

function cleanName(raw?: string): string | undefined {
  const value = raw?.trim();
  return value ? value.slice(0, 50) : undefined;
}
