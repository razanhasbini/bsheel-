var __decorate = (this && this.__decorate) || function (decorators, target, key, desc) {
    var c = arguments.length, r = c < 3 ? target : desc === null ? desc = Object.getOwnPropertyDescriptor(target, key) : desc, d;
    if (typeof Reflect === "object" && typeof Reflect.decorate === "function") r = Reflect.decorate(decorators, target, key, desc);
    else for (var i = decorators.length - 1; i >= 0; i--) if (d = decorators[i]) r = (c < 3 ? d(r) : c > 3 ? d(target, key, r) : d(target, key)) || r;
    return c > 3 && r && Object.defineProperty(target, key, r), r;
};
var __metadata = (this && this.__metadata) || function (k, v) {
    if (typeof Reflect === "object" && typeof Reflect.metadata === "function") return Reflect.metadata(k, v);
};
import { ConflictException, Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
let AuthRepository = class AuthRepository {
    database;
    constructor(database) {
        this.database = database;
    }
    async createPasswordAccount(input) {
        try {
            return await this.database.transaction(async (transaction) => {
                const users = await transaction.query(`INSERT INTO users (email, password_hash, email_verified_at)
           VALUES ($1, $2, CASE WHEN $3::boolean THEN NULL ELSE now() END)
           RETURNING id, email::text, password_hash, email_verified_at,
                     status, token_version, NULL::text AS role`, [input.email.trim().toLowerCase(), input.passwordHash, Boolean(input.confirmation)]);
                const user = users.rows[0];
                await transaction.query(`INSERT INTO profiles (id, username, display_name, age_verified, profile_completed)
           VALUES ($1, $2, $3, $4, true)`, [user.id, input.username.trim().toLowerCase(), input.displayName.trim(), input.ageVerified]);
                await transaction.query(`INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
           VALUES ($1, 'password', $2::text, $2::citext)`, [user.id, input.email.trim().toLowerCase()]);
                if (input.confirmation) {
                    const action = await transaction.query(`INSERT INTO auth_action_tokens
               (user_id, purpose, token_hash, encrypted_token, expires_at)
             VALUES ($1, 'email_confirmation', $2, $3, $4)
             RETURNING id`, [
                        user.id,
                        input.confirmation.tokenHash,
                        input.confirmation.encryptedToken,
                        input.confirmation.expiresAt,
                    ]);
                    await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
             VALUES ('auth_action_token', $1, 'auth.email_confirmation.requested',
                     jsonb_build_object('tokenId', $1::uuid))`, [action.rows[0].id]);
                }
                await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
           VALUES ('user', $1, 'user.created', jsonb_build_object('userId', $1::uuid))`, [user.id]);
                return this.mapAccount(user);
            });
        }
        catch (error) {
            if (this.isUniqueViolation(error)) {
                throw new ConflictException({ code: 'ACCOUNT_CONFLICT', message: 'Email or username is already in use' });
            }
            throw error;
        }
    }
    async findAccountByEmail(email) {
        const result = await this.database.query(`SELECT u.id, u.email::text, u.password_hash, u.email_verified_at,
              u.status, u.token_version, a.role::text
       FROM users u
       LEFT JOIN admins a ON a.user_id = u.id
       WHERE u.email = $1 AND u.deleted_at IS NULL`, [email.trim().toLowerCase()]);
        return result.rows[0] ? this.mapAccount(result.rows[0]) : null;
    }
    async findActiveAccountById(id) {
        const result = await this.database.query(`SELECT u.id, u.email::text, u.password_hash, u.email_verified_at,
              u.status, u.token_version, a.role::text
       FROM users u
       LEFT JOIN admins a ON a.user_id = u.id
       WHERE u.id = $1 AND u.deleted_at IS NULL AND u.status = 'active'`, [id]);
        return result.rows[0] ? this.mapAccount(result.rows[0]) : null;
    }
    async findOrCreateOAuthAccount(identity, ageVerified) {
        return this.database.transaction(async (transaction) => {
            await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 11))', [
                `${identity.provider}:${identity.subject}`,
            ]);
            const existingIdentity = await transaction.query(`SELECT users.id, users.email::text, users.password_hash, users.email_verified_at, users.status,
                users.token_version, admins.role::text
         FROM auth_identities identity
         JOIN users ON users.id = identity.user_id
         LEFT JOIN admins ON admins.user_id = users.id
         WHERE identity.provider = $1 AND identity.provider_subject = $2`, [identity.provider, identity.subject]);
            if (existingIdentity.rows[0]) {
                await transaction.query(`UPDATE profiles SET age_verified = age_verified OR $2, updated_at = now()
           WHERE id = $1`, [existingIdentity.rows[0].id, ageVerified]);
                return this.mapAccount(existingIdentity.rows[0]);
            }
            await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 12))', [identity.email]);
            const existingEmail = await transaction.query(`SELECT users.id, users.email::text, users.password_hash, users.email_verified_at, users.status,
                users.token_version, admins.role::text
         FROM users LEFT JOIN admins ON admins.user_id = users.id
         WHERE users.email = $1 FOR UPDATE OF users`, [identity.email]);
            let account = existingEmail.rows[0];
            let createdNew = false;
            if (!account) {
                const created = await transaction.query(`INSERT INTO users (email, email_verified_at)
           VALUES ($1, now())
           RETURNING id, email::text, password_hash, email_verified_at,
                     status, token_version, NULL::text AS role`, [identity.email]);
                account = created.rows[0];
                createdNew = true;
                const username = `user_${createStableSuffix(identity.provider, identity.subject)}`;
                await transaction.query(`INSERT INTO profiles (id, username, display_name, age_verified, profile_completed)
           VALUES ($1, $2, $3, $4, false)`, [account.id, username, identity.displayName ?? 'New User', ageVerified]);
            }
            else {
                await transaction.query(`UPDATE users SET email_verified_at = COALESCE(email_verified_at, now()), updated_at = now()
           WHERE id = $1`, [account.id]);
                await transaction.query(`UPDATE profiles SET age_verified = age_verified OR $2, updated_at = now()
           WHERE id = $1`, [account.id, ageVerified]);
                account = { ...account, email_verified_at: account.email_verified_at ?? new Date() };
            }
            await transaction.query(`INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, $2, $3, $4)`, [account.id, identity.provider, identity.subject, identity.email]);
            if (createdNew) {
                await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
           VALUES ('user', $1, 'user.created', jsonb_build_object('userId', $1::uuid))`, [account.id]);
            }
            return this.mapAccount(account);
        });
    }
    async passwordIdentity(userId) {
        const result = await this.database.query(`SELECT users.email::text, profiles.username::text
       FROM users JOIN profiles ON profiles.id = users.id WHERE users.id = $1`, [userId]);
        return result.rows[0] ?? null;
    }
    async updatePassword(userId, passwordHash) {
        return this.database.transaction(async (transaction) => {
            const result = await transaction.query(`UPDATE users SET password_hash = $2, updated_at = now()
         WHERE id = $1 AND status = 'active'
         RETURNING id, email::text, password_hash, email_verified_at,
                   status, token_version, NULL::text AS role`, [userId, passwordHash]);
            const account = result.rows[0];
            if (!account)
                throw new ConflictException({ code: 'ACCOUNT_RESTRICTED', message: 'Password cannot be updated' });
            await transaction.query(`INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, 'password', $2::text, $2::citext) ON CONFLICT DO NOTHING`, [userId, account.email]);
            const admin = await transaction.query('SELECT role::text FROM admins WHERE user_id = $1', [userId]);
            return this.mapAccount({ ...account, role: admin.rows[0]?.role ?? null });
        });
    }
    async requestPasswordRecovery(input) {
        const normalizedEmail = input.email.trim().toLowerCase();
        await this.database.transaction(async (transaction) => {
            await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 13))', [normalizedEmail]);
            const user = await transaction.query(`SELECT id FROM users
         WHERE email = $1 AND status = 'active' AND deleted_at IS NULL`, [normalizedEmail]);
            if (!user.rows[0])
                return;
            await transaction.query(`UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'password_recovery' AND consumed_at IS NULL`, [user.rows[0].id]);
            const action = await transaction.query(`INSERT INTO auth_action_tokens
           (user_id, purpose, token_hash, encrypted_token, expires_at)
         VALUES ($1, 'password_recovery', $2, $3, $4)
         RETURNING id`, [user.rows[0].id, input.tokenHash, input.encryptedToken, input.expiresAt]);
            await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('auth_action_token', $1, 'auth.password_recovery.requested',
                 jsonb_build_object('tokenId', $1::uuid))`, [action.rows[0].id]);
        });
    }
    async requestEmailConfirmation(input) {
        const normalizedEmail = input.email.trim().toLowerCase();
        await this.database.transaction(async (transaction) => {
            await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 14))', [normalizedEmail]);
            const user = await transaction.query(`SELECT id FROM users
         WHERE email = $1 AND email_verified_at IS NULL
           AND status = 'active' AND deleted_at IS NULL`, [normalizedEmail]);
            if (!user.rows[0])
                return;
            await transaction.query(`UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'email_confirmation' AND consumed_at IS NULL`, [user.rows[0].id]);
            const action = await transaction.query(`INSERT INTO auth_action_tokens
           (user_id, purpose, token_hash, encrypted_token, expires_at)
         VALUES ($1, 'email_confirmation', $2, $3, $4)
         RETURNING id`, [user.rows[0].id, input.tokenHash, input.encryptedToken, input.expiresAt]);
            await transaction.query(`INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('auth_action_token', $1, 'auth.email_confirmation.requested',
                 jsonb_build_object('tokenId', $1::uuid))`, [action.rows[0].id]);
        });
    }
    async completeEmailConfirmation(tokenHash) {
        return this.database.transaction(async (transaction) => {
            const action = await transaction.query(`SELECT user_id FROM auth_action_tokens
         WHERE token_hash = $1 AND purpose = 'email_confirmation'
           AND consumed_at IS NULL AND expires_at > now()
         FOR UPDATE`, [tokenHash]);
            const userId = action.rows[0]?.user_id;
            if (!userId)
                return false;
            const updated = await transaction.query(`UPDATE users SET email_verified_at = COALESCE(email_verified_at, now()), updated_at = now()
         WHERE id = $1 AND status = 'active' AND deleted_at IS NULL`, [userId]);
            if (!updated.rowCount)
                return false;
            await transaction.query(`UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'email_confirmation' AND consumed_at IS NULL`, [userId]);
            return true;
        });
    }
    async recoveryIdentity(tokenHash) {
        const result = await this.database.query(`SELECT token.id AS token_id, users.id AS user_id, users.email::text,
              profiles.username::text
       FROM auth_action_tokens token
       JOIN users ON users.id = token.user_id
       JOIN profiles ON profiles.id = users.id
       WHERE token.token_hash = $1 AND token.purpose = 'password_recovery'
         AND token.consumed_at IS NULL AND token.expires_at > now()
         AND users.status = 'active' AND users.deleted_at IS NULL`, [tokenHash]);
        const row = result.rows[0];
        return row ? {
            tokenId: row.token_id,
            userId: row.user_id,
            email: row.email,
            username: row.username,
        } : null;
    }
    async completePasswordRecovery(tokenId, tokenHash, passwordHash) {
        return this.database.transaction(async (transaction) => {
            const action = await transaction.query(`SELECT user_id FROM auth_action_tokens
         WHERE id = $1 AND token_hash = $2 AND purpose = 'password_recovery'
           AND consumed_at IS NULL AND expires_at > now()
         FOR UPDATE`, [tokenId, tokenHash]);
            const userId = action.rows[0]?.user_id;
            if (!userId)
                return false;
            const account = await transaction.query(`UPDATE users
         SET password_hash = $2, token_version = token_version + 1, updated_at = now()
         WHERE id = $1 AND status = 'active' AND deleted_at IS NULL
         RETURNING email::text`, [userId, passwordHash]);
            if (!account.rows[0])
                return false;
            await transaction.query(`INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, 'password', $2::text, $2::citext) ON CONFLICT DO NOTHING`, [userId, account.rows[0].email]);
            await transaction.query('UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [userId]);
            await transaction.query(`UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'password_recovery' AND consumed_at IS NULL`, [userId]);
            return true;
        });
    }
    async createSession(input, transaction) {
        await this.database.query(`INSERT INTO refresh_sessions
       (id, user_id, family_id, token_hash, expires_at, user_agent, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`, [input.id, input.userId, input.familyId, input.tokenHash, input.expiresAt, input.userAgent ?? null, input.ipAddress ?? null], transaction);
    }
    async findSessionForUpdate(id, transaction) {
        const result = await transaction.query(`SELECT s.id, s.user_id, s.family_id, s.token_hash, s.rotated_at, s.revoked_at,
              s.expires_at, u.token_version
       FROM refresh_sessions s JOIN users u ON u.id = s.user_id
       WHERE s.id = $1 FOR UPDATE`, [id]);
        const row = result.rows[0];
        return row ? {
            id: row.id,
            userId: row.user_id,
            familyId: row.family_id,
            tokenHash: row.token_hash,
            tokenVersion: row.token_version,
            rotatedAt: row.rotated_at,
            revokedAt: row.revoked_at,
            expiresAt: row.expires_at,
        } : null;
    }
    async markSessionRotated(id, transaction) {
        await transaction.query('UPDATE refresh_sessions SET rotated_at = now() WHERE id = $1', [id]);
    }
    async revokeSession(id) {
        await this.database.query('UPDATE refresh_sessions SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL', [id]);
    }
    async revokeFamily(familyId, transaction) {
        await this.database.query('UPDATE refresh_sessions SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL', [familyId], transaction);
    }
    async touchLastLogin(userId) {
        await this.database.query('UPDATE users SET last_login_at = now() WHERE id = $1', [userId]);
    }
    transaction(work) {
        return this.database.transaction(work);
    }
    mapAccount(row) {
        return {
            id: row.id,
            email: row.email,
            passwordHash: row.password_hash,
            emailVerified: row.email_verified_at !== null,
            status: row.status,
            tokenVersion: row.token_version,
            role: row.role ?? 'user',
        };
    }
    isUniqueViolation(error) {
        return typeof error === 'object' && error !== null && 'code' in error && error.code === '23505';
    }
};
AuthRepository = __decorate([
    Injectable(),
    __metadata("design:paramtypes", [DatabaseService])
], AuthRepository);
export { AuthRepository };
function createStableSuffix(provider, subject) {
    return createHash('sha256').update(`${provider}:${subject}`, 'utf8').digest('hex').slice(0, 12);
}
//# sourceMappingURL=auth.repository.js.map