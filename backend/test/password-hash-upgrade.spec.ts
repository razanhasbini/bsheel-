import bcrypt from 'bcryptjs';
import { hash, verify } from 'argon2';
import { describe, expect, it } from 'vitest';

/**
 * The quest-app import brought 180 accounts hashed with bcrypt into a service
 * that hashes with argon2. argon2's verify returns false for a bcrypt hash
 * rather than throwing, so those users were refused with the correct password
 * and nothing in the logs said why.
 *
 * These lock in the two properties the fallback depends on: that argon2 fails
 * closed on a foreign hash, and that the prefix test recognises every bcrypt
 * variant in the wild.
 */
describe('legacy password hash compatibility', () => {
  const bcryptPrefix = /^\$2[abxy]?\$/;

  it('argon2 rejects a bcrypt hash instead of throwing', async () => {
    const legacy = bcrypt.hashSync('correct-horse-battery', 10);
    // If this ever throws, login turns a wrong-scheme hash into a 500 and the
    // fallback below never runs.
    await expect(verify(legacy, 'correct-horse-battery')).resolves.toBe(false);
  });

  it('recognises every bcrypt variant that appears in real data', () => {
    // $2a$ and $2b$ are what the import actually contained; $2x$ and $2y$ are
    // the other revisions in circulation.
    for (const prefix of ['$2a$', '$2b$', '$2x$', '$2y$', '$2$']) {
      expect(bcryptPrefix.test(`${prefix}10$abcdefghijklmnopqrstuv`)).toBe(true);
    }
  });

  it('does not mistake an argon2 hash for bcrypt', async () => {
    const current = await hash('correct-horse-battery', { type: 2 });
    expect(current.startsWith('$argon2')).toBe(true);
    expect(bcryptPrefix.test(current)).toBe(false);
  });

  it('verifies a real imported hash, and only with the right password', async () => {
    // Cost 6 and 10 are the two the imported rows use.
    for (const cost of [6, 10]) {
      const legacy = bcrypt.hashSync('correct-horse-battery', cost);
      expect(legacy.startsWith('$2')).toBe(true);
      await expect(bcrypt.compare('correct-horse-battery', legacy)).resolves.toBe(true);
      await expect(bcrypt.compare('wrong-password', legacy)).resolves.toBe(false);
    }
  });

  it('the upgraded hash verifies under argon2 and no longer looks like bcrypt', async () => {
    const password = 'correct-horse-battery';
    const legacy = bcrypt.hashSync(password, 10);
    expect(await bcrypt.compare(password, legacy)).toBe(true);

    // What the login path stores after a successful bcrypt verification.
    const upgraded = await hash(password, { type: 2 });

    expect(bcryptPrefix.test(upgraded)).toBe(false);
    await expect(verify(upgraded, password)).resolves.toBe(true);
    await expect(verify(upgraded, 'wrong-password')).resolves.toBe(false);
  });
});
