import { ConflictException, Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import type { Environment } from '../../../config/environment.js';
import type { DatabaseTransaction } from '../../../infrastructure/database/database.service.js';

/** The shipped wait between quest assignments; overridable per deployment. */
export const DEFAULT_QUEST_ASSIGNMENT_COOLDOWN_SECONDS = 30;

@Injectable()
export class QuestAssignmentPolicyRepository {
  constructor(private readonly config: ConfigService<Environment, true>) {}

  async lockUser(
    userId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
      [userId],
    );
  }

  /**
   * Anti-abuse on quest intake: a player cannot take a new quest within the
   * cooldown of their last one.
   *
   * A cooldown of 0 disables the check outright rather than running a query
   * whose window is empty — that is the e2e suite's configuration, and it
   * also means an operator who sets 0 pays nothing for it.
   */
  async assertCooldownElapsed(
    userId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const seconds = this.config.get('QUEST_ASSIGNMENT_COOLDOWN_SECONDS', { infer: true });
    if (seconds <= 0) return;

    const recent = await transaction.query(
      `SELECT 1 FROM user_quests
       WHERE user_id = $1
         AND status IN ('assigned', 'submitted')
         AND assigned_at > now() - make_interval(secs => $2)
       LIMIT 1`,
      [userId, seconds],
    );
    if (recent.rowCount) {
      throw new ConflictException({
        code: 'QUEST_ASSIGNMENT_COOLDOWN',
        message: `Please wait ${seconds} seconds before getting another quest`,
      });
    }
  }
}
