import type { ConfigService } from '@nestjs/config';
import { describe, expect, it, vi } from 'vitest';
import type { Environment } from '../src/config/environment.js';
import { AuthService } from '../src/modules/auth/application/auth.service.js';

function build(options: {
  outcome?: { status: 'VERIFIED'; phoneNumber: string } | { status: 'NOT_VERIFIED' } | { status: 'UNAVAILABLE'; reason: string };
  pending?: Record<string, unknown> | null;
} = {}) {
  const account = {
    id: '00000000-0000-4000-8000-000000000010', email: null, passwordHash: null,
    emailVerified: false, phoneVerified: true, status: 'active', tokenVersion: 0, role: 'user',
  };
  const repository = {
    findOrCreateByPhone: vi.fn().mockResolvedValue(account),
    linkPhoneIdentity: vi.fn().mockResolvedValue(account),
    findActiveAccountById: vi.fn().mockResolvedValue(account),
    touchLastLogin: vi.fn(),
  };
  const pending = options.pending === undefined ? {
    id: '00000000-0000-4000-8000-000000000011', intent: 'sign_in', userId: null,
    ageVerified: true, redirectUri: 'https://api.bsheel.app/api/v1/auth/phone/callback',
    nonce: 'nonce', claimedPhoneNumber: '+99999991000', oauthFlow: 'standard',
    claimedEmail: 'optional@example.test',
  } : options.pending;
  const phoneStates = {
    consumePending: vi.fn().mockResolvedValue(pending),
    markCompleted: vi.fn(),
    consumeHandoff: vi.fn().mockResolvedValue(null),
  };
  const numberVerification = {
    verifyClaimedNumber: vi.fn().mockResolvedValue(options.outcome ?? { status: 'VERIFIED', phoneNumber: '+99999991000' }),
  };
  const config = {
    get: vi.fn((key: keyof Environment) => key === 'PHONE_SIGNIN_MOBILE_REDIRECT_URL'
      ? 'https://admin.bsheel.app/phone-signin-callback'
      : undefined),
  } as unknown as ConfigService<Environment, true>;
  const service = new AuthService(
    repository as never,
    {} as never,
    config,
    {} as never,
    {} as never,
    numberVerification as never,
    phoneStates as never,
  );
  return { service, repository, phoneStates, numberVerification };
}

describe('phone authentication orchestration', () => {
  it('creates the +99999991000 account only after V1 returns true and carries optional email', async () => {
    const { service, repository, phoneStates } = build();
    const result = await service.completePhoneCallback('code', 'state');
    expect(repository.findOrCreateByPhone).toHaveBeenCalledWith(
      '+99999991000', true, 'optional@example.test',
    );
    expect(phoneStates.markCompleted).toHaveBeenCalledOnce();
    expect(result.redirectUrl).toContain('handoff=');
    expect(result.redirectUrl).not.toContain('accessToken');
  });

  it('does not create an account when +99999991001 returns false', async () => {
    const { service, repository } = build({
      outcome: { status: 'NOT_VERIFIED' },
      pending: {
        id: '00000000-0000-4000-8000-000000000011', intent: 'sign_in', userId: null,
        ageVerified: true, redirectUri: 'https://api.bsheel.app/api/v1/auth/phone/callback',
        nonce: 'nonce', claimedPhoneNumber: '+99999991001', oauthFlow: 'standard', claimedEmail: null,
      },
    });
    // A refusal redirects rather than throwing: this handler is the page
    // the user's browser lands on, so a thrown error would render raw JSON
    // at a URL they are looking at. What matters is that no account exists
    // and no session is issued — the redirect only carries a reason code.
    const refused = await service.completePhoneCallback('code', 'state');
    expect(refused.redirectUrl).toContain('error=PHONE_NUMBER_NOT_VERIFIED');
    expect(refused.redirectUrl).not.toContain('handoff=');
    // The unverified number must never be echoed back in a URL.
    expect(refused.redirectUrl).not.toContain('99999991001');
    expect(repository.findOrCreateByPhone).not.toHaveBeenCalled();
  });

  it('does not create an account when the provider is unavailable', async () => {
    const { service, repository } = build({ outcome: { status: 'UNAVAILABLE', reason: 'HTTP 503' } });
    // Distinct from a refusal, so the app can say "try again" rather than
    // "check the number".
    const unavailable = await service.completePhoneCallback('code', 'state');
    expect(unavailable.redirectUrl).toContain('error=NUMBER_VERIFICATION_UNAVAILABLE');
    expect(unavailable.redirectUrl).not.toContain('handoff=');
    expect(repository.findOrCreateByPhone).not.toHaveBeenCalled();
  });

  it('accepts absent optional email and forwards null', async () => {
    const { service, repository } = build({
      pending: {
        id: '00000000-0000-4000-8000-000000000011', intent: 'sign_in', userId: null,
        ageVerified: true, redirectUri: 'https://api.bsheel.app/api/v1/auth/phone/callback',
        nonce: 'nonce', claimedPhoneNumber: '+99999991000', oauthFlow: 'standard', claimedEmail: null,
      },
    });
    await service.completePhoneCallback('code', 'state');
    expect(repository.findOrCreateByPhone).toHaveBeenCalledWith('+99999991000', true, null);
  });

  it('rejects expired or replayed state before contacting Nokia', async () => {
    const { service, numberVerification } = build({ pending: null });
    // Redirects rather than throws, for the same reason every other failure
    // does: this handler is a landing page, and a thrown error renders raw
    // JSON at a URL somebody is looking at. What must stay true is that
    // Nokia is never contacted and no session is issued.
    const result = await service.completePhoneCallback('code', 'replayed');
    expect(result.redirectUrl).toContain('error=INVALID_PHONE_SIGNIN_STATE');
    expect(result.redirectUrl).not.toContain('handoff=');
    expect(numberVerification.verifyClaimedNumber).not.toHaveBeenCalled();
  });
});
