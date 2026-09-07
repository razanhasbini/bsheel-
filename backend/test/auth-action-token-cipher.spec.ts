import { ConfigService } from '@nestjs/config';
import { describe, expect, it } from 'vitest';
import type { Environment } from '../src/config/environment.js';
import { AuthActionTokenCipher } from '../src/modules/auth/infrastructure/auth-action-token-cipher.js';

describe('AuthActionTokenCipher', () => {
  const config = new ConfigService<Environment, true>({
    AUTH_ACTION_TOKEN_ENCRYPTION_KEY: 'test-auth-action-encryption-key-32-characters',
  } as Environment);

  it('round-trips a token while keeping the stored bytes opaque', () => {
    const cipher = new AuthActionTokenCipher(config);
    const token = 'one-time-password-recovery-token';
    const protectedToken = cipher.protect(token);

    expect(protectedToken.encrypted.toString('utf8')).not.toContain(token);
    expect(protectedToken.hash).toEqual(cipher.hash(token));
    expect(cipher.unprotect(protectedToken.encrypted)).toBe(token);
  });

  it('rejects modified authenticated ciphertext', () => {
    const cipher = new AuthActionTokenCipher(config);
    const protectedToken = cipher.protect('token');
    protectedToken.encrypted[protectedToken.encrypted.length - 1] ^= 1;

    expect(() => cipher.unprotect(protectedToken.encrypted)).toThrow();
  });
});
