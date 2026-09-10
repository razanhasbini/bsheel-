import { Injectable, Logger, ServiceUnavailableException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../config/environment.js';
import { CamaraClientFactory } from './camara-client.factory.js';
import { CamaraOAuthMetadataService } from './camara-oauth-metadata.service.js';

/**
 * CAMARA's two Number Verification V1 flows. Both start with the same
 * authorization request; they differ only in how the final verify call
 * proves the user consented.
 *
 * `fast`     — verify receives `code` + `state` as query parameters and
 *              Network as Code redeems the authorization code internally.
 *              Requires Nokia to advertise fast_flow_csp_auth_endpoint,
 *              which is also the authorization base for this flow.
 * `standard` — we redeem the code at token_endpoint ourselves, validate the
 *              nonce in the returned id_token, and send the resulting
 *              access token as `Authorization: Bearer …` on verify.
 */
export type NumberVerificationFlow = 'fast' | 'standard';

export interface AuthorizationUrlInput {
  readonly state: string;
  readonly nonce: string;
  readonly redirectUri: string;
  /** The number the user claims to control. V1 verifies the device against it. */
  readonly loginHint: string;
}

export interface AuthorizationUrl {
  readonly url: string;
  /** Must be replayed to verifyClaimedNumber — the flows are not interchangeable. */
  readonly flow: NumberVerificationFlow;
}

export interface CodeExchangeInput {
  readonly code: string;
  /** Echoed back by the operator; fast flow forwards it to Nokia verbatim. */
  readonly state: string;
  /** Checked against the id_token's nonce claim on the standard flow. */
  readonly nonce: string | null;
  readonly redirectUri: string;
  readonly flow: NumberVerificationFlow;
  /** The claim recorded when the flow started — never taken from the callback. */
  readonly claimedPhoneNumber: string;
}

/**
 * The three things Number Verification can tell us, kept distinct.
 *
 * `NOT_VERIFIED` is a real, trustworthy answer from the network: this device
 * is not using that number. `UNAVAILABLE` means we never got an answer. They
 * must never collapse into one "failed" branch — the first is grounds to
 * refuse the number, the second is grounds to retry.
 */
export type NumberVerificationOutcome =
  | { readonly status: 'VERIFIED'; readonly phoneNumber: string }
  | { readonly status: 'NOT_VERIFIED' }
  | { readonly status: 'UNAVAILABLE'; readonly reason: string };

/**
 * CAMARA Number Verification **V1.0.0** (issue #1) — a 3-legged flow,
 * structurally different from the mandatory-evidence adapter in
 * camara-evidence.adapter.ts: the app-level RapidAPI key alone cannot answer
 * "whose phone number is this," only a per-user access token obtained by
 * redirecting the user's own device through the operator's authorization
 * endpoint (over cellular data, so the operator can correlate the connection
 * to a real subscriber) can. This adapter owns exactly that redirect + code
 * exchange + the final SDK call with the resulting bearer token.
 *
 * V1, not V2.1, deliberately. In the installed SDK (network-as-code@10.0.0)
 * they are different methods on the same client:
 *
 *   V1  client.numberVerification.verify(…)
 *       → POST passthrough/camara/v1/number-verification/number-verification/v0/verify
 *       → { devicePhoneNumberVerified: boolean }
 *   V2  client.numberVerification.verifyV2 / .getDevicePhoneNumberV2
 *       → .../v2/verify, .../v2/device-phone-number
 *
 * V1's shape is what Bsheel's flow wants: the user types a number, and the
 * network answers true/false about that specific claim. (V2's
 * device-phone-number instead hands back whatever number the SIM has, which
 * is a different product decision, not a drop-in newer version.)
 *
 * `verify` is NOT a one-shot call on a phone number. It is the last step of
 * a 3-legged OAuth flow and it only means anything when it carries proof
 * that the user consented — `code` + `state` on the fast flow, or an
 * `Authorization: Bearer` token on the standard flow. Calling it with
 * `{ phoneNumber }` alone would send an unauthenticated question and is
 * never correct; see NumberVerificationFlow above.
 *
 * Full sequence:
 *   1. oauth.getClientCredentials()               → client_id / client_secret
 *   2. wellKnownMetadata.getOauthAuthorizationServer()
 *                                                 → authorization / token /
 *                                                   fast_flow_csp_auth endpoints
 *   3. buildAuthorizationUrl(…)                   → client_id, redirect_uri,
 *                                                   login_hint, state, nonce,
 *                                                   scope, prompt=none
 *   4. user's device opens that URL over cellular data
 *   5. operator redirects back with code + state
 *   6. caller validates state (single-use row in phone_signin_states)
 *   7. verifyClaimedNumber(…)                     → fast or standard flow
 *
 * The authorization/token endpoints and the client_id/client_secret are NOT
 * configured by hand: they come from Nokia at call time via
 * CamaraOAuthMetadataService (well-known metadata + oauth.getClientCredentials).
 * Anything undiscoverable fails closed with PHONE_SIGNIN_NOT_CONFIGURED
 * rather than guessing an endpoint.
 */
@Injectable()
export class CamaraNumberVerificationAdapter {
  private readonly logger = new Logger(CamaraNumberVerificationAdapter.name);

  constructor(
    private readonly config: ConfigService<Environment, true>,
    private readonly metadata: CamaraOAuthMetadataService,
    private readonly clients: CamaraClientFactory,
  ) {}

  isConfigured(): boolean {
    // Endpoints and client credentials are discovered from Nokia at call
    // time, so the only local configuration is the application API key.
    return this.clients.isConfigured();
  }

  async buildAuthorizationUrl(input: AuthorizationUrlInput): Promise<AuthorizationUrl> {
    const [endpoints, credentials] = await Promise.all([
      this.metadata.endpointsOrNull(),
      this.metadata.clientCredentialsOrNull(),
    ]);
    if (!endpoints || !credentials) this.notConfigured();

    // Standard flow, and this is settled by measurement rather than
    // preference. Verified end to end against Nokia's simulator on
    // 2026-09-10: +99999991000 → devicePhoneNumberVerified true,
    // +99999991001 → false.
    //
    // The account does advertise fast_flow_csp_auth_endpoint
    // (https://auth.eu.nac.nokia.io/oauth2/v1/retrieve_csp_auth_url) and
    // Nokia's docs say to use it "as the base URL when building the
    // authorization link" — but it does not behave like one. Probed the
    // same day it answers 422 "client_id parameter is missing" when bare,
    // then 400 Bad Request once the full documented parameter set is
    // supplied; and carrying a real authorization code through to
    // verify(code, state) returns 404 Not Found. Its name suggests a call
    // that RETURNS an auth URL rather than a redirect target.
    //
    // So fast flow is not usable on this account today. The code path stays
    // in verifyClaimedNumber() because it is correct per spec and costs
    // nothing to keep; it is simply never selected until Nokia's endpoint
    // is understood.
    const flow: NumberVerificationFlow = 'standard';
    const url = new URL(endpoints.authorizationEndpoint);
    url.searchParams.set('response_type', 'code');
    url.searchParams.set('client_id', credentials.clientId);
    url.searchParams.set('redirect_uri', input.redirectUri);
    // The scope CAMARA defines for V1. `dpv:FraudPreventionAndDetection` is
    // the Data Privacy Vocabulary purpose the operator records consent
    // against; without it the operator can reject the request outright.
    url.searchParams.set('scope', 'dpv:FraudPreventionAndDetection number-verification:verify');
    url.searchParams.set('state', input.state);
    // OpenID nonce, bound to the same one-time state row the callback
    // validates. On the standard flow it is additionally checked against
    // the id_token's nonce claim after the token exchange.
    url.searchParams.set('nonce', input.nonce);
    // Required. Network-based authentication means the operator identifies
    // the SIM from the data connection itself — `none` tells it not to show
    // an interactive login, which is the whole point of the mechanism.
    // Omitting it turns a silent check into a prompt, or an error.
    url.searchParams.set('prompt', 'none');
    // The number the user claims, so the operator knows what is being asked.
    url.searchParams.set('login_hint', input.loginHint);
    return { url: url.toString(), flow };
  }

  /**
   * Exchanges the authorization code for a user token, then asks the network
   * whether the claimed number really belongs to this device.
   *
   * Returns an outcome rather than throwing on a negative answer: "the
   * network says no" is a successful call with a false result, and the
   * caller has to tell it apart from "we could not reach the network."
   */
  async verifyClaimedNumber(input: CodeExchangeInput): Promise<NumberVerificationOutcome> {
    const client = this.clients.clientOrNull();
    const [endpoints, credentials] = await Promise.all([
      this.metadata.endpointsOrNull(),
      this.metadata.clientCredentialsOrNull(),
    ]);
    if (!client || !endpoints || !credentials) this.notConfigured();

    const timeoutMs = this.config.get('CAMARA_REQUEST_TIMEOUT_MS', { infer: true });
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      // Either way the app-level RapidAPI key (held inside the client)
      // identifies the caller; what differs is how the END USER's consent
      // is proven. Sending phoneNumber alone would prove nothing and is
      // never correct for V1.
      const request =
        input.flow === 'fast'
          ? {
              // Nokia redeems the code itself. `code` and `state` travel as
              // query parameters (the SDK lifts them out of the request
              // object); phoneNumber stays in the body.
              phoneNumber: input.claimedPhoneNumber,
              code: input.code,
              state: input.state,
            }
          : {
              // We redeemed the code ourselves above; the resulting
              // single-use access token goes on the Authorization header.
              phoneNumber: input.claimedPhoneNumber,
              authorization: `Bearer ${await this.exchangeToken(
                endpoints.tokenEndpoint,
                credentials.clientId,
                credentials.clientSecret,
                input,
                controller.signal,
              )}`,
            };

      const result = await client.numberVerification.verify(request, {
        abortSignal: controller.signal,
      });

      if (result.devicePhoneNumberVerified === true) {
        return { status: 'VERIFIED', phoneNumber: input.claimedPhoneNumber };
      }
      if (result.devicePhoneNumberVerified === false) {
        return { status: 'NOT_VERIFIED' };
      }
      // A response we cannot read is not a "no" — treat it as no answer.
      return { status: 'UNAVAILABLE', reason: 'Provider returned no verification result' };
    } catch (error) {
      if (error instanceof ServiceUnavailableException) throw error;
      // Sanitised: status and a coarse category only, never headers or body,
      // because both can echo the API key back.
      const reason = describeProviderStatus(error);
      this.logger.warn({ reason }, 'Number Verification V1 call failed');
      return { status: 'UNAVAILABLE', reason };
    } finally {
      clearTimeout(timeout);
    }
  }

  private async exchangeToken(
    tokenUrl: string,
    clientId: string,
    clientSecret: string | undefined,
    input: CodeExchangeInput,
    signal: AbortSignal,
  ): Promise<string> {
    const expectedNonce = input.nonce;
    const body = new URLSearchParams({
      grant_type: 'authorization_code',
      code: input.code,
      redirect_uri: input.redirectUri,
      client_id: clientId,
    });
    const headers: Record<string, string> = { 'content-type': 'application/x-www-form-urlencoded' };
    if (clientSecret) {
      headers.authorization = `Basic ${Buffer.from(`${clientId}:${clientSecret}`).toString('base64')}`;
    }
    const response = await fetch(tokenUrl, { method: 'POST', headers, body, signal });
    if (!response.ok) {
      this.logger.warn({ status: response.status }, 'Number Verification token exchange failed');
      this.unavailable('Could not complete phone verification');
    }
    const payload = (await response.json()) as { access_token?: string; id_token?: string };
    if (!payload.access_token) this.unavailable('Token exchange returned no access_token');

    // Standard flow requires checking that the id_token was minted for THIS
    // authorization request. The nonce is the binding: we generated it, put
    // it on the authorization URL, and stored it on the single-use state
    // row, so a token issued for some other request cannot carry it.
    //
    // We compare the claim rather than verify the JWT signature, and that is
    // a deliberate, bounded decision: this token came back over a direct
    // TLS call that we initiated to Nokia's discovered token_endpoint,
    // authenticated with our client credentials — not through the browser.
    // There is no untrusted party in that exchange to forge it. Signature
    // verification would matter if we ever accepted an id_token from the
    // redirect itself; we never do.
    if (expectedNonce) {
      const actual = readJwtNonce(payload.id_token);
      if (actual !== null && actual !== expectedNonce) {
        this.logger.warn('id_token nonce did not match the authorization request');
        this.unavailable('Could not complete phone verification');
      }
    }
    return payload.access_token;
  }

  private notConfigured(): never {
    throw new ServiceUnavailableException({
      code: 'PHONE_SIGNIN_NOT_CONFIGURED',
      message: 'Phone sign-in is not configured yet',
    });
  }

  private unavailable(reason: string): never {
    this.logger.warn(reason);
    throw new ServiceUnavailableException({
      code: 'NUMBER_VERIFICATION_UNAVAILABLE',
      message: 'Could not complete phone verification. Please try again.',
    });
  }
}

