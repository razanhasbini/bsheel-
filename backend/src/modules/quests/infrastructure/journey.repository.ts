import { BadRequestException, Injectable } from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { DatabaseTransaction } from '../../../infrastructure/database/database.service.js';


interface ChainRow {
  chain_id: string; mode: 'solo' | 'group';
  completion_rule: 'sequential' | 'all_steps_any_order';
  step_order: number;
}

/**
 * Reads and writes for chain runs — the parent journey state.
 *
 * Progress is derived, never stored: a sequential run has a meaningful
 * current step and an all_steps_any_order run genuinely does not, so a
 * `current_step` column would be honest for one rule and a lie for the
 * other. What IS stored is the durable unlock, because "this checkpoint
 * opened for this person in this run" is a fact that must survive the app
 * being closed and must not be recomputable into non-existence.
 */
@Injectable()
export class JourneyRepository {
  constructor(private readonly database: DatabaseService) {}

  /** The chain step a quest belongs to, if any. */
  async stepFor(questId: string, transaction?: DatabaseTransaction): Promise<ChainRow | null> {
    const result = await this.database.query<ChainRow>(
      `SELECT cs.chain_id, ch.mode, ch.completion_rule, cs.step_order
       FROM quest_chain_steps cs JOIN quest_chains ch ON ch.id = cs.chain_id
       WHERE cs.quest_id = $1 AND ch.is_active`,
      [questId], transaction,
    );
    return result.rows[0] ?? null;
  }

  /**
   * The live run a user is walking for a chain.
   *
   * A relay is found through the roster rather than through an owner, which
   * is the whole reason the roster belongs to the run: the shared journey
   * has no single owner to look it up by.
   */
  async liveRunFor(userId: string, chainId: string, transaction?: DatabaseTransaction) {
    const result = await this.database.query<{ id: string; run_kind: 'solo' | 'group'; status: string }>(
      `SELECT r.id, r.run_kind, r.status FROM quest_chain_runs r
       WHERE r.chain_id = $2 AND r.status IN ('forming', 'active')
         AND (r.owner_user_id = $1 OR EXISTS (
           SELECT 1 FROM quest_chain_run_participants p
           WHERE p.chain_run_id = r.id AND p.user_id = $1))
       LIMIT 1`,
      [userId, chainId], transaction,
    );
    return result.rows[0] ?? null;
  }

  /**
   * Opens a solo run for a chain the user is starting.
   *
   * Solo only, and the caller must have checked the chain's mode. A group
   * chain reaching here would produce a run_kind that disagrees with its
   * chain definition, which is the drift the snapshot column exists to
   * prevent — so it is refused rather than coerced.
   */
  async createSoloRun(userId: string, chainId: string, transaction: DatabaseTransaction): Promise<string> {
    const mode = await this.database.query<{ mode: string }>(
      `SELECT mode FROM quest_chains WHERE id = $1`, [chainId], transaction,
    );
    if (mode.rows[0]?.mode !== 'solo') {
      throw new BadRequestException({
        code: 'CHAIN_RUN_REQUIRED',
        message: 'This journey is a relay — start it with a group run and a roster',
      });
    }
    const run = await this.database.query<{ id: string }>(
      `INSERT INTO quest_chain_runs (chain_id, run_kind, owner_user_id, created_by_user_id, status, started_at)
       VALUES ($1, 'solo', $2, $2, 'active', now())
       ON CONFLICT DO NOTHING
       RETURNING id`,
      [chainId, userId], transaction,
    );
    if (run.rows[0]) return run.rows[0].id;
    const existing = await this.liveRunFor(userId, chainId, transaction);
    if (!existing) throw new BadRequestException({ code: 'CHAIN_RUN_UNAVAILABLE', message: 'Could not open this journey' });
    return existing.id;
  }

