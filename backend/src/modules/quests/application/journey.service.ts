import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import { JourneyRepository } from '../infrastructure/journey.repository.js';
import { QuestsRepository } from '../infrastructure/quests.repository.js';
import type { JourneyRun } from '../domain/journey.types.js';

/**
 * The journey product surface: read where you are, and take the next step.
 *
 * Continue deliberately owns no assignment logic of its own. It checks that
 * the caller is entitled to this checkpoint and then calls the same
 * `assignSpecific` every other assignment goes through, so the one-active-
 * quest index, the reroll cap, the cooldown and the destination rules stay
 * in exactly one place. A second assignment path is how those rules drift.
 */
@Injectable()
export class JourneyService {
  constructor(
    private readonly database: DatabaseService,
    private readonly journeys: JourneyRepository,
    private readonly quests: QuestsRepository,
  ) {}

  activeFor(userId: string): Promise<readonly JourneyRun[]> {
    return this.journeys.activeRunsFor(userId);
  }

  async detail(runId: string, userId: string): Promise<JourneyRun> {
    const run = await this.journeys.runFor(runId, userId);
    if (!run) throw new NotFoundException({ code: 'JOURNEY_NOT_FOUND', message: 'No such journey' });
    return run;
  }

  /**
   * Starts the checkpoint that is open for this caller.
   *
   * This is the only moment a journey's timer begins. Unlocking deliberately
   * does not: a checkpoint approved while its owner slept would otherwise
   * have been burning their clock before they knew it existed.
   */
  async continueJourney(runId: string, userId: string, questId?: string) {
    const unlock = await this.database.query<{ quest_id: string; step_order: number }>(
      `SELECT u.quest_id, u.step_order
       FROM journey_stage_unlocks u
       JOIN quest_chain_runs r ON r.id = u.chain_run_id
       WHERE u.chain_run_id = $1
         AND u.target_user_id = $2
         AND r.status = 'active'
         AND ($3::uuid IS NULL OR u.quest_id = $3)
         -- Already finished or awaiting a decision: there is nothing to
         -- start. An expired or rejected attempt is absent from this test on
         -- purpose, because those stay retryable like any other quest.
         AND NOT EXISTS (
           SELECT 1 FROM user_quests uq
           WHERE uq.quest_id = u.quest_id AND uq.user_id = $2
             AND uq.status IN ('assigned', 'submitted', 'approved')
         )
       ORDER BY u.step_order
       LIMIT 1`,
      [runId, userId, questId ?? null],
    );

    const row = unlock.rows[0];
    if (!row) {
      // One code for "not yours", "not unlocked" and "already under way".
      // Distinguishing them would tell a non-participant which checkpoints
      // exist and who holds them.
      throw new ConflictException({
        code: 'NO_CHECKPOINT_AVAILABLE',
        message: 'There is no checkpoint ready for you on this journey',
      });
    }

    // The existing flow: locks the user, enforces the one-active-quest
    // index, sets expires_at, and stamps journey_stage_unlocks.started_at.
    const assignment = await this.quests.assignSpecific(userId, row.quest_id);
    return { assignment, stepOrder: row.step_order };
  }

  /** Marks this viewer's unlocks on a run seen, so the animation plays once. */
  async acknowledgeUnlock(runId: string, userId: string): Promise<void> {
    await this.journeys.markUnlockSeen(runId, userId);
  }

  // ── Relay lifecycle ──────────────────────────────────────────────────

  /**
   * Opens a relay and puts the creator at position 1.
   *
   * The run starts `forming`, with nothing unlocked: a relay cannot begin
   * until its roster exists, because who owns stage 2 is a question about
   * the roster. Participants join themselves with the code — nobody is
   * conscripted into a journey by another user naming them.
   */
  async createGroupRun(chainId: string, creatorId: string) {
    const chain = await this.database.query<{ mode: string; name: string }>(
      `SELECT mode, name FROM quest_chains WHERE id = $1 AND is_active`, [chainId],
    );
    if (!chain.rows[0]) throw new NotFoundException({ code: 'CHAIN_NOT_FOUND', message: 'No such journey' });
    if (chain.rows[0].mode !== 'group') {
      throw new BadRequestException({
        code: 'CHAIN_NOT_A_RELAY',
        message: 'This journey is walked alone — just start its first checkpoint',
      });
    }
    return this.database.transaction(async (transaction) => {
      const run = await transaction.query<{ id: string; join_code: string }>(
        `INSERT INTO quest_chain_runs (chain_id, run_kind, created_by_user_id, join_code, status)
         VALUES ($1, 'group', $2, $3, 'forming')
         RETURNING id, join_code`,
        [chainId, creatorId, this.journeys.newJoinCode()],
      );
      await transaction.query(
        `INSERT INTO quest_chain_run_participants (chain_run_id, user_id, position)
         VALUES ($1, $2, 1)`,
        [run.rows[0].id, creatorId],
      );
      return { runId: run.rows[0].id, joinCode: run.rows[0].join_code, title: chain.rows[0].name };
    });
  }

