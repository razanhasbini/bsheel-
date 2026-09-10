import type { ConfigService } from '@nestjs/config';
import { ServiceUnavailableException } from '@nestjs/common';
import { describe, expect, it, vi, beforeEach, afterEach } from 'vitest';
import { CamaraNumberVerificationAdapter } from '../src/integrations/camara/number-verification.adapter.js';
import type { CamaraClientFactory } from '../src/integrations/camara/camara-client.factory.js';
import type { CamaraOAuthMetadataService } from '../src/integrations/camara/camara-oauth-metadata.service.js';
import type { Environment } from '../src/config/environment.js';

/**
 * These tests are about ONE property: the three answers Number Verification
 * can give must stay distinguishable. "the network says no" and "we never
 * reached the network" both mean the user does not get verified, but only
 * the first is evidence about the number — collapsing them would either
 * lock out users during an outage or, worse, let an outage look like a pass.
 *
 * Nokia itself is not mocked anywhere in the integration path; what is
 * stubbed here is only the SDK boundary, so the mapping logic can be
 * exercised without a live entitlement.
 */
type VerifyCall = { phoneNumber?: string; code?: string; state?: string; authorization?: string };

function build(
  verifyImpl: (request: VerifyCall) => Promise<{ devicePhoneNumberVerified?: boolean }>,
  opts: { fastFlowCspAuthEndpoint?: string } = {},
) {
  const config = {
    get: vi.fn((key: keyof Environment) =>
      key === 'CAMARA_REQUEST_TIMEOUT_MS' ? 10_000 : 'set'),
  } as unknown as ConfigService<Environment, true>;

  const metadata = {
    endpointsOrNull: vi.fn().mockResolvedValue({
      authorizationEndpoint: 'https://operator.example/authorize',
      tokenEndpoint: 'https://operator.example/token',
      fastFlowCspAuthEndpoint: opts.fastFlowCspAuthEndpoint,
    }),
    clientCredentialsOrNull: vi.fn().mockResolvedValue({
      clientId: 'client-id',
      clientSecret: 'client-secret',
    }),
  } as unknown as CamaraOAuthMetadataService;

  const clients = {
    isConfigured: () => true,
    clientOrNull: () => ({ numberVerification: { verify: verifyImpl } }),
  } as unknown as CamaraClientFactory;

  return new CamaraNumberVerificationAdapter(config, metadata, clients);
}

const input = {
  code: 'auth-code',
  state: 'the-state',
  nonce: 'the-nonce',
  redirectUri: 'https://api.bsheel.app/api/v1/auth/phone/callback',
  flow: 'standard' as const,
  claimedPhoneNumber: '+99999991000',
};

