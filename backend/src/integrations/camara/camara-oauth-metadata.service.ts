import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NetworkAsCodeApiClient } from 'network-as-code';
import type { Environment } from '../../config/environment.js';
import { CamaraClientFactory } from './camara-client.factory.js';

export interface CamaraOAuthEndpoints {
  readonly authorizationEndpoint: string;
  readonly tokenEndpoint: string;
  readonly fastFlowCspAuthEndpoint?: string;
}

export interface CamaraOAuthClientCredentials {
  readonly clientId: string;
  readonly clientSecret: string;
}

interface Cached<T> {
  readonly value: T;
  readonly fetchedAt: number;
}

/** Both are stable per application; re-fetched hourly rather than per request. */
const CACHE_TTL_MS = 60 * 60 * 1000;

/**
 * Everything Nokia exposes programmatically, fetched through the official
 * SDK rather than copied out of the dashboard by hand:
 *
 *  - wellKnownMetadata.getOauthAuthorizationServer() → the authorization
 *    and token endpoints for Number Verification's 3-legged flow.
 *  - oauth.getClientCredentials() → the client_id/client_secret for this
 *    application ("if it exists that is returned, otherwise new created",
 *    per the SDK).
 *
 * Env vars of the same name still win when set, so a deployment can pin
 * values Nokia's account configuration requires be provided by hand — but
 * nothing has to be pinned for the normal path to work.
 *
 * Neither the secret nor the API key is ever logged.
 */
@Injectable()
export class CamaraOAuthMetadataService {
  private readonly logger = new Logger(CamaraOAuthMetadataService.name);
  private client?: NetworkAsCodeApiClient;
  private endpoints?: Cached<CamaraOAuthEndpoints>;
  private credentials?: Cached<CamaraOAuthClientCredentials>;

  constructor(
    private readonly config: ConfigService<Environment, true>,
    private readonly clients: CamaraClientFactory,
  ) {}

  /**
   * Discovered from Nokia unless explicitly overridden in config. Returns
   * null when neither is available, so callers fail closed rather than
   * guessing an endpoint.
   */
  async endpointsOrNull(): Promise<CamaraOAuthEndpoints | null> {
    const overrideAuthorize = this.config.get('CAMARA_NUMBER_VERIFICATION_AUTHORIZE_URL', { infer: true });
    const overrideToken = this.config.get('CAMARA_NUMBER_VERIFICATION_TOKEN_URL', { infer: true });
    if (overrideAuthorize && overrideToken) {
      return { authorizationEndpoint: overrideAuthorize, tokenEndpoint: overrideToken };
    }

    if (this.endpoints && Date.now() - this.endpoints.fetchedAt < CACHE_TTL_MS) {
      return this.endpoints.value;
    }
    const client = this.clientOrNull();
    if (!client) return null;

    try {
      const metadata = await client.wellKnownMetadata.getOauthAuthorizationServer();
      if (!metadata.authorization_endpoint || !metadata.token_endpoint) return null;
      const value: CamaraOAuthEndpoints = {
        authorizationEndpoint: metadata.authorization_endpoint,
        tokenEndpoint: metadata.token_endpoint,
        fastFlowCspAuthEndpoint: metadata.fast_flow_csp_auth_endpoint,
      };
      this.endpoints = { value, fetchedAt: Date.now() };
      this.logger.log('Discovered CAMARA OAuth endpoints from Nokia well-known metadata');
      return value;
    } catch (error) {
      this.logger.warn(
        { statusCode: this.statusCodeOf(error) },
        'Could not discover CAMARA OAuth endpoints; phone sign-in stays unavailable',
      );
      return null;
    }
  }

  /**
   * Discovered from Nokia unless explicitly overridden in config. Never
   * logged, never returned to the client — only used server-side for the
   * authorization-code exchange.
   */
  async clientCredentialsOrNull(): Promise<CamaraOAuthClientCredentials | null> {
    const overrideId = this.config.get('CAMARA_NUMBER_VERIFICATION_CLIENT_ID', { infer: true });
    const overrideSecret = this.config.get('CAMARA_NUMBER_VERIFICATION_CLIENT_SECRET', { infer: true });
    if (overrideId) {
      return { clientId: overrideId, clientSecret: overrideSecret ?? '' };
    }

    if (this.credentials && Date.now() - this.credentials.fetchedAt < CACHE_TTL_MS) {
      return this.credentials.value;
    }
    const client = this.clientOrNull();
    if (!client) return null;

    try {
      const issued = await client.oauth.getClientCredentials();
      if (!issued.client_id || !issued.client_secret) return null;
      const value: CamaraOAuthClientCredentials = {
        clientId: issued.client_id,
        clientSecret: issued.client_secret,
      };
      this.credentials = { value, fetchedAt: Date.now() };
      this.logger.log('Obtained CAMARA OAuth client credentials from Nokia');
      return value;
    } catch (error) {
      this.logger.warn(
        { statusCode: this.statusCodeOf(error) },
        'Could not obtain CAMARA OAuth client credentials; phone sign-in stays unavailable',
      );
      return null;
    }
  }

  private clientOrNull(): NetworkAsCodeApiClient | null {
    return this.clients.clientOrNull();
  }

  private statusCodeOf(error: unknown): number | undefined {
    return typeof error === 'object' && error !== null && 'statusCode' in error
      ? (error as { statusCode?: number }).statusCode
      : undefined;
  }
}
