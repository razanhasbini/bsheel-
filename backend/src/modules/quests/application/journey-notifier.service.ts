import { Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';

/** Structured types, so the app can route a tap rather than parse a string. */
export const JOURNEY_NOTIFICATION = {
  stageUnlocked: 'journey_stage_unlocked',
  teammateAdvanced: 'journey_teammate_advanced',
  completed: 'journey_completed',
  hiddenDiscovered: 'hidden_quest_discovered',
} as const;

/**
 * Tells people their journey moved.
 *
 * Uses the existing notifications table and its outbox delivery — the type
 * column is free-form text, so new semantic types need no migration. Every
 * row is written with the reference id of the RUN, so opening the
 * notification lands on the journey rather than on a bare quest.
 */
@Injectable()
export class JourneyNotifier {
  constructor(private readonly database: DatabaseService) {}

  /**
   * The unlock announcement.
   *
   * On a relay two different people need two different messages: whoever is
   * up next needs to know it is their turn, and whoever just cleared a
   * checkpoint needs to know the baton moved rather than being met with
   * silence. The teammate message deliberately carries a name and no
   * content — a hidden checkpoint's instructions belong to its target only.
   */
  async announceUnlock(
    unlock: { runId: string; stepOrder: number; targetUserId: string; chainName: string },
    approvedUserId: string,
  ): Promise<void> {
    await this.insert(
      unlock.targetUserId,
      'Checkpoint unlocked 🎯',
      `Stage ${unlock.stepOrder} of ${unlock.chainName} is ready for you.`,
      JOURNEY_NOTIFICATION.stageUnlocked,
      unlock.runId,
    );
    if (unlock.targetUserId === approvedUserId) return;

    const name = await this.displayName(unlock.targetUserId);
    await this.insert(
      approvedUserId,
      'Checkpoint cleared ✅',
      `You cleared your checkpoint on ${unlock.chainName}. ${name} is up next.`,
      JOURNEY_NOTIFICATION.teammateAdvanced,
      unlock.runId,
    );
  }

  /** Everyone who walked it hears that it is finished. */
  async announceCompletion(runId: string, chainName: string): Promise<void> {
    const people = await this.database.query<{ user_id: string }>(
      `SELECT owner_user_id AS user_id FROM quest_chain_runs
       WHERE id = $1 AND owner_user_id IS NOT NULL
       UNION
       SELECT user_id FROM quest_chain_run_participants WHERE chain_run_id = $1`,
      [runId],
    );
    for (const person of people.rows) {
      await this.insert(
        person.user_id,
        'Journey complete 🏁',
        `Every checkpoint on ${chainName} is verified. That is the whole route walked.`,
        JOURNEY_NOTIFICATION.completed,
        runId,
      );
    }
  }

  /**
   * The discovery moment for a hidden quest.
   *
   * References the QUEST rather than a run: a hidden quest is not
   * necessarily part of a journey, and the tap should land on the thing
   * that just opened.
   */
  async announceHiddenUnlock(userId: string, title: string, questId: string): Promise<void> {
    await this.insert(
      userId,
      'You found something 🔓',
      `"${title}" just opened for you.`,
      JOURNEY_NOTIFICATION.hiddenDiscovered,
      questId,
    );
  }

  private async displayName(userId: string): Promise<string> {
    const result = await this.database.query<{ name: string }>(
      `SELECT COALESCE(NULLIF(display_name, ''), username::text, 'Someone') AS name
       FROM profiles WHERE id = $1`,
      [userId],
    );
    return result.rows[0]?.name ?? 'Someone';
  }

  private async insert(
    userId: string, title: string, body: string, type: string, referenceId: string,
  ): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const row = await transaction.query<{ id: string }>(
        `INSERT INTO notifications (user_id, title, body, type, reference_id)
         VALUES ($1, $2, $3, $4, $5) RETURNING id`,
        [userId, title, body, type, referenceId],
      );
      // Delivery rides the same outbox every other notification uses.
      await transaction.query(
        `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
         VALUES ('notification', $1, 'notification.created', $2::jsonb)`,
        [row.rows[0].id, JSON.stringify({ notificationId: row.rows[0].id, userId })],
      );
    });
  }
}
