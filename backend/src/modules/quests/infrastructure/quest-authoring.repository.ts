import { BadRequestException, Injectable } from '@nestjs/common';
import { DatabaseService } from '../../../infrastructure/database/database.service.js';
import type { DatabaseTransaction } from '../../../infrastructure/database/database.service.js';
import type { AuthorChainDto, AuthorQuestDto } from '../presentation/quest-authoring.dto.js';

/** One authored quest, echoed back with every dimension resolved. */
export interface AuthoredQuest {
  readonly id: string;
  readonly title: string;
  readonly category: string;
  readonly difficulty: string;
  readonly xpReward: number;
  readonly isHidden: boolean;
  readonly editorialTier: string;
  readonly availableUntil: Date | null;
  readonly placeId: string | null;
  readonly unlockRuleCount: number;
}

/** A chain, its steps, and how players are actually doing on each one. */
export interface ChainOverview {
  readonly id: string;
  readonly name: string;
  readonly mode: string;
  readonly completionRule: string;
  readonly isActive: boolean;
  readonly steps: readonly ChainStepOverview[];
}

export interface ChainStepOverview {
  readonly stepOrder: number;
  readonly questId: string;
  readonly title: string;
  readonly isHidden: boolean;
  readonly xpReward: number;
  readonly placeName: string | null;
  readonly requiresVerification: boolean;
  /** Live counts, so a step that nobody can clear is visible as one. */
  readonly assigned: number;
  readonly submitted: number;
  readonly approved: number;
  readonly rejected: number;
}

/**
 * Writes for the admin authoring surface.
 *
 * Every method here is one transaction, because a quest is not one row: it
 * is a row plus optionally a destination, unlock rules, collection
 * memberships and a chain step. A partial write produces content that is
 * broken in a way nobody notices until a player hits it — a destination
 * quest with no destination, a hidden quest with no way to open.
 */
@Injectable()
export class QuestAuthoringRepository {
  constructor(private readonly database: DatabaseService) {}

  async authorQuest(input: AuthorQuestDto, actorId: string): Promise<AuthoredQuest> {
    return this.database.transaction(async (transaction) => {
      const id = await this.insertQuest(transaction, input, actorId);
      return this.readBack(transaction, id);
    });
  }

  /**
   * Creates every step and the chain linking them, atomically.
   *
   * Steps after the first default to hidden: the reveal is the mechanic, and
   * an author who wanted a visible later step has to say so. The unlock rule
   * is written too — `chainStepUnlocked` gates the step on the previous one's
   * approval, and the rule row is what makes the same fact legible to the
   * admin panel and to any future unlock surface.
   */
  async authorChain(input: AuthorChainDto, actorId: string): Promise<ChainOverview> {
    if (input.mode === 'group' && !input.collabGroupId) {
      throw new BadRequestException({
        code: 'COLLAB_GROUP_REQUIRED',
        message: 'A group relay needs the collab group that runs it',
      });
    }
    return this.database.transaction(async (transaction) => {
      const chain = await transaction.query<{ id: string }>(
        `INSERT INTO quest_chains (name, description, mode, completion_rule, collab_group_id, created_by)
         VALUES ($1, $2, $3, $4, $5, $6)
         RETURNING id`,
        [
          input.name.trim(), (input.description ?? '').trim(), input.mode,
          input.completionRule, input.collabGroupId ?? null, actorId,
        ],
      );
      const chainId = chain.rows[0].id;

      let previousQuestId: string | null = null;
      for (const [index, step] of input.steps.entries()) {
        const questId = await this.insertQuest(
          transaction,
          // Later steps are hidden unless the author overrode it explicitly.
          index === 0 ? step : { ...step, isHidden: step.isHidden ?? true },
          actorId,
        );
        await transaction.query(
          `INSERT INTO quest_chain_steps (chain_id, quest_id, step_order) VALUES ($1, $2, $3)`,
          [chainId, questId, index + 1],
        );
        // Only sequential chains have a prerequisite to record. An
        // any-order chain gates nothing, so writing one would describe a
        // rule the eligibility engine does not apply.
        if (previousQuestId && input.completionRule === 'sequential') {
          await transaction.query(
            `INSERT INTO quest_unlock_rules (quest_id, unlock_type, prerequisite_quest_id)
             VALUES ($1, 'prerequisite_quest', $2)`,
            [questId, previousQuestId],
          );
        }
        previousQuestId = questId;
      }
      return this.readChain(transaction, chainId);
    });
  }

