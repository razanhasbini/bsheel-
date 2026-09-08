import { Injectable, BadRequestException, ConflictException, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { AdminRepositoryBase } from './admin-repository.base.js';

@Injectable()
export class AdminIdentityRepository extends AdminRepositoryBase {
  constructor(database: DatabaseService) { super(database); }

  async createUser(
    actorId: string,
    input: {
      email: string;
      passwordHash: string;
      username: string;
      displayName: string;
    },
  ) {
    try {
      return await this.database.transaction(async (transaction) => {
        const user = await transaction.query<{ id: string }>(
          `INSERT INTO users (email, password_hash, email_verified_at)
           VALUES ($1, $2, now()) RETURNING id`,
          [input.email.trim().toLowerCase(), input.passwordHash],
        );
        const userId = user.rows[0].id;
        await transaction.query(
          `INSERT INTO profiles (id, username, display_name, age_verified, profile_completed)
           VALUES ($1, $2, $3, false, false)`,
          [
            userId,
            input.username.trim().toLowerCase(),
            input.displayName.trim(),
          ],
        );
        await transaction.query(
          `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
           VALUES ($1, 'password', $2::text, $2::citext)`,
          [userId, input.email.trim().toLowerCase()],
        );
        await this.audit(
          actorId,
          'user.create',
          'profile',
          userId,
          null,
          {
            email_confirmed_at_create: true,
          },
          transaction,
        );
        await transaction.query(
          `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
           VALUES ('user', $1, 'user.created', jsonb_build_object('userId', $1::uuid))`,
          [userId],
        );
        return { userId };
      });
    } catch (error) {
      if (
        typeof error === 'object' &&
        error !== null &&
        'code' in error &&
        error.code === '23505'
      ) {
        throw new ConflictException({
          code: 'ACCOUNT_CONFLICT',
          message: 'Email or username is already in use',
        });
      }
      throw error;
    }
  }

  async queueUserDeletion(actorId: string, userId: string): Promise<void> {
    if (actorId === userId) {
      throw new BadRequestException({
        code: 'CANNOT_DELETE_SELF',
        message: 'Cannot delete yourself',
      });
    }
    await this.database.transaction(async (transaction) => {
      const user = await transaction.query<{ status: string }>(
        'SELECT status::text FROM users WHERE id = $1 FOR UPDATE',
        [userId],
      );
      if (!user.rows[0])
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        });
      const request = await transaction.query<{ id: string }>(
        `INSERT INTO account_delete_requests (user_id, execute_after)
         VALUES ($1, now()) ON CONFLICT (user_id) DO UPDATE
         SET cancelled_at = NULL, execute_after = now() RETURNING id`,
        [userId],
      );
      await transaction.query(
        `UPDATE profiles SET username = 'deleted_' || substr(replace(id::text, '-', ''), 1, 8),
           display_name = 'Deleted account', avatar_url = NULL, bio = NULL,
           analytics_consent_at = NULL, updated_at = now() WHERE id = $1`,
        [userId],
      );
      await transaction.query(
        `UPDATE users SET status = 'deletion_pending', token_version = token_version + 1,
           updated_at = now() WHERE id = $1`,
        [userId],
      );
      await transaction.query(
        'UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [userId],
      );
      await transaction.query('DELETE FROM device_tokens WHERE user_id = $1', [
        userId,
      ]);
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('account', $1, 'account.deletion.requested', $2::jsonb)`,
        [userId, JSON.stringify({ requestId: request.rows[0].id, userId })],
      );
      await this.audit(
        actorId,
        'user.delete',
        'profile',
        userId,
        {
          status: user.rows[0].status,
        },
        { queued: true },
        transaction,
      );
    });
  }

  async setAdminRole(
    actorId: string,
    userId: string,
    role?: 'moderator' | 'super_admin',
  ): Promise<void> {
    if (actorId === userId) {
      throw new BadRequestException({
        code: 'CANNOT_CHANGE_OWN_ROLE',
        message: 'Cannot change your own role',
      });
    }
    await this.database.transaction(async (transaction) => {
      const target = await transaction.query(
        'SELECT 1 FROM users WHERE id = $1 FOR UPDATE',
        [userId],
      );
      if (!target.rowCount)
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        });
      const before = await transaction.query<{ role: string }>(
        'SELECT role::text FROM admins WHERE user_id = $1',
        [userId],
      );
      if (role) {
        await transaction.query(
          `INSERT INTO admins (user_id, role) VALUES ($1, $2::admin_role)
           ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role`,
          [userId, role],
        );
      } else {
        await transaction.query('DELETE FROM admins WHERE user_id = $1', [
          userId,
        ]);
      }
      await this.audit(
        actorId,
        role ? 'admin.grant' : 'admin.revoke',
        'profile',
        userId,
        { role: before.rows[0]?.role ?? null },
        { role: role ?? null },
        transaction,
      );
    });
  }

  async passwordIdentity(
    userId: string,
  ): Promise<{ email: string; username: string } | null> {
    const result = await this.database.query<{
      email: string;
      username: string;
    }>(
      `SELECT users.email::text, profiles.username::text
       FROM users JOIN profiles ON profiles.id = users.id WHERE users.id = $1`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  async forceResetPassword(
    actorId: string,
    userId: string,
    passwordHash: string,
  ): Promise<void> {
    if (actorId === userId) {
      throw new BadRequestException({
        code: 'USE_SELF_PASSWORD_FLOW',
        message: 'Use the normal account flow to change your own password',
      });
    }
    await this.database.transaction(async (transaction) => {
      const target = await transaction.query<{ email: string }>(
        `UPDATE users SET password_hash = $2, token_version = token_version + 1, updated_at = now()
         WHERE id = $1 RETURNING email::text`,
        [userId, passwordHash],
      );
      if (!target.rows[0])
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        });
      await transaction.query(
        `INSERT INTO auth_identities (user_id, provider, provider_subject, provider_email)
         VALUES ($1, 'password', $2::text, $2::citext) ON CONFLICT DO NOTHING`,
        [userId, target.rows[0].email],
      );
      await transaction.query(
        'UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL',
        [userId],
      );
      const notification = await transaction.query<{ id: string }>(
        `INSERT INTO notifications (user_id, title, body, type, reference_id)
         VALUES ($1, 'Your password was reset by an admin',
                 'If you did not request this, contact support immediately.',
                 'security_alert', $2) RETURNING id`,
        [userId, actorId],
      );
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('notification', $1, 'notification.created', $2::jsonb)`,
        [
          notification.rows[0].id,
          JSON.stringify({
            notificationId: notification.rows[0].id,
            userId,
          }),
        ],
      );
      await this.audit(
        actorId,
        'user.reset_password',
        'profile',
        userId,
        null,
        {
          forced: true,
        },
        transaction,
      );
    });
  }

  async queuePasswordRecovery(
    actorId: string,
    userId: string,
    token: { tokenHash: Buffer; encryptedToken: Buffer; expiresAt: Date },
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const target = await transaction.query<{ email: string }>(
        `SELECT email::text FROM users
         WHERE id = $1 AND deleted_at IS NULL FOR UPDATE`,
        [userId],
      );
      if (!target.rows[0]) {
        throw new NotFoundException({
          code: 'USER_NOT_FOUND',
          message: 'User not found',
        });
      }
      await transaction.query(
        `UPDATE auth_action_tokens SET consumed_at = now()
         WHERE user_id = $1 AND purpose = 'password_recovery' AND consumed_at IS NULL`,
        [userId],
      );
      const action = await transaction.query<{ id: string }>(
        `INSERT INTO auth_action_tokens
           (user_id, purpose, token_hash, encrypted_token, expires_at)
         VALUES ($1, 'password_recovery', $2, $3, $4)
         RETURNING id`,
        [userId, token.tokenHash, token.encryptedToken, token.expiresAt],
      );
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('auth_action_token', $1, 'auth.password_recovery.requested',
                 jsonb_build_object('tokenId', $1::uuid))`,
        [action.rows[0].id],
      );
      await this.audit(
        actorId,
        'user.request_password_reset',
        'profile',
        userId,
        null,
        { queued: true },
        transaction,
      );
    });
  }
}
