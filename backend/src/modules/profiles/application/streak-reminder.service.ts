import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { Environment } from '../../../config/environment.js';

export interface StreakReminderOutcome {
  readonly reminded: number;
}

/// Warns users whose streak dies at the end of today (#46).
///
/// "At risk" is a precise state: the last approved submission day is
/// yesterday. Today's streak is already safe, and a streak that lapsed two or
/// more days ago is gone — reminding either group is noise.
///
/// Idempotent by date, not by job run. `profiles.streak_reminder_sent_on`
/// holds the UTC date of the last reminder, so retries, overlapping runs and
/// an hourly cadence all still produce one message per user per day.
@Injectable()
export class StreakReminderService {
  private readonly logger = new Logger(StreakReminderService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly config: ConfigService<Environment, true>,
  ) {}

  async sweep(): Promise<StreakReminderOutcome> {
    const batchSize = this.config.get('STREAK_REMINDER_BATCH_SIZE', { infer: true });

    // One statement so the claim and the notification cannot diverge: a
    // crash between "sent" and "notified" would silently cost a user their
    // only warning, and there is no way to detect that afterwards.
    const result = await this.database.query<{ user_id: string; streak: number }>(
      `WITH days AS (
         SELECT s.user_id, (s.submitted_at AT TIME ZONE 'UTC')::date AS d
         FROM submissions s
         WHERE s.status = 'approved' AND s.visibility <> 'deleted'
         GROUP BY s.user_id, (s.submitted_at AT TIME ZONE 'UTC')::date
       ),
       grouped AS (
         SELECT user_id, d,
                d - (row_number() OVER (PARTITION BY user_id ORDER BY d))::int AS grp
         FROM days
       ),
       runs AS (
         SELECT user_id, count(*)::int AS len, max(d) AS last_day
         FROM grouped GROUP BY user_id, grp
       ),
       at_risk AS (
         SELECT r.user_id, r.len AS streak
         FROM runs r
         JOIN profiles p ON p.id = r.user_id
         -- Alive, but its last day is yesterday: it expires tonight.
         WHERE r.last_day = (now() AT TIME ZONE 'UTC')::date - 1
           AND (p.streak_reminder_sent_on IS DISTINCT FROM (now() AT TIME ZONE 'UTC')::date)
           -- A suspended or banned account cannot act on the reminder, and
           -- the app hides the quest surfaces from them entirely.
           AND EXISTS (SELECT 1 FROM users u WHERE u.id = p.id AND u.status = 'active')
         LIMIT $1
       ),
       claimed AS (
         UPDATE profiles p
            SET streak_reminder_sent_on = (now() AT TIME ZONE 'UTC')::date
           FROM at_risk a
          WHERE p.id = a.user_id
         RETURNING p.id AS user_id, a.streak
       )
       INSERT INTO notifications (user_id, type, title, body, reference_id)
       SELECT c.user_id,
              'streak_at_risk',
              CASE WHEN c.streak = 1
                   THEN 'Your streak dies tonight. 🔥'
                   ELSE format('Your %s-day streak dies tonight. 🔥', c.streak) END,
              'Finish a quest today to keep it alive.',
              NULL
       FROM claimed c
       RETURNING user_id, 0 AS streak`,
      [batchSize],
    );

    const reminded = result.rowCount ?? 0;
    if (reminded > 0) {
      this.logger.log({ reminded, batchSize }, 'Sent streak-at-risk reminders');
    }
    return { reminded };
  }
}
