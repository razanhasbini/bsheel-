import { ConflictException, Injectable } from '@nestjs/common';
import { createHash } from 'node:crypto';
import type { DatabaseTransaction } from '../../../infrastructure/database/database.service.js';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { AccountCredentials, SessionRecord } from '../domain/auth.types.js';
import type { OAuthIdentity } from './oauth-identity-verifier.js';

interface AccountRow {
  id: string;
  /** Null for a phone-only account — see users.email nullability, migration 0027. */
  email: string | null;
  password_hash: string | null;
  email_verified_at: Date | null;
  phone_verified_at: Date | null;
  status: string;
  token_version: number;
  role: 'moderator' | 'super_admin' | null;
}

interface SessionRow {
  id: string;
  user_id: string;
  family_id: string;
  token_hash: string;
  token_version: number;
  rotated_at: Date | null;
  revoked_at: Date | null;
  expires_at: Date;
}

interface RecoveryIdentityRow {
  token_id: string;
  user_id: string;
  email: string;
  username: string;
}

@Injectable()
export class AuthRepository {
  constructor(private readonly database: DatabaseService) {}

  async createPasswordAccount(input: {
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
  }): Promise<AccountCredentials> {
    try {
      return await this.database.transaction(async (transaction) => {
        const users = await transaction.query<AccountRow>(
          `INSERT INTO users (email, password_hash, email_verified_at)
           VALUES ($1, $2, CASE WHEN $3::boolean THEN NULL ELSE now() END)
           RETURNING id, email::text, password_hash, email_verified_at, phone_verified_at,
                     status, token_version, NULL::text AS role`,
          [input.email.trim().toLowerCase(), input.passwordHash, Boolean(input.confirmation)],
        );
        const user = users.rows[0];
        await transaction.query(
          `INSERT INTO profiles (id, username, display_name, age_verified, profile_completed)
           VALUES ($1, $2, $3, $4, true)`,
          [user.id, input.username.trim().toLowerCase(), input.displayName.trim(), input.ageVerified],
        );
        await transaction.query(
          `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
           VALUES ($1, 'password', $2::text, $2::citext)`,
          [user.id, input.email.trim().toLowerCase()],
        );
        if (input.confirmation) {
          const action = await transaction.query<{ id: string }>(
            `INSERT INTO auth_action_tokens
               (user_id, purpose, token_hash, encrypted_token, expires_at)
             VALUES ($1, 'email_confirmation', $2, $3, $4)
             RETURNING id`,
            [
              user.id,
              input.confirmation.tokenHash,
              input.confirmation.encryptedToken,
              input.confirmation.expiresAt,
            ],
          );
          await transaction.query(
            `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
             VALUES ('auth_action_token', $1, 'auth.email_confirmation.requested',
                     jsonb_build_object('tokenId', $1::uuid))`,
            [action.rows[0].id],
          );
        }
        await transaction.query(
          `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
           VALUES ('user', $1, 'user.created', jsonb_build_object('userId', $1::uuid))`,
          [user.id],
        );
        return this.mapAccount(user);
      });
    } catch (error) {
      const constraint = this.uniqueViolationConstraint(error);
      if (constraint !== null) {
        // The signup form routes the message to a specific field, so the
        // caller has to be able to tell which value collided. `users.email`
        // and `profiles.username` are both inline UNIQUE constraints, which
        // PostgreSQL names after the table and column.
        if (constraint.includes('username')) {
          throw new ConflictException({ code: 'USERNAME_TAKEN', message: 'That username is already taken' });
        }
        if (constraint.includes('email')) {
          throw new ConflictException({ code: 'EMAIL_TAKEN', message: 'That email is already registered' });
        }
        throw new ConflictException({ code: 'ACCOUNT_CONFLICT', message: 'Email or username is already in use' });
      }
      throw error;
    }
  }