  /**
   * Records that a checkpoint opened, once.
   *
   * The primary key carries the idempotency: a replayed approval event
   * inserts nothing and returns nothing, so a duplicate cannot produce a
   * second unlock, a second notification or a second assignment.
   * Returns true only on the insert that actually opened it.
   */
  async recordUnlock(
    chainRunId: string, stepOrder: number, questId: string, targetUserId: string,
    transaction?: DatabaseTransaction,
  ): Promise<boolean> {
    const result = await this.database.query(
      `INSERT INTO journey_stage_unlocks (chain_run_id, step_order, quest_id, target_user_id)
       VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING RETURNING 1`,
      [chainRunId, stepOrder, questId, targetUserId], transaction,
    );
    return result.rowCount === 1;
  }

  /**
   * Who owns a step of a relay.
   *
   * An authored `target_position` wins; otherwise round-robin. Round-robin
   * is the default nobody has to configure, not the only possible semantics
   * — an asymmetric relay, a stage bound to a country, or a sequence where
   * one participant acts twice all need the override.
   */
  async targetForStep(
    chainRunId: string, chainId: string, stepOrder: number, transaction?: DatabaseTransaction,
  ): Promise<string | null> {
    const roster = await this.database.query<{ user_id: string; position: number }>(
      `SELECT user_id, position FROM quest_chain_run_participants
       WHERE chain_run_id = $1 ORDER BY position`,
      [chainRunId], transaction,
    );
    if (roster.rows.length === 0) return null;
    const authored = await this.database.query<{ target_position: number | null }>(
      `SELECT target_position FROM quest_chain_steps WHERE chain_id = $1 AND step_order = $2`,
      [chainId, stepOrder], transaction,
    );
    const explicit = authored.rows[0]?.target_position ?? null;
    const position = explicit ?? ((stepOrder - 1) % roster.rows.length) + 1;
    return roster.rows.find((r) => r.position === position)?.user_id ?? null;
  }

  /** Steps of a chain that this run has not had approved yet. */
  async unapprovedSteps(chainRunId: string, transaction?: DatabaseTransaction) {
    const result = await this.database.query<{ step_order: number; quest_id: string }>(
      `SELECT cs.step_order, cs.quest_id
       FROM quest_chain_runs r
       JOIN quest_chain_steps cs ON cs.chain_id = r.chain_id
       WHERE r.id = $1 AND NOT EXISTS (
         SELECT 1 FROM user_quests uq
         WHERE uq.quest_id = cs.quest_id AND uq.status = 'approved'
           AND (uq.user_id = r.owner_user_id OR EXISTS (
             SELECT 1 FROM quest_chain_run_participants p
             WHERE p.chain_run_id = r.id AND p.user_id = uq.user_id))
       )
       ORDER BY cs.step_order`,
      [chainRunId], transaction,
    );
    return result.rows;
  }

  async completeRun(chainRunId: string, transaction?: DatabaseTransaction): Promise<boolean> {
    const result = await this.database.query(
      `UPDATE quest_chain_runs SET status = 'completed', completed_at = now(), updated_at = now()
       WHERE id = $1 AND status = 'active' RETURNING 1`,
      [chainRunId], transaction,
    );
    return result.rowCount === 1;
  }

  /** Stamps the first start of a checkpoint. Audit only — never a gate. */
  async markStarted(questId: string, userId: string, transaction?: DatabaseTransaction): Promise<void> {
    await this.database.query(
      `UPDATE journey_stage_unlocks SET started_at = COALESCE(started_at, now())
       WHERE quest_id = $1 AND target_user_id = $2`,
      [questId, userId], transaction,
    );
  }

  async markUnlockSeen(chainRunId: string, userId: string): Promise<void> {
    await this.database.query(
      `UPDATE journey_stage_unlocks SET seen_at = now()
       WHERE chain_run_id = $1 AND target_user_id = $2 AND seen_at IS NULL`,
      [chainRunId, userId],
    );
  }

  newJoinCode(): string {
    return randomBytes(4).toString('hex').toUpperCase();
  }
}
