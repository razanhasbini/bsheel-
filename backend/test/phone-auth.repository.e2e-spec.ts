import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { AuthRepository } from '../src/modules/auth/infrastructure/auth.repository.js';
import { PhoneSigninStateRepository } from '../src/modules/auth/infrastructure/phone-signin-state.repository.js';
import { E2eHarness } from './support/e2e-harness.js';

describe('phone account persistence (e2e)', () => {
  let harness: E2eHarness;
  let auth: AuthRepository;
  let states: PhoneSigninStateRepository;
  const suffix = String(Date.now()).slice(-9);
  const phones = [`+9991${suffix}`, `+9992${suffix}`, `+9993${suffix}`];
  const statePrefix = `phone-e2e-${suffix}`;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    auth = harness.app.get(AuthRepository);
    states = harness.app.get(PhoneSigninStateRepository);
  }, 60_000);

  afterAll(async () => {
    if (harness) {
      await harness.database.query('DELETE FROM phone_signin_states WHERE state LIKE $1', [`${statePrefix}%`]);
      const created = await harness.database.query<{ id: string }>(
        'SELECT id FROM users WHERE phone_number = ANY($1::citext[])',
        [phones],
      );
      for (const row of created.rows) {
        await harness.database.query(
          `DELETE FROM outbox_events WHERE aggregate_id = $1::uuid OR payload->>'userId' = $2::text`,
          [row.id, row.id],
        );
      }
      await harness.database.query('DELETE FROM users WHERE phone_number = ANY($1::citext[])', [phones]);
      await harness.close();
    }
  });

  it('creates a phone-only account when optional email is absent', async () => {
    const account = await auth.findOrCreateByPhone(phones[0], true, null);
    expect(account.email).toBeNull();
    expect(account.phoneVerified).toBe(true);
  });

  it('attaches an available optional email only after verified account creation', async () => {
    const email = `phone-available-${suffix}@example.test`;
    const account = await auth.findOrCreateByPhone(phones[1], true, email);
    expect(account.email).toBe(email);
  });

  it('keeps a valid phone signup successful when another account owns the optional email', async () => {
    const owner = await harness.createUser({ prefix: 'phoneemail' });
    const account = await auth.findOrCreateByPhone(phones[2], true, owner.email);
    expect(account.phoneVerified).toBe(true);
    expect(account.email).toBeNull();
  });

  it('consumes state once and rejects replay or expiration', async () => {
    await states.start({
      state: `${statePrefix}-live`, intent: 'sign_in', redirectUri: 'https://api.bsheel.app/callback',
      nonce: 'nonce', claimedPhoneNumber: phones[0], oauthFlow: 'standard', ttlMs: 60_000,
    });
    expect(await states.consumePending(`${statePrefix}-live`)).not.toBeNull();
    expect(await states.consumePending(`${statePrefix}-live`)).toBeNull();

    await states.start({
      state: `${statePrefix}-expired`, intent: 'sign_in', redirectUri: 'https://api.bsheel.app/callback',
      nonce: 'nonce', claimedPhoneNumber: phones[0], oauthFlow: 'standard', ttlMs: -1_000,
    });
    expect(await states.consumePending(`${statePrefix}-expired`)).toBeNull();
  });
});