  async findAccountByEmail(email: string): Promise<AccountCredentials | null> {
    const result = await this.database.query<AccountRow>(
      `SELECT u.id, u.email::text, u.password_hash, u.email_verified_at, u.phone_verified_at,
              u.status, u.token_version, a.role::text
       FROM users u
       LEFT JOIN admins a ON a.user_id = u.id
       WHERE u.email = $1 AND u.deleted_at IS NULL`,
      [email.trim().toLowerCase()],
    );
    return result.rows[0] ? this.mapAccount(result.rows[0]) : null;
  }

  async findActiveAccountById(id: string): Promise<AccountCredentials | null> {
    const result = await this.database.query<AccountRow>(
      `SELECT u.id, u.email::text, u.password_hash, u.email_verified_at, u.phone_verified_at,
              u.status, u.token_version, a.role::text
       FROM users u
       LEFT JOIN admins a ON a.user_id = u.id
       WHERE u.id = $1 AND u.deleted_at IS NULL AND u.status = 'active'`,
      [id],
    );
    return result.rows[0] ? this.mapAccount(result.rows[0]) : null;
  }

  /**
   * Current `token_version` for each still-active account in `ids`.
   *
   * Used by the realtime gateway to expire live sockets. Revocation was
   * checked only in `handleConnection`, so a socket opened before a logout,
   * ban, or password reset kept receiving events indefinitely — the HTTP
   * side rejected the same token immediately, but the WebSocket did not.
   *
   * An id missing from the result means the account is gone, soft-deleted or
   * no longer `active`, all of which must drop the socket. A version that
   * moved means the session behind it was revoked.
   */
  async liveTokenVersions(ids: readonly string[]): Promise<Map<string, number>> {
    if (ids.length === 0) return new Map();
    const result = await this.database.query<{ id: string; token_version: number }>(
      `SELECT id, token_version
       FROM users
       WHERE id = ANY($1::uuid[]) AND deleted_at IS NULL AND status = 'active'`,
      [ids],
    );
    return new Map(result.rows.map((row) => [row.id, row.token_version]));
  }

