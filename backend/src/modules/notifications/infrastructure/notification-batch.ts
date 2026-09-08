import type { DatabaseTransaction } from '../../../infrastructure/database/database.service.js';

export interface NotificationInsert {
  userId: string;
  title: string;
  body: string;
  type: string;
  referenceId: string | null;
  actorId: string | null;
}

/** One statement, atomically paired notification/outbox rows, independent of fanout size. */
export async function insertNotificationBatch(transaction: DatabaseTransaction, notifications: readonly NotificationInsert[]): Promise<void> {
  if (!notifications.length) return;
  await transaction.query(
    `WITH inserted AS (
       INSERT INTO notifications (user_id, title, body, type, reference_id, actor_id)
       SELECT "userId"::uuid, title, body, type, "referenceId"::uuid, "actorId"::uuid
       FROM jsonb_to_recordset($1::jsonb) AS n("userId" text, title text, body text, type text, "referenceId" text, "actorId" text)
       RETURNING id, user_id
     )
     INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
     SELECT 'notification', id, 'notification.created',
            jsonb_build_object('notificationId', id, 'userId', user_id) FROM inserted`,
    [JSON.stringify(notifications)],
  );
}