  /** The caller adds THEMSELVES to a forming relay. */
  async joinGroupRun(joinCode: string, userId: string) {
    return this.database.transaction(async (transaction) => {
      const run = await transaction.query<{ id: string; status: string }>(
        `SELECT id, status FROM quest_chain_runs WHERE join_code = $1 FOR UPDATE`,
        [joinCode.trim()],
      );
      if (!run.rows[0]) throw new NotFoundException({ code: 'RUN_NOT_FOUND', message: 'No journey with that code' });
      if (run.rows[0].status !== 'forming') {
        throw new ConflictException({ code: 'RUN_ALREADY_STARTED', message: 'That journey has already begun' });
      }
      const next = await transaction.query<{ position: number }>(
        `SELECT COALESCE(max(position), 0) + 1 AS position
         FROM quest_chain_run_participants WHERE chain_run_id = $1`,
        [run.rows[0].id],
      );
      await transaction.query(
        `INSERT INTO quest_chain_run_participants (chain_run_id, user_id, position)
         VALUES ($1, $2, $3) ON CONFLICT DO NOTHING`,
        [run.rows[0].id, userId, next.rows[0].position],
      );
      return { runId: run.rows[0].id };
    });
  }

  async roster(runId: string, userId: string) {
    const rows = await this.database.query<{ user_id: string; username: string; position: number }>(
      `SELECT p.user_id, pr.username::text, p.position
       FROM quest_chain_run_participants p
       JOIN profiles pr ON pr.id = p.user_id
       WHERE p.chain_run_id = $1 ORDER BY p.position`,
      [runId],
    );
    if (!rows.rows.some((r) => r.user_id === userId)) {
      throw new ForbiddenException({ code: 'NOT_A_PARTICIPANT', message: 'You are not on this journey' });
    }
    return rows.rows;
  }

  /**
   * Finalises the roster and opens the first checkpoint.
   *
   * Authored target positions are validated against the roster HERE, before
   * anybody invests a step, rather than being discovered halfway through a
   * relay when stage 3 turns out to belong to a participant who never
   * joined.
   */
  async startGroupRun(runId: string, userId: string) {
    return this.database.transaction(async (transaction) => {
      const run = await transaction.query<{ chain_id: string; status: string; created_by_user_id: string }>(
        `SELECT chain_id, status, created_by_user_id FROM quest_chain_runs
         WHERE id = $1 AND run_kind = 'group' FOR UPDATE`,
        [runId],
      );
      if (!run.rows[0]) throw new NotFoundException({ code: 'RUN_NOT_FOUND', message: 'No such journey' });
      if (run.rows[0].created_by_user_id !== userId) {
        throw new ForbiddenException({ code: 'NOT_RUN_CREATOR', message: 'Only whoever opened this relay can start it' });
      }
      if (run.rows[0].status !== 'forming') {
        throw new ConflictException({ code: 'RUN_ALREADY_STARTED', message: 'That journey has already begun' });
      }

      const roster = await transaction.query<{ user_id: string; position: number }>(
        `SELECT user_id, position FROM quest_chain_run_participants
         WHERE chain_run_id = $1 ORDER BY position`,
        [runId],
      );
      if (roster.rows.length < 2) {
        throw new BadRequestException({
          code: 'ROSTER_TOO_SMALL',
          message: 'A relay needs at least two people',
        });
      }

      const steps = await transaction.query<{ step_order: number; quest_id: string; target_position: number | null }>(
        `SELECT step_order, quest_id, target_position FROM quest_chain_steps
         WHERE chain_id = $1 ORDER BY step_order`,
        [run.rows[0].chain_id],
      );
      const overflowing = steps.rows.find(
        (s) => s.target_position !== null && s.target_position > roster.rows.length,
      );
      if (overflowing) {
        throw new BadRequestException({
          code: 'TARGET_POSITION_OUT_OF_RANGE',
          message: `Stage ${overflowing.step_order} is assigned to participant ${overflowing.target_position}, but this relay has ${roster.rows.length}`,
        });
      }

      const first = steps.rows[0];
      const position = first.target_position ?? 1;
      const target = roster.rows.find((r) => r.position === position);
      if (!target) {
        throw new BadRequestException({ code: 'TARGET_POSITION_OUT_OF_RANGE', message: 'Nobody holds the first checkpoint' });
      }

      await transaction.query(
        `UPDATE quest_chain_runs SET status = 'active', started_at = now(), updated_at = now()
         WHERE id = $1`,
        [runId],
      );
      await transaction.query(
        `INSERT INTO journey_stage_unlocks (chain_run_id, step_order, quest_id, target_user_id)
         VALUES ($1, $2, $3, $4) ON CONFLICT DO NOTHING`,
        [runId, first.step_order, first.quest_id, target.user_id],
      );
      return { runId, firstTargetUserId: target.user_id };
    });
  }
}
