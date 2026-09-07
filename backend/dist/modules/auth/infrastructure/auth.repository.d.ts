import type { DatabaseTransaction } from '../../../infrastructure/database/database.service.js';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { AccountCredentials, SessionRecord } from '../domain/auth.types.js';
import type { OAuthIdentity } from './oauth-identity-verifier.js';
export declare class AuthRepository {
    private readonly database;
    constructor(database: DatabaseService);
    createPasswordAccount(input: {
        email: string;
        passwordHash: string;
        username: string;
        displayName: string;
        ageVerified: boolean;
        confirmation?: {
            tokenHash: Buffer;
            encryptedToken: Buffer;
            expiresAt: Date;
        };
    }): Promise<AccountCredentials>;
    findAccountByEmail(email: string): Promise<AccountCredentials | null>;
    findActiveAccountById(id: string): Promise<AccountCredentials | null>;
    findOrCreateOAuthAccount(identity: OAuthIdentity, ageVerified: boolean): Promise<AccountCredentials>;
    passwordIdentity(userId: string): Promise<{
        email: string;
        username: string;
    } | null>;
    updatePassword(userId: string, passwordHash: string): Promise<AccountCredentials>;
    requestPasswordRecovery(input: {
        email: string;
        tokenHash: Buffer;
        encryptedToken: Buffer;
        expiresAt: Date;
    }): Promise<void>;
    requestEmailConfirmation(input: {
        email: string;
        tokenHash: Buffer;
        encryptedToken: Buffer;
        expiresAt: Date;
    }): Promise<void>;
    completeEmailConfirmation(tokenHash: Buffer): Promise<boolean>;
    recoveryIdentity(tokenHash: Buffer): Promise<{
        tokenId: string;
        userId: string;
        email: string;
        username: string;
    } | null>;
    completePasswordRecovery(tokenId: string, tokenHash: Buffer, passwordHash: string): Promise<boolean>;
    createSession(input: {
        id: string;
        userId: string;
        familyId: string;
        tokenHash: string;
        expiresAt: Date;
        userAgent?: string;
        ipAddress?: string;
    }, transaction?: DatabaseTransaction): Promise<void>;
    findSessionForUpdate(id: string, transaction: DatabaseTransaction): Promise<SessionRecord | null>;
    markSessionRotated(id: string, transaction: DatabaseTransaction): Promise<void>;
    revokeSession(id: string): Promise<void>;
    revokeFamily(familyId: string, transaction?: DatabaseTransaction): Promise<void>;
    touchLastLogin(userId: string): Promise<void>;
    transaction<T>(work: (transaction: DatabaseTransaction) => Promise<T>): Promise<T>;
    private mapAccount;
    private isUniqueViolation;
}
