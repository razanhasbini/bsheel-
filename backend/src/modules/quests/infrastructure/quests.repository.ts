import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import {
  DatabaseService,
  type DatabaseTransaction,
} from '../../../infrastructure/database/database.service.js';
import type { QuestRecord, UserQuestRecord } from '../domain/quest.types.js';
import type {
  CreateQuestDto,
  UpdateQuestDto,
} from '../presentation/quest.dto.js';
import { QuestAssignmentPolicyRepository } from './quest-assignment-policy.repository.js';
import { eligibilityFor } from '../domain/quest-eligibility.js';
import { visible as mapVisible } from '../../map/infrastructure/map-visibility.sql.js';

@Injectable()
export class QuestsRepository {
  constructor(private readonly database: DatabaseService, private readonly assignmentPolicy: QuestAssignmentPolicyRepository) {}

  /// A destination quest is reachable exactly when its place is visible on
  /// the map: published, and not a hidden place the user has yet to uncover.
  /// Same predicate as the map endpoints, so a pin never offers a quest this
  /// refuses.
  ///
  /// There is deliberately no assignment-time location gate any more.
  /// Migration 0035 moved presence to the real lifecycle — the geofence opens
  /// after assignment and the network's answer is weighed when the proof
  /// comes in — so the old "verify before you may start" check could never
  /// be satisfied and left every verified quest permanently locked.
  async assertDestinationAccess(userId: string, questId: string, _assignment = false) {
    const result = await this.database.query(`SELECT ${mapVisible} AS visible
      FROM quest_destinations d JOIN map_places p ON p.id=d.place_id WHERE d.quest_id=$2`, [userId,questId]);
    const destination = result.rows[0];
    if (!destination) return;
    if (!destination.visible) {
      throw new NotFoundException({code:'QUEST_NOT_FOUND',message:'Quest not found'});
    }
    // Deliberately no verification gate at assignment.
    //
    // Presence is proven where it is claimed — at SUBMISSION, by the CAMARA
    // pipeline — not before a user is allowed to take a challenge on. The
    // proposal's central journey is a user in Lebanon watching a Lusail
    // Stadium completion, pressing Do This Quest, and saving it for a trip
    // they have not taken yet. Demanding verified presence here made
    // discovery unable to motivate travel, which is the product; and since
    // nothing wrote map_location_evidence, it also made every
    // `requires_verification` quest permanently unassignable.
    //
    // `_assignment` is kept in the signature: callers distinguish the two
    // reads, and the hidden-place check above is the part that still differs.
    void _assignment;
  }

  async findQuest(id: string): Promise<QuestRecord | null> {
    const result = await this.database.query<QuestRecord>(
      'SELECT * FROM quests WHERE id = $1',
      [id],
    );
    return result.rows[0] ?? null;
  }

  async listAll(): Promise<readonly QuestRecord[]> {
    return (
      await this.database.query<QuestRecord>(
        'SELECT * FROM quests ORDER BY created_at DESC, id DESC',
      )
    ).rows;
  }

