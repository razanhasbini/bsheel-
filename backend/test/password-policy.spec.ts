import { describe, expect, it } from 'vitest';
import { assertPasswordPolicy } from '../src/modules/auth/domain/password-policy.js';

describe('assertPasswordPolicy', () => {
  it('accepts the canonical ten-character composition policy', () => {
    expect(() => assertPasswordPolicy('Strong-Z9!', 'player', 'player@example.com')).not.toThrow();
  });

  it.each([
    ['Short9A', 'too short'],
    ['alllowercase9', 'missing uppercase'],
    ['ALLUPPERCASE9', 'missing lowercase'],
    ['NoDigitsHere!', 'missing digit'],
    ['Qwerty-Canyon-9A', 'banned substring'],
    ['Player-Canyon-9A', 'username reuse'],
    ['Mailbox-Canyon-9A', 'email reuse'],
  ])('rejects %s (%s)', (password) => {
    expect(() => assertPasswordPolicy(password, 'player', 'mailbox@example.com')).toThrow();
  });
});
