import type { SystemRole } from '../../../common/auth/auth-user.js';
export interface AccountCredentials {
    readonly id: string;
    readonly email: string;
    readonly passwordHash: string | null;
    readonly emailVerified: boolean;
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
