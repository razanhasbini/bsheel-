import { ConflictException, Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

@Injectable()
export class AccountRepository {
  constructor(private readonly database: DatabaseService) {}

  async requestExport(userId: string) {
    return this.database.transaction(async (transaction) => {
      await transaction.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 3))', [userId]);
      const recent = await transaction.query(
        `SELECT 1 FROM gdpr_export_log WHERE user_id = $1
         AND requested_at > now() - interval '5 minutes' LIMIT 1`, [userId],
      );
      if (recent.rowCount) throw new ConflictException({ code: 'EXPORT_RATE_LIMIT', message: 'Export rate limit; try again in 5 minutes' });
      const request = await transaction.query<{ id: string; requested_at: Date }>(
        'INSERT INTO gdpr_export_log (user_id) VALUES ($1) RETURNING id::text, requested_at', [userId],
      );
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('privacy_export', $1, 'privacy.export.requested', $2::jsonb)`,
        [request.rows[0].id, JSON.stringify({ exportId: request.rows[0].id, userId })],
      );
      return { id: request.rows[0].id, status: 'pending', requestedAt: request.rows[0].requested_at };
    });
  }

  async exports(userId: string) {
    return (await this.database.query(
      `SELECT id::text, requested_at, completed_at, object_key, expires_at,
              CASE WHEN completed_at IS NULL THEN 'pending'
                   WHEN expires_at <= now() THEN 'expired' ELSE 'ready' END AS status
       FROM gdpr_export_log WHERE user_id = $1 ORDER BY requested_at DESC LIMIT 20`, [userId],
    )).rows;
  }

  async requestDeletion(userId: string) {
    return this.database.transaction(async (transaction) => {
      const profile = await transaction.query<{ id: string }>('SELECT id FROM profiles WHERE id = $1 FOR UPDATE', [userId]);
      if (!profile.rows[0]) throw new ConflictException({ code: 'DELETION_ALREADY_REQUESTED', message: 'Account deletion is already pending' });
      const request = await transaction.query<{ id: string; execute_after: Date }>(
        `INSERT INTO account_delete_requests (user_id, execute_after)
         VALUES ($1, now()) ON CONFLICT (user_id) DO UPDATE
         SET cancelled_at = NULL RETURNING id, execute_after`, [userId],
      );
      await transaction.query(
        `UPDATE profiles SET username = 'deleted_' || substr(replace(id::text, '-', ''), 1, 8),
           display_name = 'Deleted account', avatar_url = NULL, bio = NULL,
           analytics_consent_at = NULL, updated_at = now() WHERE id = $1`, [userId],
      );
      await transaction.query(
        `UPDATE users SET status = 'deletion_pending', token_version = token_version + 1,
           updated_at = now() WHERE id = $1`, [userId],
      );
      await transaction.query('UPDATE refresh_sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL', [userId]);
      await transaction.query('DELETE FROM device_tokens WHERE user_id = $1', [userId]);
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('account', $1, 'account.deletion.requested', $2::jsonb)`,
        [userId, JSON.stringify({ requestId: request.rows[0].id, userId, executeAfter: request.rows[0].execute_after })],
      );
      return { requestId: request.rows[0].id, executeAfter: request.rows[0].execute_after };
    });
  }
}
