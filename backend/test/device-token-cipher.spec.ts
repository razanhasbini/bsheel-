import { ConfigService } from '@nestjs/config';
import { describe, expect, it } from 'vitest';
import type { Environment } from '../src/config/environment.js';
import { DeviceTokenCipher } from '../src/modules/notifications/infrastructure/device-token-cipher.js';

describe('DeviceTokenCipher', () => {
  const config = new ConfigService<Environment, true>({
    DEVICE_TOKEN_ENCRYPTION_KEY: 'test-device-token-encryption-key-32-characters',
  } as Environment);

  it('round-trips a device token without storing plaintext', () => {
    const cipher = new DeviceTokenCipher(config);
    const token = 'fcm-registration-token-that-must-stay-secret';
    const protectedToken = cipher.protect(token);

    expect(protectedToken.encrypted.toString('utf8')).not.toContain(token);
    expect(cipher.unprotect(protectedToken.encrypted)).toBe(token);
  });

  it('rejects tampered ciphertext', () => {
    const cipher = new DeviceTokenCipher(config);
    const protectedToken = cipher.protect('token');
    protectedToken.encrypted[protectedToken.encrypted.length - 1] ^= 1;

    expect(() => cipher.unprotect(protectedToken.encrypted)).toThrow();
  });
});