  /** Every quest with the dimensions that decide where it can appear. */
  async catalogue(limit: number, offset: number): Promise<readonly AuthoredQuest[]> {
    const result = await this.database.query<CatalogueRow>(
      `${CATALOGUE_SELECT}
       ORDER BY q.created_at DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset],
    );
    return result.rows.map(toAuthored);
  }

  async chains(): Promise<readonly ChainOverview[]> {
    // One connection for the whole read, so every chain's step counts come
    // from the same snapshot. Across separate pool checkouts a moderator
    // approving mid-read could produce a view where step 2 has more
    // approvals than step 1, which is impossible and reads as a bug.
    return this.database.transaction(async (transaction) => {
      const result = await transaction.query<{ id: string }>(
        `SELECT id FROM quest_chains ORDER BY created_at DESC LIMIT 200`,
      );
      const out: ChainOverview[] = [];
      for (const row of result.rows) {
        out.push(await this.readChain(transaction, row.id));
      }
      return out;
    });
  }

  // ── internals ────────────────────────────────────────────────────────

  private async insertQuest(
    transaction: DatabaseTransaction,
    input: AuthorQuestDto,
    actorId: string,
  ): Promise<string> {
    const created = await transaction.query<{ id: string }>(
      `INSERT INTO quests (
         title, description, category, difficulty, xp_reward, duration_hours,
         is_active, is_hidden, editorial_tier, is_globally_discoverable,
         available_from, available_until, sponsor_name, partner_id, created_by)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15)
       RETURNING id`,
      [
        input.title.trim(), input.description.trim(), input.category.trim(),
        input.difficulty, input.xpReward, input.durationHours,
        input.isActive ?? true, input.isHidden ?? false,
        input.editorialTier ?? 'standard', input.isGloballyDiscoverable ?? true,
        input.availableFrom ?? null, input.availableUntil ?? null,
        input.sponsorName?.trim() || null, input.partnerId ?? null, actorId,
      ],
    );
    const questId = created.rows[0].id;

    if (input.destination) {
      await transaction.query(
        `INSERT INTO quest_destinations (quest_id, place_id, requires_verification)
         VALUES ($1, $2, $3)`,
        [questId, input.destination.placeId, input.destination.requiresVerification ?? true],
      );
    }

    for (const rule of input.unlockRules ?? []) {
      // The column set is fixed; which of them is non-null is what the
      // CHECK constraint validates. Sending them all and letting Postgres
      // refuse an incoherent combination is the right division of labour —
      // the database is the authority on what a legal rule is.
      await transaction.query(
        `INSERT INTO quest_unlock_rules
           (quest_id, unlock_type, country_code, place_id, prerequisite_quest_id, collection_id, threshold)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [
          questId, rule.unlockType, rule.countryCode ?? null, rule.placeId ?? null,
          rule.prerequisiteQuestId ?? null, rule.collectionId ?? null, rule.threshold ?? null,
        ],
      );
    }

    for (const collectionId of input.collectionIds ?? []) {
      await transaction.query(
        `INSERT INTO quest_collection_items (collection_id, quest_id)
         VALUES ($1, $2) ON CONFLICT DO NOTHING`,
        [collectionId, questId],
      );
    }
    return questId;
  }

  private async readBack(transaction: DatabaseTransaction, id: string): Promise<AuthoredQuest> {
    const result = await transaction.query<CatalogueRow>(
      `${CATALOGUE_SELECT} WHERE q.id = $1`,
      [id],
    );
    return toAuthored(result.rows[0]);
  }

  private async readChain(transaction: DatabaseTransaction, chainId: string): Promise<ChainOverview> {
    const head = await transaction.query<{
      id: string; name: string; mode: string; completion_rule: string; is_active: boolean;
    }>(
      `SELECT id, name, mode, completion_rule, is_active FROM quest_chains WHERE id = $1`,
      [chainId],
    );
    const steps = await transaction.query<{
      step_order: number; quest_id: string; title: string; is_hidden: boolean;
      xp_reward: number; place_name: string | null; requires_verification: boolean | null;
      assigned: number; submitted: number; approved: number; rejected: number;
    }>(
      // Counted per status rather than as one total, because "nobody has
      // cleared step 3" and "nobody has reached step 3" look identical in a
      // total and mean completely different things.
      `SELECT cs.step_order, q.id AS quest_id, q.title, q.is_hidden, q.xp_reward,
              p.name AS place_name, d.requires_verification,
              count(*) FILTER (WHERE uq.status = 'assigned')::int  AS assigned,
              count(*) FILTER (WHERE uq.status = 'submitted')::int AS submitted,
              count(*) FILTER (WHERE uq.status = 'approved')::int  AS approved,
              count(*) FILTER (WHERE uq.status = 'rejected')::int  AS rejected
       FROM quest_chain_steps cs
       JOIN quests q ON q.id = cs.quest_id
       LEFT JOIN quest_destinations d ON d.quest_id = q.id
       LEFT JOIN map_places p ON p.id = d.place_id
       LEFT JOIN user_quests uq ON uq.quest_id = q.id
       WHERE cs.chain_id = $1
       GROUP BY cs.step_order, q.id, q.title, q.is_hidden, q.xp_reward, p.name, d.requires_verification
       ORDER BY cs.step_order`,
      [chainId],
    );
    const row = head.rows[0];
    return {
      id: row.id,
      name: row.name,
      mode: row.mode,
      completionRule: row.completion_rule,
      isActive: row.is_active,
      steps: steps.rows.map((s) => ({
        stepOrder: s.step_order,
        questId: s.quest_id,
        title: s.title,
        isHidden: s.is_hidden,
        xpReward: s.xp_reward,
        placeName: s.place_name,
        requiresVerification: s.requires_verification ?? false,
        assigned: s.assigned,
        submitted: s.submitted,
        approved: s.approved,
        rejected: s.rejected,
      })),
    };
  }
}

interface CatalogueRow {
  id: string; title: string; category: string; difficulty: string;
  xp_reward: number; is_hidden: boolean; editorial_tier: string;
  available_until: Date | null; place_id: string | null; unlock_rule_count: number;
}

const CATALOGUE_SELECT = `
  SELECT q.id, q.title, q.category, q.difficulty, q.xp_reward, q.is_hidden,
         q.editorial_tier, q.available_until, d.place_id,
         (SELECT count(*)::int FROM quest_unlock_rules r WHERE r.quest_id = q.id) AS unlock_rule_count
  FROM quests q
  LEFT JOIN quest_destinations d ON d.quest_id = q.id`;

function toAuthored(row: CatalogueRow): AuthoredQuest {
  return {
    id: row.id,
    title: row.title,
    category: row.category,
    difficulty: row.difficulty,
    xpReward: row.xp_reward,
    isHidden: row.is_hidden,
    editorialTier: row.editorial_tier,
    availableUntil: row.available_until,
    placeId: row.place_id,
    unlockRuleCount: row.unlock_rule_count,
  };
}