  async findOrCreateOAuthAccount(identity: OAuthIdentity, ageVerified: boolean): Promise<AccountCredentials> {
    return this.database.transaction(async (transaction) => {
      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 11))', [
        `${identity.provider}:${identity.subject}`,
      ]);
      const existingIdentity = await transaction.query<AccountRow>(
        `SELECT users.id, users.email::text, users.password_hash, users.email_verified_at,
                users.phone_verified_at, users.status,
                users.token_version, admins.role::text
         FROM auth_identities identity
         JOIN users ON users.id = identity.user_id
         LEFT JOIN admins ON admins.user_id = users.id
         WHERE identity.provider = $1 AND identity.provider_subject = $2`,
        [identity.provider, identity.subject],
      );
      if (existingIdentity.rows[0]) {
        await transaction.query(
          `UPDATE profiles SET age_verified = age_verified OR $2, updated_at = now()
           WHERE id = $1`,
          [existingIdentity.rows[0].id, ageVerified],
        );
        return this.mapAccount(existingIdentity.rows[0]);
      }

      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 12))', [identity.email]);
      const existingEmail = await transaction.query<AccountRow>(
        `SELECT users.id, users.email::text, users.password_hash, users.email_verified_at,
                users.phone_verified_at, users.status,
                users.token_version, admins.role::text
         FROM users LEFT JOIN admins ON admins.user_id = users.id
         WHERE users.email = $1 FOR UPDATE OF users`,
        [identity.email],
      );
      let account = existingEmail.rows[0];
      let createdNew = false;
      if (!account) {
        const created = await transaction.query<AccountRow>(
          `INSERT INTO users (email, email_verified_at)
           VALUES ($1, now())
           RETURNING id, email::text, password_hash, email_verified_at, phone_verified_at,
                     status, token_version, NULL::text AS role`,
          [identity.email],
        );
        account = created.rows[0];
        createdNew = true;
        const username = `user_${createStableSuffix(identity.provider, identity.subject)}`;
        await transaction.query(
          `INSERT INTO profiles (id, username, display_name, age_verified, profile_completed)
           VALUES ($1, $2, $3, $4, false)`,
          [account.id, username, identity.displayName ?? 'New User', ageVerified],
        );
      } else {
        if (account.email_verified_at === null) {
          throw new ConflictException({
            code: 'ACCOUNT_LINK_CONFIRMATION_REQUIRED',
            message: 'Sign in with your password first, then link this provider from your account',
          });
        }
        await transaction.query(
          `UPDATE users SET email_verified_at = COALESCE(email_verified_at, now()), updated_at = now()
           WHERE id = $1`,
          [account.id],
        );
        await transaction.query(
          `UPDATE profiles SET age_verified = age_verified OR $2, updated_at = now()
           WHERE id = $1`,
          [account.id, ageVerified],
        );
        account = { ...account, email_verified_at: account.email_verified_at ?? new Date() };
      }
      await transaction.query(
        `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, $2, $3, $4)`,
        [account.id, identity.provider, identity.subject, identity.email],
      );
      if (createdNew) {
        await transaction.query(
          `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
           VALUES ('user', $1, 'user.created', jsonb_build_object('userId', $1::uuid))`,
          [account.id],
        );
      }
      return this.mapAccount(account);
    });
  }

  async linkOAuthIdentity(userId: string, identity: OAuthIdentity, ageVerified: boolean): Promise<void> {
    await this.database.transaction(async (transaction) => {
      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 11))', [
        `${identity.provider}:${identity.subject}`,
      ]);
      const account = await transaction.query<{ email: string | null; status: string }>(
        `SELECT email::text, status::text FROM users
         WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`,
        [userId],
      );
      if (!account.rows[0] || account.rows[0].status !== 'active') {
        throw new ConflictException({ code: 'ACCOUNT_RESTRICTED', message: 'This account cannot be linked' });
      }
      if (account.rows[0].email && account.rows[0].email.toLowerCase() !== identity.email) {
        throw new ConflictException({
          code: 'OAUTH_EMAIL_MISMATCH',
          message: 'The provider email must match your Bsheel account email',
        });
      }
      if (!account.rows[0].email) {
        await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 12))', [identity.email]);
        const emailOwner = await transaction.query<{ id: string }>(
          'SELECT id FROM users WHERE email = $1 AND id <> $2',
          [identity.email, userId],
        );
        if (emailOwner.rows[0]) {
          throw new ConflictException({
            code: 'EMAIL_TAKEN',
            message: 'That provider email is already registered to another account',
          });
        }
      }
      const existing = await transaction.query<{ user_id: string }>(
        `SELECT user_id FROM auth_identities
         WHERE provider = $1 AND provider_subject = $2 FOR UPDATE`,
        [identity.provider, identity.subject],
      );
      if (existing.rows[0]?.user_id && existing.rows[0].user_id !== userId) {
        throw new ConflictException({
          code: 'OAUTH_IDENTITY_ALREADY_LINKED',
          message: 'This provider identity is already linked to another account',
        });
      }
      await transaction.query(
        `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, $2, $3, $4) ON CONFLICT (provider, provider_subject) DO NOTHING`,
        [userId, identity.provider, identity.subject, identity.email],
      );
      await transaction.query(
        `UPDATE users SET email = COALESCE(email, $2),
           email_verified_at = COALESCE(email_verified_at, now()), updated_at = now()
         WHERE id = $1`,
        [userId, identity.email],
      );
      await transaction.query(
        `UPDATE profiles SET age_verified = age_verified OR $2, updated_at = now()
         WHERE id = $1`,
        [userId, ageVerified],
      );
    });
  }

  /// Sign-in via a CAMARA-verified phone number (issue #1). No email
  /// counterpart exists for a brand-new phone account, so unlike
  /// findOrCreateOAuthAccount there is nothing to match against beyond the
  /// auth_identities row itself.
  async findOrCreateByPhone(phoneNumber: string, ageVerified: boolean, email?: string | null): Promise<AccountCredentials> {
    return this.database.transaction(async (transaction) => {
      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 15))', [`phone:${phoneNumber}`]);
      const normalizedEmail = email?.trim().toLowerCase() || null;
      if (normalizedEmail) {
        // Serialize optional-email ownership with every other auth path. The
        // email is still best-effort: a collision means "create without it",
        // not "fail an otherwise verified phone sign-in".
        await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 12))', [normalizedEmail]);
      }
      const existingIdentity = await transaction.query<AccountRow>(
        `SELECT users.id, users.email::text, users.password_hash, users.email_verified_at,
                users.phone_verified_at, users.status, users.token_version, admins.role::text
         FROM auth_identities identity
         JOIN users ON users.id = identity.user_id
         LEFT JOIN admins ON admins.user_id = users.id
         WHERE identity.provider = 'phone' AND identity.provider_subject = $1`,
        [phoneNumber],
      );
      if (existingIdentity.rows[0]) {
        await transaction.query(
          `UPDATE profiles SET age_verified = age_verified OR $2, updated_at = now() WHERE id = $1`,
          [existingIdentity.rows[0].id, ageVerified],
        );
        return this.mapAccount(existingIdentity.rows[0]);
      }

      // The optional email is best-effort: if another account already holds
      // it, we create the account without one rather than fail a phone
      // sign-in that is otherwise valid. The user can set it later from
      // edit-profile, where a collision can be reported properly.
      const emailIsFree = normalizedEmail
        ? (await transaction.query('SELECT 1 FROM users WHERE email = $1', [normalizedEmail])).rows.length === 0
        : false;
      const created = await transaction.query<AccountRow>(
        `INSERT INTO users (email, phone_number, phone_verified_at)
         VALUES ($2, $1, now())
         RETURNING id, email::text, password_hash, email_verified_at, phone_verified_at,
                   status, token_version, NULL::text AS role`,
        [phoneNumber, emailIsFree ? normalizedEmail : null],
      );
      const account = created.rows[0];
      const username = `user_${createStableSuffix('phone', phoneNumber)}`;
      await transaction.query(
        `INSERT INTO profiles (id, username, display_name, age_verified, profile_completed)
         VALUES ($1, $2, $3, $4, false)`,
        [account.id, username, 'New User', ageVerified],
      );
      await transaction.query(
        `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, 'phone', $2, NULL)`,
        [account.id, phoneNumber],
      );
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('user', $1, 'user.created', jsonb_build_object('userId', $1::uuid))`,
        [account.id],
      );
      return this.mapAccount(account);
    });
  }

  /// Link a CAMARA-verified phone number to the already-signed-in caller's
  /// account. One verified phone per account — an account that already has
  /// one must unlink before replacing it (not built yet; no flow needs it).
  /// Returns the updated account so the caller can issue a fresh token pair
  /// carrying `phoneVerified: true` immediately, rather than making the
  /// client wait for its next natural token refresh.
  async linkPhoneIdentity(userId: string, phoneNumber: string): Promise<AccountCredentials> {
    return this.database.transaction(async (transaction) => {
      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 15))', [`phone:${phoneNumber}`]);
      const account = await transaction.query<{ phone_number: string | null; status: string }>(
        `SELECT phone_number, status::text FROM users WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`,
        [userId],
      );
      if (!account.rows[0] || account.rows[0].status !== 'active') {
        throw new ConflictException({ code: 'ACCOUNT_RESTRICTED', message: 'This account cannot be linked' });
      }
      if (account.rows[0].phone_number) {
        throw new ConflictException({ code: 'PHONE_ALREADY_LINKED', message: 'This account already has a verified phone number' });
      }
      const existing = await transaction.query<{ user_id: string }>(
        `SELECT user_id FROM auth_identities WHERE provider = 'phone' AND provider_subject = $1 FOR UPDATE`,
        [phoneNumber],
      );
      if (existing.rows[0]?.user_id && existing.rows[0].user_id !== userId) {
        throw new ConflictException({
          code: 'PHONE_ALREADY_LINKED_ELSEWHERE',
          message: 'This phone number is already linked to another account',
        });
      }
      await transaction.query(
        `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, 'phone', $2, NULL) ON CONFLICT (provider, provider_subject) DO NOTHING`,
        [userId, phoneNumber],
      );
      const updated = await transaction.query<AccountRow>(
        `UPDATE users SET phone_number = $2, phone_verified_at = now(), updated_at = now()
         WHERE id = $1
         RETURNING id, email::text, password_hash, email_verified_at, phone_verified_at,
                   status, token_version, NULL::text AS role`,
        [userId, phoneNumber],
      );
      const admin = await transaction.query<{ role: 'moderator' | 'super_admin' }>(
        'SELECT role::text FROM admins WHERE user_id = $1',
        [userId],
      );
      return this.mapAccount({ ...updated.rows[0], role: admin.rows[0]?.role ?? null });
    });
  }

  async passwordIdentity(userId: string): Promise<{ email: string | null; username: string } | null> {
    const result = await this.database.query<{ email: string | null; username: string }>(
      `SELECT users.email::text, profiles.username::text
       FROM users JOIN profiles ON profiles.id = users.id WHERE users.id = $1`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  /**
   * Changes the password and ends every existing session.
   *
   * Bumps `token_version` and revokes all refresh sessions, exactly as
   * `completePasswordRecovery` already does. This method used to do neither,
   * so changing your password left every other signed-in device — including
   * an intruder's — fully working. The caller is expected to mint a fresh
   * token pair afterwards so the device doing the change stays signed in.
   */
  /**
   * Replaces the stored hash with an equivalent one, changing nothing else.
   *
   * Used to upgrade a legacy bcrypt hash to argon2 after a successful sign-in
   * with the same password. Distinct from `updatePassword` on purpose: this is
   * not a credential change, so it must not bump `token_version` or revoke
   * sessions — that would sign the user out at the exact moment they signed in.
   */
  async replacePasswordHash(userId: string, passwordHash: string): Promise<void> {
    await this.database.query(
      `UPDATE users SET password_hash = $2, updated_at = now()
       WHERE id = $1 AND status = 'active'`,
      [userId, passwordHash],
    );
  }

  async updatePassword(userId: string, passwordHash: string): Promise<AccountCredentials> {
    return this.database.transaction(async (transaction) => {
      const result = await transaction.query<AccountRow>(
        `UPDATE users SET password_hash = $2, token_version = token_version + 1, updated_at = now()
         WHERE id = $1 AND status = 'active'
         RETURNING id, email::text, password_hash, email_verified_at, phone_verified_at,
                   status, token_version, NULL::text AS role`,
        [userId, passwordHash],
      );
      const account = result.rows[0];
      if (!account) throw new ConflictException({ code: 'ACCOUNT_RESTRICTED', message: 'Password cannot be updated' });
      await transaction.query(
        `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, 'password', $2::text, $2::citext) ON CONFLICT DO NOTHING`,
        [userId, account.email],
      );
      // Every device is signed out. The caller re-issues a pair for this one.
      await transaction.query(
        'UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [userId],
      );
      const admin = await transaction.query<{ role: 'moderator' | 'super_admin' }>(
        'SELECT role::text FROM admins WHERE user_id = $1',
        [userId],
      );
      return this.mapAccount({ ...account, role: admin.rows[0]?.role ?? null });
    });
  }

  async requestPasswordRecovery(input: {
    email: string;
    tokenHash: Buffer;
    encryptedToken: Buffer;
    expiresAt: Date;
  }): Promise<void> {
    const normalizedEmail = input.email.trim().toLowerCase();
    await this.database.transaction(async (transaction) => {
      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 13))', [normalizedEmail]);
      const user = await transaction.query<{ id: string }>(
        `SELECT id FROM users
         WHERE email = $1 AND status = 'active' AND deleted_at IS NULL`,
        [normalizedEmail],
      );
      if (!user.rows[0]) return;

      await transaction.query(
        `UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'password_recovery' AND consumed_at IS NULL`,
        [user.rows[0].id],
      );
      const action = await transaction.query<{ id: string }>(
        `INSERT INTO auth_action_tokens
           (user_id, purpose, token_hash, encrypted_token, expires_at)
         VALUES ($1, 'password_recovery', $2, $3, $4)
         RETURNING id`,
        [user.rows[0].id, input.tokenHash, input.encryptedToken, input.expiresAt],
      );
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('auth_action_token', $1, 'auth.password_recovery.requested',
                 jsonb_build_object('tokenId', $1::uuid))`,
        [action.rows[0].id],
      );
    });
  }

  async requestEmailConfirmation(input: {
    email: string;
    tokenHash: Buffer;
    encryptedToken: Buffer;
    expiresAt: Date;
  }): Promise<void> {
    const normalizedEmail = input.email.trim().toLowerCase();
    await this.database.transaction(async (transaction) => {
      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 14))', [normalizedEmail]);
      const user = await transaction.query<{ id: string }>(
        `SELECT id FROM users
         WHERE email = $1 AND email_verified_at IS NULL
           AND status = 'active' AND deleted_at IS NULL`,
        [normalizedEmail],
      );
      if (!user.rows[0]) return;

      await transaction.query(
        `UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'email_confirmation' AND consumed_at IS NULL`,
        [user.rows[0].id],
      );
      const action = await transaction.query<{ id: string }>(
        `INSERT INTO auth_action_tokens
           (user_id, purpose, token_hash, encrypted_token, expires_at)
         VALUES ($1, 'email_confirmation', $2, $3, $4)
         RETURNING id`,
        [user.rows[0].id, input.tokenHash, input.encryptedToken, input.expiresAt],
      );
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('auth_action_token', $1, 'auth.email_confirmation.requested',
                 jsonb_build_object('tokenId', $1::uuid))`,
        [action.rows[0].id],
      );
    });
  }

  async completeEmailConfirmation(tokenHash: Buffer): Promise<boolean> {
    return this.database.transaction(async (transaction) => {
      const action = await transaction.query<{ user_id: string }>(
        `SELECT user_id FROM auth_action_tokens
         WHERE token_hash = $1 AND purpose = 'email_confirmation'
           AND consumed_at IS NULL AND expires_at > now()
         FOR UPDATE`,
        [tokenHash],
      );
      const userId = action.rows[0]?.user_id;
      if (!userId) return false;
      const updated = await transaction.query(
        `UPDATE users SET email_verified_at = COALESCE(email_verified_at, now()), updated_at = now()
         WHERE id = $1 AND status = 'active' AND deleted_at IS NULL`,
        [userId],
      );
      if (!updated.rowCount) return false;
      await transaction.query(
        `UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'email_confirmation' AND consumed_at IS NULL`,
        [userId],
      );
      return true;
    });
  }

  async recoveryIdentity(tokenHash: Buffer): Promise<{
    tokenId: string;
    userId: string;
    email: string;
    username: string;
  } | null> {
    const result = await this.database.query<RecoveryIdentityRow>(
      `SELECT token.id AS token_id, users.id AS user_id, users.email::text,
              profiles.username::text
       FROM auth_action_tokens token
       JOIN users ON users.id = token.user_id
       JOIN profiles ON profiles.id = users.id
       WHERE token.token_hash = $1 AND token.purpose = 'password_recovery'
         AND token.consumed_at IS NULL AND token.expires_at > now()
         AND users.status = 'active' AND users.deleted_at IS NULL`,
      [tokenHash],
    );
    const row = result.rows[0];
    return row ? {
      tokenId: row.token_id,
      userId: row.user_id,
      email: row.email,
      username: row.username,
    } : null;
  }

  async completePasswordRecovery(tokenId: string, tokenHash: Buffer, passwordHash: string): Promise<boolean> {
    return this.database.transaction(async (transaction) => {
      const action = await transaction.query<{ user_id: string }>(
        `SELECT user_id FROM auth_action_tokens
         WHERE id = $1 AND token_hash = $2 AND purpose = 'password_recovery'
           AND consumed_at IS NULL AND expires_at > now()
         FOR UPDATE`,
        [tokenId, tokenHash],
      );
      const userId = action.rows[0]?.user_id;
      if (!userId) return false;

      const account = await transaction.query<{ email: string }>(
        `UPDATE users
         SET password_hash = $2, token_version = token_version + 1, updated_at = now()
         WHERE id = $1 AND status = 'active' AND deleted_at IS NULL
         RETURNING email::text`,
        [userId, passwordHash],
      );
      if (!account.rows[0]) return false;
      await transaction.query(
        `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, 'password', $2::text, $2::citext) ON CONFLICT DO NOTHING`,
        [userId, account.rows[0].email],
      );
      await transaction.query(
        'UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [userId],
      );
      await transaction.query(
        `UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'password_recovery' AND consumed_at IS NULL`,
        [userId],
      );
      return true;
    });
  }

  async createSession(input: {
    id: string;
    userId: string;
    familyId: string;
    tokenHash: string;
    expiresAt: Date;
    userAgent?: string;
    ipAddress?: string;
  }, transaction?: DatabaseTransaction): Promise<void> {
    await this.database.query(
      `INSERT INTO refresh_sessions
       (id, user_id, family_id, token_hash, expires_at, user_agent, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [input.id, input.userId, input.familyId, input.tokenHash, input.expiresAt, input.userAgent ?? null, input.ipAddress ?? null],
      transaction,
    );
  }

  async findSessionForUpdate(id: string, transaction: DatabaseTransaction): Promise<SessionRecord | null> {
    const result = await transaction.query<SessionRow & { token_version: number }>(
      `SELECT s.id, s.user_id, s.family_id, s.token_hash, s.rotated_at, s.revoked_at,
              s.expires_at, u.token_version
       FROM refresh_sessions s JOIN users u ON u.id = s.user_id
       WHERE s.id = $1 FOR UPDATE`,
      [id],
    );
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

  async markSessionRotated(id: string, transaction: DatabaseTransaction): Promise<void> {
    await transaction.query('UPDATE refresh_sessions SET rotated_at = now() WHERE id = $1', [id]);
  }

  async revokeSession(id: string): Promise<void> {
    await this.database.query('UPDATE refresh_sessions SET revoked_at = now() WHERE id = $1 AND revoked_at IS NULL', [id]);
  }

  async revokeFamily(familyId: string, transaction?: DatabaseTransaction): Promise<void> {
    await this.database.query(
      'UPDATE refresh_sessions SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL',
      [familyId],
      transaction,
    );
  }

  async touchLastLogin(userId: string): Promise<void> {
    await this.database.query('UPDATE users SET last_login_at = now() WHERE id = $1', [userId]);
  }

  transaction<T>(work: (transaction: DatabaseTransaction) => Promise<T>): Promise<T> {
    return this.database.transaction(work);
  }

  private mapAccount(row: AccountRow): AccountCredentials {
    return {
      id: row.id,
      email: row.email,
      passwordHash: row.password_hash,
      emailVerified: row.email_verified_at !== null,
      phoneVerified: row.phone_verified_at !== null,
      status: row.status,
      tokenVersion: row.token_version,
      role: row.role ?? 'user',
    };
  }

  /// Returns the violated constraint name for a unique-violation error, an
  /// empty string when PostgreSQL did not report one, or null when the error
  /// is not a unique violation at all.
  private uniqueViolationConstraint(error: unknown): string | null {
    if (
      typeof error !== 'object' ||
      error === null ||
      !('code' in error) ||
      (error as { code?: unknown }).code !== '23505'
    ) {
      return null;
    }
    const constraint = (error as { constraint?: unknown }).constraint;
    return typeof constraint === 'string' ? constraint : '';
  }
}

function createStableSuffix(provider: string, subject: string): string {
  return createHash('sha256').update(`${provider}:${subject}`, 'utf8').digest('hex').slice(0, 12);
}
