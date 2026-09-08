import { DatabaseService } from '../../../infrastructure/database/database.service.js';

/** Shared transactional audit primitive; domain operations remain in focused repositories. */
export abstract class AdminRepositoryBase {
  constructor(protected readonly database: DatabaseService) {}

  protected async audit(
    actorId: string,
    action: string,
    targetType: string,
    targetId: string | null,
    before: unknown,
    after: unknown,
    transaction: import('../../../infrastructure/database/database.service.js').DatabaseTransaction,
  ) {
    await transaction.query(
      `INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, before_state, after_state)
       VALUES ($1, $2, $3, $4, $5::jsonb, $6::jsonb)`,
      [
        actorId,
        action,
        targetType,
        targetId,
        before === null ? null : JSON.stringify(before),
        after === null ? null : JSON.stringify(after),
      ],
    );
  }
}
