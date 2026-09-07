import { describe, expect, it } from 'vitest';
import { validateEnvironment } from '../src/config/environment.js';

describe('validateEnvironment', () => {
  it('provides safe local defaults', () => {
    const environment = validateEnvironment({ NODE_ENV: 'test' });
    expect(environment.PORT).toBe(3000);
    expect(environment.DATABASE_POOL_MAX).toBe(20);
    expect(environment.SWAGGER_ENABLED).toBe(true);
    expect(environment.PUSH_NOTIFICATIONS_ENABLED).toBe(false);
    expect(environment.AUTH_EMAIL_CONFIRMATION_REQUIRED).toBe(true);
  });

  it('rejects an inverted connection-pool range', () => {
    expect(() =>
      validateEnvironment({ DATABASE_POOL_MIN: '21', DATABASE_POOL_MAX: '20' }),
    ).toThrow(/DATABASE_POOL_MIN/);
  });

  it('rejects development secrets in production', () => {
    expect(() => validateEnvironment({ NODE_ENV: 'production' })).toThrow(
      /JWT_ACCESS_SECRET/,
    );
  });

  it('requires Firebase credentials when push delivery is enabled', () => {
    expect(() => validateEnvironment({
      NODE_ENV: 'test',
      PUSH_NOTIFICATIONS_ENABLED: 'true',
    })).toThrow(/FIREBASE_SERVICE_ACCOUNT/);
  });
});
