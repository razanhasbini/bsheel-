import { describe, expect, it } from 'vitest';
import { validateEnvironment } from '../src/config/environment.js';

describe('validateEnvironment', () => {
  it('provides safe local defaults', () => {
    const environment = validateEnvironment({ NODE_ENV: 'test' });
    expect(environment.PORT).toBe(3000);
    expect(environment.DATABASE_POOL_MAX).toBe(10);
    expect(environment.DATABASE_WORKER_POOL_MAX).toBe(12);
    expect(environment.DATABASE_CONNECTION_TIMEOUT_MS).toBe(5000);
    expect(environment.OUTBOX_POLL_MS).toBe(250);
    expect(environment.SWAGGER_ENABLED).toBe(true);
    expect(environment.PUSH_NOTIFICATIONS_ENABLED).toBe(false);
    expect(environment.AUTH_EMAIL_CONFIRMATION_REQUIRED).toBe(true);
  });

  it('enables submission verification when the variable is absent', () => {
    // Fail-safe rather than fail-silent. Verifying that a device was where a
    // quest required is the product, so a deployment that simply forgot the
    // variable must get the verification, not quietly skip it. Disabling is
    // a deliberate act and has to be spelled out.
    expect(
      validateEnvironment({ NODE_ENV: 'test' }).AGENT_SUBMISSION_VERIFICATION_ENABLED,
    ).toBe(true);
  });

  it('disables submission verification only on an explicit false', () => {
    expect(
      validateEnvironment({
        NODE_ENV: 'test',
        AGENT_SUBMISSION_VERIFICATION_ENABLED: 'false',
      }).AGENT_SUBMISSION_VERIFICATION_ENABLED,
    ).toBe(false);
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
  it('reads an empty optional variable as absent, not as an invalid value', () => {
    // `.env.example` ships these empty and dotenv/compose surface '' rather
    // than undefined, so the documented `cp .env.example .env` must validate.
    const environment = validateEnvironment({
      NODE_ENV: 'test',
      EMAIL_DELIVERY_WEBHOOK_URL: '',
      EMAIL_DELIVERY_WEBHOOK_SECRET: '',
      FIREBASE_SERVICE_ACCOUNT: '',
      TELEGRAM_BOT_TOKEN: '',
      TELEGRAM_ADMIN_CHAT_ID: '',
      TELEGRAM_WEBHOOK_SECRET: '',
      R2_ENDPOINT: '',
      R2_PUBLIC_BASE_URL: '',
      R2_ACCESS_KEY_ID: '',
      R2_SECRET_ACCESS_KEY: '',
      R2_BUCKET: '',
    });
    expect(environment.EMAIL_DELIVERY_WEBHOOK_URL).toBeUndefined();
    expect(environment.R2_ENDPOINT).toBeUndefined();
    expect(environment.FIREBASE_SERVICE_ACCOUNT).toBeUndefined();
    expect(environment.TELEGRAM_BOT_TOKEN).toBeUndefined();
  });

  it('still rejects a malformed optional URL', () => {
    expect(() =>
      validateEnvironment({ NODE_ENV: 'test', R2_ENDPOINT: 'not-a-url' }),
    ).toThrow(/R2_ENDPOINT/);
  });

  it('still requires the email secret when a delivery URL is configured', () => {
    expect(() =>
      validateEnvironment({
        NODE_ENV: 'test',
        EMAIL_DELIVERY_WEBHOOK_URL: 'https://mail.example.test/send',
        EMAIL_DELIVERY_WEBHOOK_SECRET: '',
      }),
    ).toThrow(/EMAIL_DELIVERY_WEBHOOK_SECRET/);
  });

  it('requires the CAMARA phone-verification config in production', () => {
    // Phone verification has no off switch, so a production deployment
    // without these would send every user to an unpassable verify-phone
    // wall. Fail at boot instead.
    expect(() => validateEnvironment({ NODE_ENV: 'production' })).toThrow(
      /CAMARA_API_KEY/,
    );
  });

  it('does not require CAMARA config to boot a dev or test machine', () => {
    // The gate is still enforced in the app; only the credentials that
    // make it *pass* are absent, and nobody should need a Nokia account to
    // run the suite.
    expect(() => validateEnvironment({ NODE_ENV: 'test' })).not.toThrow();
    expect(() => validateEnvironment({ NODE_ENV: 'development' })).not.toThrow();
  });

  it('still requires Telegram credentials when the integration is enabled', () => {
    expect(() =>
      validateEnvironment({
        NODE_ENV: 'test',
        TELEGRAM_ENABLED: 'true',
        TELEGRAM_BOT_TOKEN: '',
      }),
    ).toThrow(/TELEGRAM_BOT_TOKEN/);
  });
});
