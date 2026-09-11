import { Injectable, Logger } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { JourneyRepository } from '../infrastructure/journey.repository.js';

/**
 * Advances a journey when a checkpoint is approved.
 *
 * ONE handler, deliberately. The agent's decision and a moderator's click
 * both land in `submissions.approve(...)` — the agent passes a null actor —
 * and both therefore emit the same `submission.approved`. Building separate
 * "AI unlock" and "moderator unlock" paths would be two implementations of
 * one rule, free to drift, and the appeal case would belong to neither.
 *
 * Driven from the transactional outbox rather than from inside the approval
 * transaction. Approval is durable the moment it commits; progression is
 * guaranteed to follow because the event cannot be lost, and is safe to
 * retry because every write here is idempotent. Reaching across modules to
 * share a transaction would buy literal atomicity at the cost of coupling
 * submissions to quests, which this codebase deliberately avoids.
 */
@Injectable()
export class JourneyProgressionService {
  private readonly logger = new Logger(JourneyProgressionService.name);

  constructor(
    private readonly database: DatabaseService,
    private readonly journeys: JourneyRepository,
  ) {}

  /**
   * Called for every approved submission. A no-op unless the quest is part
   * of a chain, which is the overwhelming majority of approvals.
   *
   * Returns what it did, so the caller can notify without re-deriving it.
   */
  async onSubmissionApproved(questId: string, userId: string): Promise<
    | { kind: 'not-a-chain' }
    | { kind: 'already-processed' }
    | { kind: 'stage-unlocked'; runId: string; stepOrder: number; nextQuestId: string; targetUserId: string; chainName: string }
    | { kind: 'journey-completed'; runId: string; chainName: string }
  > {
    const step = await this.journeys.stepFor(questId);
    if (!step) return { kind: 'not-a-chain' };

    return this.database.transaction(async (transaction) => {
      let run = await this.journeys.liveRunFor(userId, step.chain_id, transaction);
      if (!run) {
        // A step-1 assignment that predates the run table, or one made
        // between the migration and this deploy. Opening the run here keeps
        // it from becoming a dead end; the backfill covers the rest.
        if (step.step_order !== 1 || step.mode !== 'solo') {
          this.logger.warn(
            { questId, userId, chainId: step.chain_id, stepOrder: step.step_order },
            'Approved chain step has no live run and cannot be adopted',
          );
          return { kind: 'not-a-chain' as const };
        }
        const runId = await this.journeys.createSoloRun(userId, step.chain_id, transaction);
        run = { id: runId, run_kind: 'solo', status: 'active' };
      }

      const chain = await this.database.query<{ name: string }>(
        `SELECT name FROM quest_chains WHERE id = $1`, [step.chain_id], transaction,
      );
      const chainName = chain.rows[0]?.name ?? 'Journey';

      const remaining = await this.journeys.unapprovedSteps(run.id, transaction);
      if (remaining.length === 0) {
        const closed = await this.journeys.completeRun(run.id, transaction);
        return closed
          ? { kind: 'journey-completed' as const, runId: run.id, chainName }
          : { kind: 'already-processed' as const };
      }

      // Which checkpoint opens now depends on the chain's rule, and only
      // here. A sequential chain opens the next one; an all_steps_any_order
      // chain opened everything when the run began and has nothing to add,
      // which is what keeps a cross-country challenge from making Palestine
      // wait for Lebanon.
      if (step.completion_rule === 'all_steps_any_order') {
        return { kind: 'already-processed' as const };
      }

      const next = remaining[0];
      const targetUserId = run.run_kind === 'group'
        ? await this.journeys.targetForStep(run.id, step.chain_id, next.step_order, transaction)
        : userId;
      if (!targetUserId) {
        this.logger.warn({ runId: run.id, stepOrder: next.step_order }, 'No participant owns the next checkpoint');
        return { kind: 'already-processed' as const };
      }

      const opened = await this.journeys.recordUnlock(
        run.id, next.step_order, next.quest_id, targetUserId, transaction,
      );
      // Already open: a replayed event, or the backfill got there first.
      // Either way there is nothing new to announce.
      if (!opened) return { kind: 'already-processed' as const };

      return {
        kind: 'stage-unlocked' as const,
        runId: run.id,
        stepOrder: next.step_order,
        nextQuestId: next.quest_id,
        targetUserId,
        chainName,
      };
    });
  }
}
