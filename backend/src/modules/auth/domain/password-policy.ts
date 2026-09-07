import { BadRequestException } from '@nestjs/common';

const bannedSubstrings = ['bsheel', 'bitsheel', 'password', 'qwerty', '123456', 'letmein'];

export function assertPasswordPolicy(password: string, username?: string, email?: string): void {
  if (password.length < 10) fail('Password must be at least 10 characters');
  if (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) {
    fail('Password must mix uppercase, lowercase, and a digit');
  }
  const normalized = password.toLowerCase();
  const emailLocal = email?.split('@')[0];
  for (const identity of [username, emailLocal]) {
    const needle = identity?.trim().toLowerCase();
    if (needle && needle.length >= 4 && normalized.includes(needle)) {
      fail("Password must not contain the user's name or email");
    }
  }
  if (bannedSubstrings.some((value) => normalized.includes(value))) {
    fail('Password is too common');
  }
}

function fail(message: string): never {
  throw new BadRequestException({ code: 'WEAK_PASSWORD', message });
}
