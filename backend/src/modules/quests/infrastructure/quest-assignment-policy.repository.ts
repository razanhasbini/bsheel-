import { ConflictException, Injectable } from '@nestjs/common';
import type { DatabaseTransaction } from '../../../infrastructure/database/database.service.js';

export const QUEST_ASSIGNMENT_COOLDOWN_SECONDS = 30;

@Injectable()
export class QuestAssignmentPolicyRepository {
  async lockUser(
    userId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      'SELECT pg_advisory_xact_lock(hashtextextended($1, 0))',
      [userId],
    );
  }

  async assertCooldownElapsed(
    userId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const recent = await transaction.query(
      `SELECT 1 FROM user_quests
       WHERE user_id = $1
         AND status IN ('assigned', 'submitted')
         AND assigned_at > now() - make_interval(secs => $2)
       LIMIT 1`,
      [userId, QUEST_ASSIGNMENT_COOLDOWN_SECONDS],
    );
    if (recent.rowCount) {
      throw new ConflictException({
        code: 'QUEST_ASSIGNMENT_COOLDOWN',
        message: 'Please wait 30 seconds before getting another quest',
      });
    }
  }
}
