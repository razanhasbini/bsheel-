import { BadRequestException, Injectable } from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { JourneyRun, JourneyStage, StageState } from '../domain/journey.types.js';
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
/**
 * Whether any checkpoint of this run has been submitted yet.
 *
 * The client needs it to know whether the feed choice is still open: the
 * server refuses a change once a stop exists, and a sheet that can only be
 * refused should not be offered. Written once and used by both projections
 * so the two can never disagree about what "still choosable" means.
 */
const hasSubmissions = `EXISTS (
  SELECT 1 FROM quest_chain_steps cs2
  JOIN user_quests uq2 ON uq2.quest_id = cs2.quest_id
  JOIN submissions s2 ON s2.user_quest_id = uq2.id
  WHERE cs2.chain_id = r.chain_id AND s2.deleted_at IS NULL)`;

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
   * The feed choice for the run a quest belongs to, for this user.
   *
   * Answers one question at submission time — may this checkpoint go to the
   * feed on its own — so the caller does not have to know what a chain is.
   * Null run, null mode and 'per_stop' all mean the same thing here: post it.
   * Only an explicit 'one_post' withholds.
   */
  async withholdsFromFeed(
    questId: string, userId: string, transaction?: DatabaseTransaction,
  ): Promise<boolean> {
    const result = await this.database.query<{ feed_mode: string | null }>(
      `SELECT r.feed_mode
       FROM quest_chain_steps s
       JOIN quest_chain_runs r ON r.chain_id = s.chain_id
       WHERE s.quest_id = $1 AND r.status IN ('forming', 'active')
         AND (r.owner_user_id = $2 OR EXISTS (
           SELECT 1 FROM quest_chain_run_participants p
           WHERE p.chain_run_id = r.id AND p.user_id = $2))
       LIMIT 1`,
      [questId, userId], transaction,
    );
    return result.rows[0]?.feed_mode === 'one_post';
  }

  /**
   * Records the player's choice for a run, once and early.
   *
   * Refused after the first checkpoint has been submitted, because by then
   * the choice has already been acted on: a stop posted per-stop cannot be
   * un-posted by a later change of mind, and one withheld cannot be posted
   * on its own without the route around it. Offering a setting that silently
   * does not apply to what already happened is worse than not offering it.
   *
   * Returns false when the run is not the caller's, is finished, or has
   * already been submitted to — all of which are "no" rather than errors.
   */
  async chooseFeedMode(
    runId: string, userId: string, mode: 'per_stop' | 'one_post',
  ): Promise<boolean> {
    const result = await this.database.query(
      `UPDATE quest_chain_runs r SET feed_mode = $3, updated_at = now()
       WHERE r.id = $1 AND r.status IN ('forming', 'active')
         AND (r.owner_user_id = $2 OR EXISTS (
           SELECT 1 FROM quest_chain_run_participants p
           WHERE p.chain_run_id = r.id AND p.user_id = $2))
         AND NOT EXISTS (
           SELECT 1 FROM quest_chain_steps s
           JOIN user_quests uq ON uq.quest_id = s.quest_id
           JOIN submissions sub ON sub.user_quest_id = uq.id
           WHERE s.chain_id = r.chain_id AND sub.deleted_at IS NULL)
       RETURNING r.id`,
      [runId, userId, mode],
    );
    return result.rowCount === 1;
  }

  /**
   * Turns a finished one_post run into a single feed post.
   *
   * The last checkpoint's submission becomes the anchor and the earlier ones
   * become its stops. Nothing is rewritten: the anchor's own media, caption
   * and verdict are untouched, and each stop stays an ordinary submission
   * that can be appealed, moderated or taken down on its own terms. The only
   * change to any row is the anchor's show_in_feed, which is the flag that
   * was holding the whole route back.
   *
   * Idempotent through journey_post_stops' unique key on (run, step): a
   * retried completion inserts nothing and leaves the post as it stands.
   * Returns the anchor id when this call is the one that published it.
   */
  async publishJourneyPost(
    chainRunId: string, transaction: DatabaseTransaction,
  ): Promise<string | null> {
    const stops = await this.database.query<{ submission_id: string; step_order: number }>(
      `SELECT sub.id AS submission_id, s.step_order
       FROM quest_chain_runs r
       JOIN quest_chain_steps s ON s.chain_id = r.chain_id
       JOIN user_quests uq ON uq.quest_id = s.quest_id
       JOIN submissions sub ON sub.user_quest_id = uq.id
       WHERE r.id = $1 AND sub.status = 'approved' AND sub.deleted_at IS NULL
         AND sub.visibility = 'visible' AND sub.moderation_removed_at IS NULL
         AND (r.owner_user_id IS NULL OR uq.user_id = r.owner_user_id)
       ORDER BY s.step_order`,
      [chainRunId], transaction,
    );
    if (stops.rows.length === 0) return null;

    // The last checkpoint anchors it: the route reaches the feed at the
    // moment it was finished, dated by its ending rather than its beginning.
    const anchor = stops.rows[stops.rows.length - 1];
    const inserted = await this.database.query(
      `INSERT INTO journey_post_stops (anchor_submission_id, stop_submission_id, chain_run_id, step_order)
       SELECT $1, unnest($2::uuid[]), $3, unnest($4::int[])
       ON CONFLICT DO NOTHING
       RETURNING stop_submission_id`,
      [
        anchor.submission_id,
        stops.rows.map((row) => row.submission_id),
        chainRunId,
        stops.rows.map((row) => row.step_order),
      ],
      transaction,
    );
    if (inserted.rowCount === 0) return null;

    await this.database.query(
      `UPDATE submissions SET show_in_feed = true, version = version + 1 WHERE id = $1`,
      [anchor.submission_id], transaction,
    );
    return anchor.submission_id;
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

  /**
   * Every live run this user is part of, projected for THEM.
   *
   * The visibility rules are applied here, in the projection, rather than
   * sent to the client to hide. A teammate watching a relay is told a
   * checkpoint is active and whose it is; a hidden checkpoint's instructions
   * reach its target and nobody else. Blurring on the client would ship the
   * secret to every device that asks.
   */
  async activeRunsFor(userId: string): Promise<readonly JourneyRun[]> {
    const runs = await this.database.query<{
      run_id: string; chain_id: string; name: string; description: string;
      run_kind: 'solo' | 'group'; completion_rule: 'sequential' | 'all_steps_any_order';
      status: JourneyRun['status']; feed_mode: 'per_stop' | 'one_post' | null;
      has_submissions: boolean;
    }>(
      `SELECT r.id AS run_id, r.chain_id, ch.name, ch.description,
              r.run_kind, ch.completion_rule, r.status, r.feed_mode,
              ${hasSubmissions} AS has_submissions
       FROM quest_chain_runs r
       JOIN quest_chains ch ON ch.id = r.chain_id
       WHERE r.status IN ('forming', 'active')
         AND (r.owner_user_id = $1 OR EXISTS (
           SELECT 1 FROM quest_chain_run_participants p
           WHERE p.chain_run_id = r.id AND p.user_id = $1))
       ORDER BY r.started_at DESC NULLS LAST`,
      [userId],
    );

    const out: JourneyRun[] = [];
    for (const run of runs.rows) out.push(await this.projectRun(run, userId));
    return out;
  }

  /** One run, projected for a viewer. Null when they are not part of it. */
  async runFor(runId: string, userId: string): Promise<JourneyRun | null> {
    const runs = await this.database.query<{
      run_id: string; chain_id: string; name: string; description: string;
      run_kind: 'solo' | 'group'; completion_rule: 'sequential' | 'all_steps_any_order';
      status: JourneyRun['status']; feed_mode: 'per_stop' | 'one_post' | null;
      has_submissions: boolean;
    }>(
      `SELECT r.id AS run_id, r.chain_id, ch.name, ch.description,
              r.run_kind, ch.completion_rule, r.status, r.feed_mode,
              ${hasSubmissions} AS has_submissions
       FROM quest_chain_runs r JOIN quest_chains ch ON ch.id = r.chain_id
       WHERE r.id = $2
         AND (r.owner_user_id = $1 OR EXISTS (
           SELECT 1 FROM quest_chain_run_participants p
           WHERE p.chain_run_id = r.id AND p.user_id = $1))`,
      [userId, runId],
    );
    return runs.rows[0] ? this.projectRun(runs.rows[0], userId) : null;
  }

  private async projectRun(
    run: {
      run_id: string; chain_id: string; name: string; description: string;
      run_kind: 'solo' | 'group'; completion_rule: 'sequential' | 'all_steps_any_order';
      status: JourneyRun['status']; feed_mode: 'per_stop' | 'one_post' | null;
      has_submissions: boolean;
    },
    userId: string,
  ): Promise<JourneyRun> {
    const steps = await this.database.query<{
      step_order: number; quest_id: string; title: string; description: string;
      xp_reward: number; is_hidden: boolean;
      place_name: string | null; country_name: string | null;
      latitude: number | null; longitude: number | null;
      requires_verification: boolean | null;
      difficulty: string; duration_hours: number;
      completed_at: Date | null; submission_id: string | null;
      approved: boolean; submitted: boolean; assigned: boolean;
      rejected_note: string | null; rejected_appealed: boolean | null;
      rejected_submission_id: string | null;
      unlocked_for: string | null; unlock_seen: boolean;
      target_username: string | null;
    }>(
      `SELECT cs.step_order, q.id AS quest_id, q.title, q.description, q.xp_reward, q.is_hidden,
              q.difficulty, q.duration_hours,
              p.name AS place_name, c.name AS country_name, p.latitude, p.longitude,
              d.requires_verification,
              -- The run's own attempt, so a completed checkpoint can show
              -- when it cleared and link to the proof that cleared it.
              mine.completed_at, mine.submission_id,
              EXISTS (SELECT 1 FROM user_quests uq WHERE uq.quest_id = q.id AND uq.status = 'approved'
                        AND (uq.user_id = $2 OR EXISTS (
                          SELECT 1 FROM quest_chain_run_participants pp
                          WHERE pp.chain_run_id = $1 AND pp.user_id = uq.user_id))) AS approved,
              EXISTS (SELECT 1 FROM user_quests uq WHERE uq.quest_id = q.id AND uq.status = 'submitted'
                        AND (uq.user_id = $2 OR EXISTS (
                          SELECT 1 FROM quest_chain_run_participants pp
                          WHERE pp.chain_run_id = $1 AND pp.user_id = uq.user_id))) AS submitted,
              EXISTS (SELECT 1 FROM user_quests uq WHERE uq.quest_id = q.id
                        AND uq.status = 'assigned' AND uq.user_id = $2) AS assigned,
              rej.review_note AS rejected_note, cur.appealed AS rejected_appealed,
              rej.submission_id AS rejected_submission_id,
              u.target_user_id::text AS unlocked_for,
              (u.seen_at IS NOT NULL) AS unlock_seen,
              pr.username::text AS target_username
       FROM quest_chain_steps cs
       JOIN quests q ON q.id = cs.quest_id
       LEFT JOIN quest_destinations d ON d.quest_id = q.id
       LEFT JOIN map_places p ON p.id = d.place_id AND p.is_published
       LEFT JOIN map_countries c ON c.code = p.country_code
       LEFT JOIN LATERAL (
         SELECT uq.completed_at, s.id AS submission_id
         FROM user_quests uq
         LEFT JOIN submissions s ON s.user_quest_id = uq.id AND s.status = 'approved'
         WHERE uq.quest_id = q.id AND uq.status = 'approved'
           AND (uq.user_id = $2 OR EXISTS (
             SELECT 1 FROM quest_chain_run_participants pp
             WHERE pp.chain_run_id = $1 AND pp.user_id = uq.user_id))
         ORDER BY uq.completed_at DESC LIMIT 1
       ) mine ON true
       -- The rejection that is still standing on this checkpoint.
       --
       -- Only when nothing newer supersedes it: a player who retried has an
       -- assigned or submitted attempt, and that is what the timeline should
       -- show. Without the NOT EXISTS a checkpoint retried and passed would
       -- keep reporting the rejection it already recovered from.
       LEFT JOIN LATERAL (
         SELECT s.review_note, s.appealed, s.id AS submission_id
         FROM user_quests uq
         JOIN submissions s ON s.user_quest_id = uq.id AND s.status = 'rejected'
         WHERE uq.quest_id = q.id AND uq.status = 'rejected'
           AND uq.user_id = $2 AND s.deleted_at IS NULL
           AND NOT EXISTS (
             SELECT 1 FROM user_quests newer
             WHERE newer.quest_id = q.id AND newer.user_id = $2
               AND newer.status IN ('assigned', 'submitted', 'approved'))
         ORDER BY s.reviewed_at DESC NULLS LAST, s.id DESC LIMIT 1
       ) rej ON true
       -- The viewer's latest attempt at this checkpoint, whatever became of
       -- it. Only the appeal flag is taken from it, and only so an appeal
       -- under review can be told apart from a first review — to the player
       -- those are entirely different waits, and calling both 'under review'
       -- leaves them unsure their appeal was ever sent.
       LEFT JOIN LATERAL (
         SELECT s.appealed
         FROM user_quests uq JOIN submissions s ON s.user_quest_id = uq.id
         WHERE uq.quest_id = q.id AND uq.user_id = $2 AND s.deleted_at IS NULL
         ORDER BY s.submitted_at DESC, s.id DESC LIMIT 1
       ) cur ON true
       LEFT JOIN journey_stage_unlocks u ON u.chain_run_id = $1 AND u.step_order = cs.step_order
       LEFT JOIN profiles pr ON pr.id = u.target_user_id
       WHERE cs.chain_id = $3
       ORDER BY cs.step_order`,
      [run.run_id, userId, run.chain_id],
    );

    let unseenUnlock: JourneyRun['unseenUnlock'] = null;
    const stages: JourneyStage[] = steps.rows.map((row) => {
      // Whose checkpoint this is.
      //
      // A solo run has exactly one participant, so every checkpoint in it is
      // theirs — and step 1 never gets an unlock row, because nothing
      // unlocked it. Reading ownership off that row alone made step 1 of
      // every solo journey belong to nobody: the timeline called it "THEIR
      // TURN" and `nextForViewer` skipped it, so a journey whose first
      // checkpoint was rejected offered no action at all.
      const isYours = run.run_kind === 'solo' || row.unlocked_for === userId;
      // Whether the server actually opened this checkpoint for this viewer.
      // A different question from ownership, and the one that protects
      // hidden content: a solo player owns every checkpoint of their own
      // journey, and still may not read one the run has not reached.
      const opened = row.unlocked_for === userId;
      const state: StageState = row.approved
        ? 'COMPLETED'
        : row.submitted
          ? 'UNDER_REVIEW'
          // Already started by this viewer, timer running. Distinct from
          // AVAILABLE because "start" is the wrong verb for it.
          : row.assigned
            ? 'IN_PROGRESS'
            // A rejection nobody has answered yet. Ranked below the states
            // that mean a live attempt and above AVAILABLE, because the
            // checkpoint IS available again — the player can retake it — but
            // saying only that loses the thing they most need to know.
            : row.rejected_submission_id !== null
              ? 'REJECTED'
          // Step 1 is the entry point; an any-order chain gates nothing.
              : row.unlocked_for !== null || row.step_order === 1 ||
                run.completion_rule === 'all_steps_any_order'
                ? 'AVAILABLE'
                : 'LOCKED';

      if (opened && !row.unlock_seen && state === 'AVAILABLE') {
        unseenUnlock = { stepOrder: row.step_order, questId: row.quest_id };
      }

      // What this viewer may read. A completed checkpoint is history and is
      // safe to show; anything still to come is only theirs to read if it is
      // not hidden, or if it has opened for them specifically. Reads
      // `opened`, never `isYours` — see above.
      const mayReadContent =
        state === 'COMPLETED' ||
        state === 'IN_PROGRESS' ||
        state === 'UNDER_REVIEW' ||
        state === 'REJECTED' ||
        (!row.is_hidden && state !== 'LOCKED') ||
        (opened && state === 'AVAILABLE');

      return {
        stepOrder: row.step_order,
        questId: mayReadContent ? row.quest_id : null,
        state,
        xpReward: mayReadContent ? row.xp_reward : null,
        title: mayReadContent ? row.title : null,
        description: mayReadContent ? row.description : null,
        placeName: mayReadContent ? row.place_name : null,
        countryName: mayReadContent ? row.country_name : null,
        // Coordinates travel only with content. Drawing a route to a hidden
        // checkpoint would give away exactly what hiding it withheld.
        latitude: mayReadContent ? row.latitude : null,
        longitude: mayReadContent ? row.longitude : null,
        requiresLocationVerification: row.requires_verification ?? false,
        difficulty: mayReadContent ? row.difficulty : null,
        durationHours: mayReadContent ? row.duration_hours : null,
        completedAt: row.completed_at ? row.completed_at.toISOString() : null,
        submissionId: row.submission_id,
        // The standing rejection, in the words the player was given. Carried
        // on the stage rather than fetched separately because the timeline
        // is where they find out, and "rejected" with no reason attached is
        // the version of this screen that sends people to support.
        rejectionNote: state === 'REJECTED' ? row.rejected_note : null,
        rejectedSubmissionId: state === 'REJECTED' ? row.rejected_submission_id : null,
        // Not gated on REJECTED: an appeal moves the checkpoint back to
        // UNDER_REVIEW, and that is exactly the moment the player needs to
        // be told their appeal is the thing being looked at.
        appealed: row.rejected_appealed === true,
        targetUsername: run.run_kind === 'group' ? row.target_username : null,
        isYours,
      };
    });

    const completedSteps = stages.filter((s) => s.state === 'COMPLETED').length;
    // A checkpoint already under way is what the viewer should be pointed
    // at, ahead of one merely open — it has a timer running on it.
    const nextForViewer =
      stages.find((s) => s.state === 'IN_PROGRESS') ??
      // A rejection of theirs outranks an open checkpoint: it is the thing
      // the journey is actually waiting on them to answer, and leaving it
      // out is what made a rejected journey report "nothing to do".
      stages.find((s) => s.isYours && s.state === 'REJECTED') ??
      stages.find((s) => s.isYours && s.state === 'AVAILABLE') ??
      null;

    return {
      runId: run.run_id,
      chainId: run.chain_id,
      title: run.name,
      description: run.description,
      runKind: run.run_kind,
      completionRule: run.completion_rule,
      status: run.status,
      completedSteps,
      totalSteps: stages.length,
      stages,
      nextForViewer,
      unseenUnlock,
      feedMode: run.feed_mode,
      // Only while nothing has been submitted. After that the server refuses
      // the change, and an offer that can only be refused is worse than none.
      canChooseFeedMode: !run.has_submissions && run.status !== 'completed',
    };
  }

  newJoinCode(): string {
    return randomBytes(4).toString('hex').toUpperCase();
  }
}
