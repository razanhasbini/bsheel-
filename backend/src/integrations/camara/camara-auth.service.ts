import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { describeCamaraError } from './camara-error.js';

interface CachedToken {
  readonly value: string;
  readonly expiresAt: number;
}

/**
 * Two supported auth modes for Nokia Network-as-Code / CAMARA, both
 * provider-spec-independent — the three capability calls in
 * camara-evidence.adapter.ts are not implemented yet because they need the
 * actual Nokia API version and OpenAPI spec, which this repository does not
 * have (see docs/design/MAP_REQUIREMENTS.md, which notes the same gap for
 * the map's pre-assignment CAMARA gate).
 *
 * - CAMARA_API_KEY: a static bearer key, used as-is. Matches Nokia's own
 *   sandbox/developer-portal onboarding, which issues a single key rather
 *   than a client/secret pair.
 * - CAMARA_TOKEN_URL + CAMARA_CLIENT_ID + CAMARA_CLIENT_SECRET: standard
 *   OAuth2 client-credentials, for a production-grade CAMARA deployment.
 *
 * If both are set, the static key wins (it needs no network round trip).
 */
@Injectable()
export class CamaraAuthService {
  private readonly logger = new Logger(CamaraAuthService.name);
  private cached?: CachedToken;

  constructor(private readonly config: ConfigService<Environment, true>) {}

  private hasStaticKey(): boolean {
    return Boolean(this.config.get('CAMARA_API_KEY', { infer: true }));
  }

  private hasOAuthCredentials(): boolean {
    return Boolean(
      this.config.get('CAMARA_TOKEN_URL', { infer: true }) &&
        this.config.get('CAMARA_CLIENT_ID', { infer: true }) &&
        this.config.get('CAMARA_CLIENT_SECRET', { infer: true }),
    );
  }

  isConfigured(): boolean {
    return Boolean(this.config.get('CAMARA_ENABLED', { infer: true })) && (this.hasStaticKey() || this.hasOAuthCredentials());
  }

  async getAccessToken(): Promise<string> {
    if (!this.isConfigured()) {
      throw new Error('CAMARA is not configured (CAMARA_ENABLED plus either CAMARA_API_KEY or a full client-credentials set)');
    }
    if (this.hasStaticKey()) {
      return this.config.get('CAMARA_API_KEY', { infer: true })!;
    }

    const now = Date.now();
    if (this.cached && this.cached.expiresAt > now + 5_000) return this.cached.value;

    const tokenUrl = this.config.get('CAMARA_TOKEN_URL', { infer: true })!;
    const clientId = this.config.get('CAMARA_CLIENT_ID', { infer: true })!;
    const clientSecret = this.config.get('CAMARA_CLIENT_SECRET', { infer: true })!;
    const scope = this.config.get('CAMARA_SCOPE', { infer: true });
    const timeoutMs = this.config.get('CAMARA_REQUEST_TIMEOUT_MS', { infer: true });

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const body = new URLSearchParams({ grant_type: 'client_credentials', ...(scope ? { scope } : {}) });
      const response = await fetch(tokenUrl, {
        method: 'POST',
        headers: {
          'content-type': 'application/x-www-form-urlencoded',
          authorization: `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString('base64')}`,
        },
        body,
        signal: controller.signal,
      });
      if (!response.ok) throw new Error(`CAMARA token endpoint responded ${response.status}`);
      const payload = (await response.json()) as { access_token?: string; expires_in?: number };
      if (!payload.access_token) throw new Error('CAMARA token response had no access_token');
      this.cached = { value: payload.access_token, expiresAt: now + (payload.expires_in ?? 300) * 1000 };
      return this.cached.value;
    } catch (error) {
      this.logger.warn({ providerError: describeCamaraError(error) }, 'CAMARA token fetch failed');
      throw error;
    } finally {
      clearTimeout(timeout);
    }
  }
}
