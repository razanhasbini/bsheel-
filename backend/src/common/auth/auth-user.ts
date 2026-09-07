export const systemRoles = ['user', 'moderator', 'super_admin'] as const;
export type SystemRole = (typeof systemRoles)[number];

export interface AuthUser {
  readonly id: string;
  readonly email: string;
  readonly role: SystemRole;
  readonly tokenVersion: number;
}

export interface AccessTokenPayload {
  readonly sub: string;
  readonly email: string;
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