  async create(input: CreateQuestDto, actorId: string): Promise<QuestRecord> {
    const result = await this.database.query<QuestRecord>(
      `INSERT INTO quests (title, description, category, difficulty, xp_reward, duration_hours, is_active, created_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [
        input.title.trim(),
        input.description.trim(),
        input.category.trim(),
        input.difficulty,
        input.xpReward,
        input.durationHours,
        input.isActive,
        actorId,
      ],
    );
    return result.rows[0];
  }

  async createBulk(
    input: readonly CreateQuestDto[],
    actorId: string,
  ): Promise<readonly QuestRecord[]> {
    return this.database.transaction(async (transaction) => {
      const result = await transaction.query<QuestRecord>(
        `INSERT INTO quests
           (title, description, category, difficulty, xp_reward, duration_hours, is_active, created_by)
         SELECT trim(item.title), trim(item.description), trim(item.category), item.difficulty,
                item.xp_reward, item.duration_hours, item.is_active, $2
         FROM jsonb_to_recordset($1::jsonb) AS item(
           title text, description text, category text, difficulty text,
           xp_reward integer, duration_hours integer, is_active boolean
         )
         RETURNING *`,
        [
          JSON.stringify(
            input.map((quest) => ({
              title: quest.title,
              description: quest.description,
              category: quest.category,
              difficulty: quest.difficulty,
              xp_reward: quest.xpReward,
              duration_hours: quest.durationHours,
              is_active: quest.isActive,
            })),
          ),
          actorId,
        ],
      );
      await transaction.query(
        `INSERT INTO admin_audit_log (actor_id, action, target_type, after_state)
         VALUES ($1, 'quest.bulk_create', 'quest', $2::jsonb)`,
        [actorId, JSON.stringify({ count: result.rowCount })],
      );
      return result.rows;
    });
  }

  async update(id: string, input: UpdateQuestDto): Promise<QuestRecord | null> {
    const result = await this.database.query<QuestRecord>(
      `UPDATE quests SET
         title = COALESCE($2, title), description = COALESCE($3, description),
         category = COALESCE($4, category), difficulty = COALESCE($5, difficulty),
         xp_reward = COALESCE($6, xp_reward), duration_hours = COALESCE($7, duration_hours),
         is_active = COALESCE($8, is_active), updated_at = now()
       WHERE id = $1 RETURNING *`,
      [
        id,
        input.title?.trim(),
        input.description?.trim(),
        input.category?.trim(),
        input.difficulty,
        input.xpReward,
        input.durationHours,
        input.isActive,
      ],
    );
    return result.rows[0] ?? null;
  }

  async delete(id: string, actorId: string): Promise<void> {
    try {
      await this.database.transaction(async (transaction) => {
        const quest = await transaction.query<QuestRecord>(
          'DELETE FROM quests WHERE id = $1 RETURNING *',
          [id],
        );
        if (!quest.rows[0]) {
          throw new NotFoundException({
            code: 'QUEST_NOT_FOUND',
            message: 'Quest not found',
          });
        }
        await transaction.query(
          `INSERT INTO admin_audit_log
             (actor_id, action, target_type, target_id, before_state)
           VALUES ($1, 'quest.delete', 'quest', $2, $3::jsonb)`,
          [actorId, id, JSON.stringify(quest.rows[0])],
        );
      });
    } catch (error) {
      if (this.isForeignKeyViolation(error)) {
        throw new ConflictException({
          code: 'QUEST_IN_USE',
          message:
            'Quest is still referenced by collaboration or scheduling data',
        });
      }
      throw error;
    }
  }

  async deleteAll(actorId: string): Promise<{ deleted: number }> {
    try {
      return await this.database.transaction(async (transaction) => {
        const deleted = await transaction.query(
          'DELETE FROM quests RETURNING id',
        );
        await transaction.query(
          `INSERT INTO admin_audit_log (actor_id, action, target_type, after_state)
           VALUES ($1, 'quest.delete_all', 'quest', $2::jsonb)`,
          [actorId, JSON.stringify({ deleted: deleted.rowCount })],
        );
        return { deleted: deleted.rowCount ?? 0 };
      });
    } catch (error) {
      if (this.isForeignKeyViolation(error)) {
        throw new ConflictException({
          code: 'QUESTS_IN_USE',
          message:
            'One or more quests are still referenced by collaboration or scheduling data',
        });
      }
      throw error;
    }
  }

  /**
   * Ensures a chain step being assigned belongs to a live run, and records
   * that this checkpoint has been started.
   *
   * A solo chain opens its run lazily here, because there is no roster to
   * gather. A group chain must NOT: coercing it into a solo run would
   * produce a run whose kind disagrees with its chain, and would hand one
   * person a relay meant for several. It is refused instead.
   */
  private async openJourneyForStep(
    userId: string,
    questId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const step = await transaction.query<{
      chain_id: string; mode: string; step_order: number; completion_rule: string;
    }>(
      `SELECT cs.chain_id, ch.mode, cs.step_order, ch.completion_rule
       FROM quest_chain_steps cs JOIN quest_chains ch ON ch.id = cs.chain_id
       WHERE cs.quest_id = $1 AND ch.is_active`,
      [questId],
    );
    const row = step.rows[0];
    if (!row) return;
    // An all_steps_any_order chain has no baton to pass and nothing to
    // sequence, so it needs no run and must not be made to wait for one.
    // Runs exist to carry ORDERED progression.
    if (row.completion_rule !== 'sequential') return;

    const live = await transaction.query<{ id: string }>(
      `SELECT r.id FROM quest_chain_runs r
       WHERE r.chain_id = $2 AND r.status IN ('forming', 'active')
         AND (r.owner_user_id = $1 OR EXISTS (
           SELECT 1 FROM quest_chain_run_participants p
           WHERE p.chain_run_id = r.id AND p.user_id = $1))
       LIMIT 1`,
      [userId, row.chain_id],
    );

    if (live.rows.length === 0) {
      if (row.mode !== 'solo') {
        // Only refuse here when somebody is trying to BEGIN a relay. A
        // request for a later step is a different mistake and deserves the
        // more precise answer: that checkpoint is locked, not that the
        // journey needs starting. Returning lets the eligibility gate say
        // so, which is also what keeps a non-member out.
        if (row.step_order !== 1) return;
        throw new BadRequestException({
          code: 'CHAIN_RUN_REQUIRED',
          message: 'This journey is a relay — it has to be started as a group run',
        });
      }
      await transaction.query(
        `INSERT INTO quest_chain_runs (chain_id, run_kind, owner_user_id, created_by_user_id, status, started_at)
         VALUES ($1, 'solo', $2, $2, 'active', now()) ON CONFLICT DO NOTHING`,
        [row.chain_id, userId],
      );
    }

    // Audit only. Deliberately not a gate: an expired or rejected checkpoint
    // stays retryable under the ordinary quest rules, so a journey cannot
    // strand itself on a stage somebody started and ran out of time on.
    await transaction.query(
      `UPDATE journey_stage_unlocks SET started_at = COALESCE(started_at, now())
       WHERE quest_id = $1 AND target_user_id = $2`,
      [questId, userId],
    );
  }

  async findActiveForUser(userId: string): Promise<UserQuestRecord | null> {
    const result = await this.database.query<
      UserQuestRecord & { quests: QuestRecord }
    >(
      `SELECT uq.*, row_to_json(q.*) AS quests
       FROM user_quests uq JOIN quests q ON q.id = uq.quest_id
       WHERE uq.user_id = $1 AND uq.status IN ('assigned', 'submitted')
       ORDER BY uq.assigned_at DESC LIMIT 1`,
      [userId],
    );
    return result.rows[0] ?? null;
  }

  async history(
    userId: string,
    limit: number,
    offset: number,
  ): Promise<readonly UserQuestRecord[]> {
    // `appeal_available` mirrors the four guards SubmissionsService enforces
    // on appeal — owner, status rejected, appeal unspent, not soft-deleted —
    // so the client can offer the action only where it will succeed.
    //
    // The client cannot derive this. `user_quests.status` is 'rejected' both
    // for a first rejection and for a re-rejection after a spent appeal;
    // there is no separate terminal status. Without this flag the history
    // list either hides the appeal from everyone who can still use it, or
    // offers it to people whose appeal is gone and sends them to a dead end.
    //
    // Costs one indexed probe per row via submissions_user_quest_idx.
    const result = await this.database.query<UserQuestRecord>(
      `SELECT uq.*, row_to_json(q.*) AS quests,
              EXISTS (
                SELECT 1 FROM submissions s
                WHERE s.user_quest_id = uq.id
                  AND s.status = 'rejected'
                  AND s.appealed = false
                  AND s.deleted_at IS NULL
              ) AS appeal_available,
              -- The submission id the appeal screen needs.
              --
              -- Without it the client had only uq.id to navigate with, and
              -- the appeal route resolves a submission — so tapping APPEAL in
              -- history opened "Submission not found". The route only checks
              -- that the parameter is a UUID, which is why the mistake was
              -- invisible until the fetch.
              (
                SELECT s.id FROM submissions s
                WHERE s.user_quest_id = uq.id
                  AND s.deleted_at IS NULL
                ORDER BY (s.status = 'rejected' AND s.appealed = false) DESC,
                         s.submitted_at DESC
                LIMIT 1
              ) AS submission_id
       FROM user_quests uq JOIN quests q ON q.id = uq.quest_id
       WHERE uq.user_id = $1
       ORDER BY uq.assigned_at DESC, uq.id DESC
       LIMIT $2 OFFSET $3`,
      [userId, Math.min(Math.max(limit, 1), 100), Math.max(offset, 0)],
    );
    return result.rows;
  }

  /// Assigns a specific quest.
  ///
  /// `displaceActive` is for admin assignment only: a moderator picking a
  /// quest for a user is an override, so any in-flight quest is expired in
  /// the same transaction rather than rejecting the request. A user
  /// assigning their own quest still cannot bypass the one-active rule.
  async assignSpecific(
    userId: string,
    questId: string,
    displaceActive = false,
  ): Promise<UserQuestRecord> {
    await this.assertDestinationAccess(userId, questId, true);
    return this.database.transaction(async (transaction) => {
      // Starting a chain step is what opens the journey, and the timer
      // starts HERE — never at unlock. An approval that landed while the
      // user was asleep must not have been quietly burning their clock.
      await this.openJourneyForStep(userId, questId, transaction);
      await this.assignmentPolicy.lockUser(userId, transaction);
      await this.expireOverdueForUser(userId, transaction);
      if (displaceActive) {
        await transaction.query(
          // Only the active quest is displaced. Expiring a 'submitted' row
          // would throw away proof a moderator has not judged yet, and the
          // user cannot get it back.
          `UPDATE user_quests SET status = 'expired', version = version + 1
           WHERE user_id = $1 AND status = 'assigned'`,
          [userId],
        );
      }
      // One *active* quest per user. Submissions awaiting review no longer
      // block a new roll — moderation latency is not something the user can
      // clear, so blocking on it left them with nothing to do. Backed by
      // user_quests_one_assigned_idx (migration 0021).
      const active = await transaction.query(
        `SELECT 1 FROM user_quests WHERE user_id = $1 AND status = 'assigned' LIMIT 1`,
        [userId],
      );
      if (active.rowCount) {
        throw new ConflictException({
          code: 'ACTIVE_QUEST_EXISTS',
          message: 'User already has an active quest',
        });
      }
      if (!displaceActive) await this.assignmentPolicy.assertCooldownElapsed(userId, transaction);
      // A chain step past the first is locked until the previous step has
      // APPROVED proof for this user. The roll never offers one, but this
      // endpoint takes a questId from the client, so the rule has to be
      // enforced here too or the chain is bypassable by id.
      // Whose approval counts depends on the chain's mode, and until now
      // this only ever asked about the caller — so in a group chain, where
      // the previous step belongs to somebody else by definition, step 2
      // could never open for anyone and `mode = 'group'` was unreachable.
      // Nothing failed loudly; relays just stopped after step 1.
      const locked = await transaction.query<{ step_order: number }>(
        `SELECT cs.step_order
         FROM quest_chain_steps cs
         JOIN quest_chains ch ON ch.id = cs.chain_id
         WHERE cs.quest_id = $2
           AND cs.step_order > 1
           -- A cross-country challenge has no reason to make one country
           -- wait for another, so only sequential chains gate on order.
           AND ch.completion_rule = 'sequential'
           AND NOT EXISTS (
             SELECT 1
             FROM quest_chain_steps prev
             JOIN user_quests uq ON uq.quest_id = prev.quest_id
             WHERE prev.chain_id = cs.chain_id
               AND prev.step_order = cs.step_order - 1
               AND uq.status = 'approved'
               AND (
                 ch.mode = 'solo' AND uq.user_id = $1
                 OR ch.mode = 'group' AND EXISTS (
                   SELECT 1 FROM collab_group_members m
                   WHERE m.group_id = ch.collab_group_id AND m.user_id = uq.user_id
                 )
               )
           )
         LIMIT 1`,
        [userId, questId],
      );
      if (locked.rowCount) {
        throw new ConflictException({
          code: 'QUEST_STEP_LOCKED',
          message: 'Finish and get the previous step approved first',
        });
      }

      // An out-of-window event quest is not assignable either, however the
      // id was obtained.
      const questResult = await transaction.query<QuestRecord>(
        `SELECT * FROM quests
         WHERE id = $1 AND is_active = true
           AND (available_from IS NULL OR available_from <= now())
           AND (available_until IS NULL OR available_until > now())
           -- A hidden quest is not assignable until it has actually opened
           -- for THIS user. The roll never offers one, but this endpoint
           -- takes an id from the client — exactly the reasoning already
           -- applied to chain steps above, which was never applied here. A
           -- guessed or leaked id could take a hidden quest straight past
           -- the unlock mechanism, and nothing would have noticed.
           --
           -- Two mechanisms can open one, and they are separate by design:
           -- discovery owns generic hidden unlocks (quest_unlock_rules →
           -- user_quest_unlocks), journeys own stage unlocks
           -- (journey_stage_unlocks). A hidden later step of a chain is
           -- opened by its journey and has no user_quest_unlocks row, so a
           -- gate that knew only the first would have locked every
           -- multi-stage quest out of its own progression.
           AND (NOT is_hidden
             OR EXISTS (
               SELECT 1 FROM user_quest_unlocks u
               WHERE u.quest_id = quests.id AND u.user_id = $2
             )
             OR EXISTS (
               SELECT 1 FROM journey_stage_unlocks j
               JOIN quest_chain_runs r ON r.id = j.chain_run_id
               WHERE j.quest_id = quests.id AND j.target_user_id = $2
                 AND r.status = 'active'
             ))`,
        [questId, userId],
      );
      const quest = questResult.rows[0];
      if (!quest)
        throw new NotFoundException({
          code: 'QUEST_NOT_FOUND',
          message: 'Quest not found or inactive',
        });
      const assigned = await transaction.query<UserQuestRecord>(
        `INSERT INTO user_quests (user_id, quest_id, expires_at)
         VALUES ($1, $2, now() + make_interval(hours => $3)) RETURNING *`,
        [userId, questId, quest.duration_hours],
      );
      await transaction.query(
        `UPDATE admin_quest_injections SET consumed_at = now()
         WHERE target_user_id = $1 AND quest_id = $2 AND consumed_at IS NULL`,
        [userId, questId],
      );
      await this.insertAssignmentNotification(
        userId,
        assigned.rows[0],
        quest.duration_hours,
        transaction,
      );
      await this.emitQuest(
        'quest.assigned',
        assigned.rows[0].id,
        {
          userId,
          userQuestId: assigned.rows[0].id,
          questId,
        },
        transaction,
      );
      return { ...assigned.rows[0], quests: quest };
    });
  }

  /**
   * Cancels a live quest at the player's request.
   *
   * Separate from `expire`, which only accepts a quest whose timer has
   * already run out — that guard is what makes the countdown
   * server-enforced, so it must not be loosened. CANCEL QUEST in the app
   * called `expire`, and the button only renders while the quest is still
   * running, so every tap returned QUEST_NOT_EXPIRABLE: the action was
   * present, labelled, and completely non-functional.
   *
   * Writes `abandoned`, a value the enum has always had and nothing ever
   * used, so a cancelled quest stays distinguishable from one the player
   * simply ran out of time on.
   *
   * Does NOT refund the roll. Abandoning frees the active slot; the
   * five-rerolls-per-24h budget is what bounds intake.
   */
  async abandon(userId: string, userQuestId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query(
        `UPDATE user_quests SET status = 'abandoned', version = version + 1
         WHERE id = $1 AND user_id = $2 AND status = 'assigned'
         RETURNING id`,
        [userQuestId, userId],
      );
      if (!result.rowCount) {
        throw new ConflictException({
          code: 'QUEST_NOT_ABANDONABLE',
          message: 'That quest is not yours, or is no longer active',
        });
      }
      await this.emitQuest(
        'quest.abandoned',
        userQuestId,
        { userId, userQuestId },
        transaction,
      );
    });
  }

  async expire(userId: string, userQuestId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const result = await transaction.query(
        `UPDATE user_quests SET status = 'expired', version = version + 1
         WHERE id = $1 AND user_id = $2 AND status = 'assigned' AND expires_at <= now()
         RETURNING id`,
        [userQuestId, userId],
      );
      if (!result.rowCount) {
        throw new ConflictException({
          code: 'QUEST_NOT_EXPIRABLE',
          message: 'Quest is not assigned to you or has not expired',
        });
      }
      await this.emitQuest(
        'quest.expired',
        userQuestId,
        {
          userId,
          userQuestId,
        },
        transaction,
      );
      await this.insertExpirationNotification(userId, userQuestId, transaction);
    });
  }

  /// SQL predicate for a quest the system may hand a user unprompted (#51).
  ///
  /// Excludes, in order: hidden content, anything outside its event window,
  /// and any chain step past the first. The last one matters most — a
  /// multi-stage quest's later steps must stay locked until the previous
  /// step has approved proof, so the roll only ever offers an entry point.
  ///
  /// Takes the quest alias so callers can apply it to `q`, `quests`, etc.
  private static offerable(alias: string): string {
    // Delegates to the shared eligibility engine so the roll, Home, the map
    // and search cannot drift apart. The ROLL channel is the narrowest: it
    // adds the location-independent and not-already-settled clauses on top
    // of the visibility rules every surface shares.
    return eligibilityFor('ROLL', { alias, userParam: '$1' });
  }

  async pickerOptions(
    userId: string,
    requestedCount: number,
  ): Promise<readonly QuestRecord[]> {
    const count = Math.min(Math.max(requestedCount || 3, 1), 20);
    return this.database.transaction(async (transaction) => {
      await this.assignmentPolicy.lockUser(userId, transaction);
      await this.chargeRollIfNotFirstOfCycle(userId, transaction);
      const injection = await transaction.query<QuestRecord>(
        `WITH popped AS (
           UPDATE admin_quest_injections SET consumed_at = now()
           WHERE id = (SELECT id FROM admin_quest_injections WHERE target_user_id = $1 AND consumed_at IS NULL ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED)
           RETURNING quest_id
         ) SELECT q.* FROM popped p JOIN quests q ON q.id = p.quest_id WHERE q.is_active
             AND NOT EXISTS (SELECT 1 FROM quest_destinations d WHERE d.quest_id=q.id)
             -- An admin may inject hidden or out-of-window content on
             -- purpose, but never a chain step whose predecessor is unmet.
             AND NOT EXISTS (
               SELECT 1 FROM quest_chain_steps cs
               WHERE cs.quest_id = q.id AND cs.step_order > 1
             )`,
        [userId],
      );
      const injected = injection.rows[0];
      const remaining = count - (injected ? 1 : 0);
      if (remaining <= 0) return injected ? [injected] : [];
      const adminSlots = Math.max(1, Math.ceil(remaining / 2));
      const result = await transaction.query<QuestRecord>(
        `WITH eligible AS (
           SELECT q.* FROM quests q
           WHERE ${QuestsRepository.offerable('q')}
             AND ($2::uuid IS NULL OR q.id <> $2)
             AND NOT EXISTS (SELECT 1 FROM admin_quest_injections i WHERE i.quest_id = q.id)
         ), preferred AS (
           SELECT * FROM eligible WHERE created_by IS NOT NULL ORDER BY created_at DESC, random() LIMIT $3
         ), filler AS (
           SELECT * FROM eligible e WHERE NOT EXISTS (SELECT 1 FROM preferred p WHERE p.id = e.id)
           ORDER BY random() LIMIT GREATEST(0, $4 - (SELECT count(*)::integer FROM preferred))
         ) SELECT * FROM preferred UNION ALL SELECT * FROM filler`,
        [userId, injected?.id ?? null, adminSlots, remaining],
      );
      return injected ? [injected, ...result.rows] : result.rows;
    });
  }

  async questOfTheDay(): Promise<Record<string, unknown> | null> {
    const result = await this.database.query(
      `SELECT d.id, to_char(d.display_date, 'YYYY-MM-DD') AS display_date, d.ticket_no, d.bonus_xp, q.id AS quest_id,
              q.title AS quest_title, q.description AS quest_description,
              q.category AS quest_category, q.difficulty AS quest_difficulty,
              q.xp_reward AS quest_xp_reward, q.duration_hours AS quest_duration_hours
       FROM quest_of_the_day d JOIN quests q ON q.id = d.quest_id
       WHERE d.display_date = (now() AT TIME ZONE 'UTC')::date
         AND ${eligibilityFor('QUEST_OF_DAY', { alias: 'q' })} LIMIT 1`,
    );
    return result.rows[0] ?? null;
  }

  async followingActive(
    userId: string,
    limit: number,
  ): Promise<readonly Record<string, unknown>[]> {
    const capped = Math.min(Math.max(limit || 12, 1), 40);
    const result = await this.database.query(
      `WITH followed AS (
         SELECT uq.id AS user_quest_id, uq.user_id, p.username::text, p.display_name, p.avatar_url,
                q.id AS quest_id, q.title AS quest_title, q.category AS quest_category,
                q.xp_reward, uq.assigned_at, uq.expires_at, 0 AS pool
         FROM user_quests uq JOIN follows f ON f.following_id = uq.user_id AND f.follower_id = $1
         JOIN profiles p ON p.id = uq.user_id JOIN quests q ON q.id = uq.quest_id
         WHERE uq.status = 'assigned' AND uq.expires_at > now() AND uq.user_id <> $1
       ), global_pool AS (
         SELECT uq.id AS user_quest_id, uq.user_id, p.username::text, p.display_name, p.avatar_url,
                q.id AS quest_id, q.title AS quest_title, q.category AS quest_category,
                q.xp_reward, uq.assigned_at, uq.expires_at, 1 AS pool
         FROM user_quests uq JOIN profiles p ON p.id = uq.user_id JOIN quests q ON q.id = uq.quest_id
         WHERE uq.status = 'assigned' AND uq.expires_at > now() AND uq.user_id <> $1
           AND NOT EXISTS (SELECT 1 FROM followed)
       ) SELECT * FROM (SELECT * FROM followed UNION ALL SELECT * FROM global_pool) candidates
         ORDER BY pool, assigned_at DESC LIMIT $2`,
      [userId, capped],
    );
    return result.rows;
  }

  async rerollsRemaining(userId: string): Promise<number> {
    const result = await this.database.query<{ remaining: number }>(
      // Only charged rows count: the free first spin of a cycle is logged
      // too, as the marker that the cycle has started.
      `SELECT GREATEST(0, 5 - count(*))::integer AS remaining FROM quest_reroll_log
       WHERE user_id = $1 AND charged AND rerolled_at > now() - interval '24 hours'`,
      [userId],
    );
    return result.rows[0].remaining;
  }

  /**
   * Charges a reroll for a picker fetch, unless it is the first of this cycle.
   *
   * The cap was enforced only inside `POST /quests/rerolls` — a bookkeeping
   * route the client calls voluntarily. Neither the picker nor assign looked
   * at the budget, so a caller with zero rerolls left could spin fresh
   * options indefinitely and take any of them. CLAUDE.md states the cap is
   * "the real limit on quest intake"; it was not.
   *
   * A cycle starts when the player takes a quest, so the first spin after
   * finishing one is free and every re-spin costs. Concretely: free when no
   * reroll has been logged since the most recent `assigned_at` — which also
   * makes a brand-new player's first ever spin free, since they have no
   * assignment to compare against.
   *
   * Runs under the same advisory lock as the rest of `pickerOptions`, so two
   * concurrent spins cannot both read the budget as unspent.
   */
  private async chargeRollIfNotFirstOfCycle(
    userId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const state = await transaction.query<{ free: boolean; used: number }>(
      // "First of this cycle" means nothing has been logged since the most
      // recent assignment — charged or not. The free spin is recorded with
      // charged = false precisely so the second spin can tell itself apart
      // from the first; without that row every spin looks like the first and
      // the cap never engages.
      `SELECT
         NOT EXISTS (
           SELECT 1 FROM quest_reroll_log l
           WHERE l.user_id = $1
             AND l.rerolled_at > COALESCE(
                   (SELECT max(uq.assigned_at) FROM user_quests uq WHERE uq.user_id = $1),
                   to_timestamp(0))
         ) AS free,
         (SELECT count(*)::integer FROM quest_reroll_log l
          WHERE l.user_id = $1 AND l.charged
            AND l.rerolled_at > now() - interval '24 hours') AS used`,
      [userId],
    );
    const { free, used } = state.rows[0];

    if (free) {
      await transaction.query(
        'INSERT INTO quest_reroll_log (user_id, charged) VALUES ($1, false)',
        [userId],
      );
      return;
    }

    if (used >= 5) {
      throw new ConflictException({
        code: 'REROLL_LIMIT_REACHED',
        message: 'Reroll limit reached (5 per 24h)',
      });
    }
    await transaction.query(
      'INSERT INTO quest_reroll_log (user_id, charged) VALUES ($1, true)',
      [userId],
    );
  }

  /**
   * Reports the remaining budget. No longer charges it.
   *
   * `pickerOptions` is now the single place a reroll is spent, because that
   * is the call that actually hands out new options — gating only this route
   * left the cap bypassable by skipping it. Keeping the route as a read
   * matters for the build already in TestFlight, which calls it immediately
   * after fetching the picker: if it still charged, every spin would cost
   * two rerolls and existing users would hit the cap in half the spins.
   *
   * Still refuses at zero, so a client that calls this first and honours the
   * error keeps showing the right thing.
   */
  async recordReroll(userId: string): Promise<number> {
    const remaining = await this.rerollsRemaining(userId);
    if (remaining <= 0) {
      throw new ConflictException({
        code: 'REROLL_LIMIT_REACHED',
        message: 'Reroll limit reached (5 per 24h)',
      });
    }
    return remaining;
  }

  private async expireOverdueForUser(
    userId: string,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const expired = await transaction.query<{ id: string }>(
      `UPDATE user_quests SET status = 'expired', version = version + 1
       WHERE user_id = $1 AND status = 'assigned' AND expires_at < now()
       RETURNING id`,
      [userId],
    );
    for (const assignment of expired.rows) {
      await this.emitQuest(
        'quest.expired',
        assignment.id,
        {
          userId,
          userQuestId: assignment.id,
        },
        transaction,
      );
      await this.insertExpirationNotification(userId, assignment.id, transaction);
    }
  }

  private async insertExpirationNotification(userId: string, assignmentId: string, transaction: DatabaseTransaction): Promise<void> {
    const notification = await transaction.query<{ id: string }>(
      `INSERT INTO notifications (user_id, title, body, type, reference_id)
       SELECT $1, 'Quest gone. Poof. 💨',
              'Time ran out. Pull a new one and try again. No streak shame here.',
              'quest_expired', $2
       WHERE NOT EXISTS (
         SELECT 1 FROM notifications
         WHERE user_id = $1 AND type = 'quest_expired' AND reference_id = $2
       ) RETURNING id`,
      [userId, assignmentId],
    );
    if (!notification.rows[0]) return;
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('notification', $1, 'notification.created', $2::jsonb)`,
      [notification.rows[0].id, JSON.stringify({ notificationId: notification.rows[0].id, userId })],
    );
  }