/**
 * Reads the `nonce` claim out of an id_token without verifying it.
 *
 * Returns null when there is no id_token or it cannot be parsed — the
 * caller treats that as "nothing to compare" rather than a failure, because
 * CAMARA does not guarantee an id_token on every token response and a
 * missing one is not evidence of an attack.
 */
function readJwtNonce(idToken: string | undefined): string | null {
  if (!idToken) return null;
  const segments = idToken.split('.');
  if (segments.length < 2) return null;
  try {
    const claims = JSON.parse(Buffer.from(segments[1], 'base64url').toString('utf8')) as {
      nonce?: unknown;
    };
    return typeof claims.nonce === 'string' ? claims.nonce : null;
  } catch {
    return null;
  }
}

/**
 * Reduces a provider error to a short, non-sensitive descriptor.
 *
 * Deliberately excludes the response body: RapidAPI and CAMARA error
 * payloads can echo back the request headers we sent, which include the API
 * key. Status code plus a coarse category is all the operational detail we
 * need, and all we can safely keep.
 */
function describeProviderStatus(error: unknown): string {
  const candidate = error as { statusCode?: number; status?: number } | null;
  const status = candidate?.statusCode ?? candidate?.status;
  if (typeof status !== 'number') return 'network error or timeout';
  if (status === 401 || status === 403) return `provider rejected the request (HTTP ${status})`;
  if (status === 404) return 'provider route not found (HTTP 404)';
  if (status >= 500) return `provider error (HTTP ${status})`;
  return `provider returned HTTP ${status}`;
}
