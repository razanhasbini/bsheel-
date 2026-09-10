import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

export interface GeofencingSubscriptionRecord {
  readonly id: string;
  readonly userQuestId: string;
  readonly placeId: string;
  readonly providerSubscriptionId: string | null;
  readonly providerSubscriptionIds: readonly string[];
  readonly status: 'pending' | 'active' | 'failed' | 'expired';
  readonly callbackSecret: string;
  readonly startsAt: Date;
  readonly expiresAt: Date;
}

export interface GeofencingEventRecord {
  readonly type: 'ENTER' | 'EXIT';
  readonly occurredAt: Date;
}

interface SubscriptionRow {
  id: string;
  user_quest_id: string;
  place_id: string;
  provider_subscription_id: string | null;
  provider_subscription_ids: string[];
  status: 'pending' | 'active' | 'failed' | 'expired';
  callback_secret: string;
  starts_at: Date;
  expires_at: Date;
}

/**
 * Persistence for CAMARA Geofencing Subscriptions and the entry/exit
 * events they deliver. Events are only ever read back within the
 * subscription's own window, which is the quest's window — presence
 * outside the quest is not evidence of completing it.
 */
@Injectable()
export class GeofencingRepository {
  constructor(private readonly database: DatabaseService) {}

  /// Claims the single subscription slot for an assignment. Returns null
  /// when one already exists, so a retried quest.assigned event cannot
  /// create a second provider subscription.
  async create(input: {
    userQuestId: string;
    placeId: string;
    callbackSecret: string;
    startsAt: Date;
    expiresAt: Date;
  }): Promise<GeofencingSubscriptionRecord | null> {
    const result = await this.database.query<SubscriptionRow>(
      `INSERT INTO geofencing_subscriptions (user_quest_id, place_id, callback_secret, starts_at, expires_at)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (user_quest_id) DO NOTHING
       RETURNING *`,
      [input.userQuestId, input.placeId, input.callbackSecret, input.startsAt, input.expiresAt],
    );
    return result.rows[0] ? this.map(result.rows[0]) : null;
  }

  async markActive(id: string, providerSubscriptionIds: readonly string[]): Promise<void> {
    await this.database.query(
      `UPDATE geofencing_subscriptions
       SET status = 'active', provider_subscription_id = $2, provider_subscription_ids = $3::text[]
       WHERE id = $1`,
      [id, providerSubscriptionIds[0] ?? null, providerSubscriptionIds],
    );
  }

  async markFailed(id: string, reason: string): Promise<void> {
    await this.database.query(
      `UPDATE geofencing_subscriptions SET status = 'failed', failure_reason = $2 WHERE id = $1`,
      [id, reason.slice(0, 500)],
    );
  }

  async findById(id: string): Promise<GeofencingSubscriptionRecord | null> {
    const result = await this.database.query<SubscriptionRow>(
      'SELECT * FROM geofencing_subscriptions WHERE id = $1',
      [id],
    );
    return result.rows[0] ? this.map(result.rows[0]) : null;
  }

  async findByUserQuest(userQuestId: string): Promise<GeofencingSubscriptionRecord | null> {
    const result = await this.database.query<SubscriptionRow>(
      'SELECT * FROM geofencing_subscriptions WHERE user_quest_id = $1',
      [userQuestId],
    );
    return result.rows[0] ? this.map(result.rows[0]) : null;
  }

  /// Idempotent on the provider's own event id where one is supplied, so a
  /// redelivered notification is not counted twice.
  async recordEvent(input: {
    subscriptionId: string;
    type: 'ENTER' | 'EXIT';
    occurredAt: Date;
    providerEventId?: string;
  }): Promise<void> {
    await this.database.query(
      `INSERT INTO geofencing_events (subscription_id, event_type, occurred_at, provider_event_id)
       VALUES ($1, $2, $3, $4)
       ON CONFLICT (subscription_id, provider_event_id) WHERE provider_event_id IS NOT NULL DO NOTHING`,
      [input.subscriptionId, input.type, input.occurredAt, input.providerEventId ?? null],
    );
  }

  /// Events inside the quest's own window only. `windowEnd` is the
  /// submission time, so entering the area after submitting proof is not
  /// treated as evidence for that proof.
  async eventsInWindow(
    userQuestId: string,
    windowStart: Date,
    windowEnd: Date,
  ): Promise<readonly GeofencingEventRecord[]> {
    const result = await this.database.query<{ event_type: 'ENTER' | 'EXIT'; occurred_at: Date }>(
      `SELECT event.event_type, event.occurred_at
       FROM geofencing_events event
       JOIN geofencing_subscriptions subscription ON subscription.id = event.subscription_id
       WHERE subscription.user_quest_id = $1
         AND event.occurred_at >= $2 AND event.occurred_at <= $3
       ORDER BY event.occurred_at`,
      [userQuestId, windowStart, windowEnd],
    );
    return result.rows.map((row) => ({ type: row.event_type, occurredAt: row.occurred_at }));
  }

  private map(row: SubscriptionRow): GeofencingSubscriptionRecord {
    return {
      id: row.id,
      userQuestId: row.user_quest_id,
      placeId: row.place_id,
      providerSubscriptionId: row.provider_subscription_id,
      providerSubscriptionIds: row.provider_subscription_ids ?? (row.provider_subscription_id ? [row.provider_subscription_id] : []),
      status: row.status,
      callbackSecret: row.callback_secret,
      startsAt: row.starts_at,
      expiresAt: row.expires_at,
    };
  }
}