  private async insertAssignmentNotification(
    userId: string,
    assignment: UserQuestRecord,
    durationHours: number,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    const count = await transaction.query<{ count: number }>(
      'SELECT count(*)::integer AS count FROM user_quests WHERE user_id = $1',
      [userId],
    );
    const duration = durationHours === 1 ? '1 hour' : `${durationHours} hours`;
    const first = count.rows[0].count === 1;
    const variants = [
      `Tap in. ${duration} on the clock. ⏳`,
      `A fresh quest landed in your lap. ${duration} to make it count.`,
      `Real life called. It assigned you something. ${duration} to deliver.`,
    ];
    const title = first
      ? 'Your adventure begins. ⚔️'
      : 'New quest just dropped.';
    const body = first
      ? `First quest unlocked. Finish it in ${duration} and the XP is yours.`
      : variants[Math.floor(Math.random() * variants.length)];
    const notification = await transaction.query<{ id: string }>(
      `INSERT INTO notifications (user_id, title, body, type, reference_id)
       VALUES ($1, $2, $3, 'quest_assigned', $4) RETURNING id`,
      [userId, title, body, assignment.id],
    );
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('notification', $1, 'notification.created', $2::jsonb)`,
      [
        notification.rows[0].id,
        JSON.stringify({ notificationId: notification.rows[0].id, userId }),
      ],
    );
  }

  private async emitQuest(
    eventType: string,
    aggregateId: string,
    payload: Record<string, unknown>,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
       VALUES ('quest', $1, $2, $3::jsonb)`,
      [aggregateId, eventType, JSON.stringify(payload)],
    );
  }

  private isForeignKeyViolation(error: unknown): boolean {
    return (
      typeof error === 'object' &&
      error !== null &&
      'code' in error &&
      error.code === '23503'
    );
  }
}