describe('CamaraNumberVerificationAdapter (Number Verification V1)', () => {
  beforeEach(() => {
    // The token exchange is plain fetch, not the SDK.
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ access_token: 'user-access-token' }),
    }));
  });

  afterEach(() => vi.unstubAllGlobals());

  it('maps devicePhoneNumberVerified=true to VERIFIED with the claimed number', async () => {
    const adapter = build(async () => ({ devicePhoneNumberVerified: true }));
    await expect(adapter.verifyClaimedNumber(input)).resolves.toEqual({
      status: 'VERIFIED',
      phoneNumber: '+99999991000',
    });
  });

  it('maps devicePhoneNumberVerified=false to NOT_VERIFIED, never to an error', async () => {
    const adapter = build(async () => ({ devicePhoneNumberVerified: false }));
    await expect(adapter.verifyClaimedNumber({ ...input, claimedPhoneNumber: '+99999991001' })).resolves.toEqual({
      status: 'NOT_VERIFIED',
    });
  });

  it('accepts the working standard token response when Nokia omits id_token', async () => {
    const adapter = build(async () => ({ devicePhoneNumberVerified: true }));
    await expect(adapter.verifyClaimedNumber(input)).resolves.toEqual({
      status: 'VERIFIED',
      phoneNumber: '+99999991000',
    });
  });

  it('maps a provider outage to UNAVAILABLE, not to NOT_VERIFIED', async () => {
    const adapter = build(async () => {
      throw Object.assign(new Error('boom'), { statusCode: 503 });
    });
    const outcome = await adapter.verifyClaimedNumber(input);
    expect(outcome.status).toBe('UNAVAILABLE');
  });

  it('treats an unreadable response as UNAVAILABLE rather than a negative answer', async () => {
    const adapter = build(async () => ({}));
    const outcome = await adapter.verifyClaimedNumber(input);
    expect(outcome.status).toBe('UNAVAILABLE');
  });

  it('never leaks a provider body or headers into the reason string', async () => {
    const adapter = build(async () => {
      throw Object.assign(new Error('boom'), {
        statusCode: 403,
        body: { message: 'You are not subscribed to this API.' },
        headers: { 'x-rapidapi-key': 'super-secret-key' },
      });
    });
    const outcome = await adapter.verifyClaimedNumber(input);
    expect(outcome.status).toBe('UNAVAILABLE');
    const reason = outcome.status === 'UNAVAILABLE' ? outcome.reason : '';
    expect(reason).not.toContain('super-secret-key');
    expect(reason).not.toContain('subscribed');
    expect(reason).toContain('403');
  });

  // ── 3-legged OAuth mechanics ───────────────────────────────────────────
  // Sending phoneNumber alone would be a call that proves nothing. These
  // pin the parts CAMARA V1 actually requires.

  it('builds an authorization URL with the CAMARA-required parameters', async () => {
    const adapter = build(async () => ({ devicePhoneNumberVerified: true }));
    const { url, flow } = await adapter.buildAuthorizationUrl({
      state: 'the-state',
      nonce: 'the-nonce',
      redirectUri: 'https://api.bsheel.app/api/v1/auth/phone/callback',
      loginHint: '+99999991000',
    });
    const params = new URL(url).searchParams;
    // prompt=none is what makes this network-based rather than interactive.
    expect(params.get('prompt')).toBe('none');
    expect(params.get('scope')).toBe('dpv:FraudPreventionAndDetection number-verification:verify');
    expect(params.get('response_type')).toBe('code');
    expect(params.get('client_id')).toBe('client-id');
    expect(params.get('login_hint')).toBe('+99999991000');
    expect(params.get('state')).toBe('the-state');
    expect(params.get('nonce')).toBe('the-nonce');
    // No fast endpoint advertised → standard flow, standard base.
    expect(flow).toBe('standard');
    expect(url.startsWith('https://operator.example/authorize')).toBe(true);
  });

  it('stays on the standard flow even when Nokia advertises a fast-flow endpoint', async () => {
    // Measured, not assumed: on this account retrieve_csp_auth_url rejects
    // the documented parameter set (400) and carrying a real code through
    // to verify(code, state) returns 404. Advertising the endpoint is not
    // the same as it being usable, so discovering it must NOT flip us onto
    // a flow that does not work.
    const adapter = build(async () => ({ devicePhoneNumberVerified: true }), {
      fastFlowCspAuthEndpoint: 'https://operator.example/fast-auth',
    });
    const { url, flow } = await adapter.buildAuthorizationUrl({
      state: 's', nonce: 'n', redirectUri: 'https://api.bsheel.app/cb', loginHint: '+99999991000',
    });
    expect(flow).toBe('standard');
    expect(url.startsWith('https://operator.example/authorize')).toBe(true);
    expect(new URL(url).searchParams.get('prompt')).toBe('none');
  });

  it('standard flow sends a Bearer token and does NOT send code/state', async () => {
    let seen: VerifyCall | undefined;
    const adapter = build(async (request) => {
      seen = request;
      return { devicePhoneNumberVerified: true };
    });
    await adapter.verifyClaimedNumber(input);
    expect(seen?.authorization).toBe('Bearer user-access-token');
    expect(seen?.phoneNumber).toBe('+99999991000');
    expect(seen?.code).toBeUndefined();
    expect(seen?.state).toBeUndefined();
  });

  it('fast flow sends code + state and does NOT exchange a token itself', async () => {
    let seen: VerifyCall | undefined;
    const adapter = build(async (request) => {
      seen = request;
      return { devicePhoneNumberVerified: true };
    });
    await adapter.verifyClaimedNumber({ ...input, flow: 'fast' });
    expect(seen?.code).toBe('auth-code');
    expect(seen?.state).toBe('the-state');
    expect(seen?.phoneNumber).toBe('+99999991000');
    expect(seen?.authorization).toBeUndefined();
    // Nokia redeems the code, so we must not have hit the token endpoint.
    expect(fetch).not.toHaveBeenCalled();
  });

  it('standard flow rejects an id_token whose nonce is not the one we issued', async () => {
    const forged = `x.${Buffer.from(JSON.stringify({ nonce: 'someone-elses' })).toString('base64url')}.y`;
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ access_token: 'user-access-token', id_token: forged }),
    }));
    const adapter = build(async () => ({ devicePhoneNumberVerified: true }));
    await expect(adapter.verifyClaimedNumber(input)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });

  it('standard flow accepts an id_token carrying the matching nonce', async () => {
    const good = `x.${Buffer.from(JSON.stringify({ nonce: 'the-nonce' })).toString('base64url')}.y`;
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ access_token: 'user-access-token', id_token: good }),
    }));
    const adapter = build(async () => ({ devicePhoneNumberVerified: true }));
    await expect(adapter.verifyClaimedNumber(input)).resolves.toEqual({
      status: 'VERIFIED',
      phoneNumber: '+99999991000',
    });
  });

  it('fails closed when Nokia will not hand over OAuth metadata', async () => {
    const config = { get: vi.fn(() => 10_000) } as unknown as ConfigService<Environment, true>;
    const metadata = {
      endpointsOrNull: vi.fn().mockResolvedValue(null),
      clientCredentialsOrNull: vi.fn().mockResolvedValue(null),
    } as unknown as CamaraOAuthMetadataService;
    const clients = {
      isConfigured: () => true,
      clientOrNull: () => ({ numberVerification: { verify: vi.fn() } }),
    } as unknown as CamaraClientFactory;

    const adapter = new CamaraNumberVerificationAdapter(config, metadata, clients);
    await expect(adapter.verifyClaimedNumber(input)).rejects.toBeInstanceOf(
      ServiceUnavailableException,
    );
  });
});
