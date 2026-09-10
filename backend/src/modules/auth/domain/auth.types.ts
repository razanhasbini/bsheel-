import type { SystemRole } from '../../../common/auth/auth-user.js';

export interface AccountCredentials {
  readonly id: string;
  /** Null for a phone-only account — see users.email nullability, migration 0027. */
  readonly email: string | null;
  readonly passwordHash: string | null;
  readonly emailVerified: boolean;
  readonly phoneVerified: boolean;
  readonly status: string;
  readonly tokenVersion: number;
  readonly role: SystemRole;
}

export interface SessionRecord {
  readonly id: string;
  readonly userId: string;
  readonly familyId: string;
  readonly tokenHash: string;
  readonly tokenVersion: number;
  readonly rotatedAt: Date | null;
  readonly revokedAt: Date | null;
  readonly expiresAt: Date;
}

export interface TokenPair {
  readonly accessToken: string;
  readonly refreshToken: string;
  readonly expiresIn: number;
}

export interface RegistrationPendingConfirmation {
  readonly confirmationRequired: true;
}
