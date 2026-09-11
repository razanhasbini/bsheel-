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
      '+99999991000', true, 'optional@example.test', undefined,
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
    expect(repository.findOrCreateByPhone).toHaveBeenCalledWith('+99999991000', true, null, undefined);
  });

  it('applies the password chosen at signup once the carrier confirms the number', async () => {
    // The password is typed before the browser leaves for the operator and
    // the account does not exist until it comes back, so the hash has to
    // survive the round trip in the sign-in state. Only the hash — never the
    // plaintext — and it only reaches the repository on the verified path.
    const { service, repository } = build({
      pending: {
        id: '00000000-0000-4000-8000-000000000011', intent: 'sign_in', userId: null,
        ageVerified: true, redirectUri: 'https://api.bsheel.app/api/v1/auth/phone/callback',
        nonce: 'nonce', claimedPhoneNumber: '+99999991000', oauthFlow: 'standard',
        claimedEmail: null, passwordHash: '$argon2id$fake',
      },
    });
    await service.completePhoneCallback('code', 'state');
    expect(repository.findOrCreateByPhone).toHaveBeenCalledWith(
      '+99999991000', true, null, '$argon2id$fake',
    );
  });

  it('never reaches the account when the number is refused, password and all', async () => {
    const { service, repository } = build({
      outcome: { status: 'NOT_VERIFIED' },
      pending: {
        id: '00000000-0000-4000-8000-000000000011', intent: 'sign_in', userId: null,
        ageVerified: true, redirectUri: 'https://api.bsheel.app/api/v1/auth/phone/callback',
        nonce: 'nonce', claimedPhoneNumber: '+99999991001', oauthFlow: 'standard',
        claimedEmail: null, passwordHash: '$argon2id$fake',
      },
    });
    await service.completePhoneCallback('code', 'state');
    expect(repository.findOrCreateByPhone).not.toHaveBeenCalled();
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

/**
 * The gate that decides whether a number may be used as a credential.
 *
 * CAMARA Number Verification is the ONLY thing in this app that may conclude
 * a number belongs to its claimant: `completePhoneCallback` writes
 * `phone_verified_at` and it writes Nokia's answer, never the user's claim.
 * Everything downstream trusts that column, so these pin what happens when
 * it is absent — including for a row somebody wrote by hand, which is how a
 * Lebanese number ended up in a local database marked verified when Nokia's
 * simulator will only ever verify +99999991000.
 */
const CORRECT_HASH =
  '$argon2id$v=19$m=65536,t=3,p=4$HB9fnB0mQAbR93mpNw62vA$uKLv5FJyjszzQcSFDvLEg7HjXKE7eDkqQ/2jd2o21A8';

describe('phone sign-in refuses a number CAMARA never verified', () => {
  function loginWith(account: Partial<{ phoneVerified: boolean; passwordHash: string | null }>) {
    const repository = {
      findAccountByPhone: vi.fn().mockResolvedValue({
        id: '00000000-0000-4000-8000-000000000020',
        email: null,
        // A REAL argon2 hash of 'RealPassword99'. It has to be real: with a
        // malformed one argon2 throws and the test passes without the gate
        // ever being consulted, which is a test that proves nothing.
        passwordHash: account.passwordHash === undefined ? CORRECT_HASH : account.passwordHash,
        emailVerified: false,
        phoneVerified: account.phoneVerified ?? false,
        status: 'active',
        tokenVersion: 0,
        role: 'user',
      }),
      findAccountByEmail: vi.fn(),
      touchLastLogin: vi.fn(),
      replacePasswordHash: vi.fn(),
    };
    const service = new AuthService(
      repository as never, {} as never, {} as never,
      {} as never, {} as never, {} as never, {} as never,
    );
    return { service, repository };
  }

  it('refuses a password sign-in when the number was never verified', async () => {
    const { service } = loginWith({ phoneVerified: false, passwordHash: null });
    // passwordHash null makes this INVALID_CREDENTIALS, which is the right
    // answer for an account that cannot be signed into at all — and the
    // point is that it is never a session.
    await expect(
      service.login({ phoneNumber: '+96170555001', password: 'CheckPoint4Me' }, {} as never),
    ).rejects.toThrow();
  });

  it('refuses even with the CORRECT password when phone_verified_at is absent', async () => {
    // The case that matters most, and the one that caught a fabricated row:
    // the password is right, so this fails on the carrier verification
    // alone. Asserting the specific code is what proves the gate ran rather
    // than something incidental throwing first.
    const { service } = loginWith({ phoneVerified: false });
    let thrown: { getResponse?: () => { code?: string } } | undefined;
    try {
      await service.login({ phoneNumber: '+96170555001', password: 'RealPassword99' }, {} as never);
    } catch (error) {
      thrown = error as typeof thrown;
    }
    expect(thrown, 'an unverified number must never sign in').toBeDefined();
    expect(thrown!.getResponse!().code).toBe('PHONE_NOT_VERIFIED');
  });

  it('lets the SAME password through once CAMARA has verified the number', async () => {
    // The other half, without which the test above would also pass if login
    // were simply broken: identical credentials, one column different.
    const { service, repository } = loginWith({ phoneVerified: true });
    await service.login({ phoneNumber: '+99999991000', password: 'RealPassword99' }, {} as never)
      .catch(() => undefined);
    // Reaching touchLastLogin means both the password and the gate passed;
    // only token issuance (unstubbed JWT) is left.
    expect(repository.touchLastLogin).toHaveBeenCalledOnce();
  });

  it('never reads the email path when a phone number was supplied', async () => {
    // Which identifier was used decides which verification gate applies, so
    // a phone sign-in must not be able to fall through to the email lookup
    // and inherit the email gate instead.
    const { service, repository } = loginWith({ phoneVerified: false });
    await service.login({ phoneNumber: '+96170555001', password: 'x' }, {} as never)
      .catch(() => undefined);
    expect(repository.findAccountByPhone).toHaveBeenCalledOnce();
    expect(repository.findAccountByEmail).not.toHaveBeenCalled();
  });
});
