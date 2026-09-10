export const systemRoles = ['user', 'moderator', 'super_admin'] as const;
export type SystemRole = (typeof systemRoles)[number];

export interface AuthUser {
  readonly id: string;
  /** Null for a phone-only account (no email on file) — see users.email nullability, migration 0027. */
  readonly email: string | null;
  /** Whether a CAMARA-verified phone number is on file (users.phone_verified_at, migration 0027) — the mobile app gates on this once phone sign-in is enabled. */
  readonly phoneVerified: boolean;
  readonly role: SystemRole;
  readonly tokenVersion: number;
}

export interface AccessTokenPayload {
  readonly sub: string;
  readonly email: string | null;
  readonly phoneVerified: boolean;
  readonly role: SystemRole;
  readonly tokenVersion: number;
  readonly type: 'access';
}

export interface RefreshTokenPayload {
  readonly sub: string;
  readonly sid: string;
  readonly familyId: string;
  readonly jti: string;
  readonly tokenVersion: number;
  readonly type: 'refresh';
}
