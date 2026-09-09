import { ConflictException, Injectable, NotFoundException } from '@nestjs/common';
import { DatabaseService, type DatabaseTransaction } from '../../../infrastructure/database/database.service.js';

/// Chains and collections, for the admin console (#56).
///
/// Both were created by migration 0024 and had no API surface at all, so a
/// multi-stage or cross-country quest — which works, and is tested — could
/// only be authored by someone with database access. That made a shipped
/// feature unreachable by the people meant to write content for it.
///
/// The schema does real work here and this code leans on it rather than
/// re-implementing it. `quest_chain_steps` is `PRIMARY KEY (chain_id,
/// step_order)` with `UNIQUE (quest_id)`, so a quest sits at exactly one
/// position in exactly one chain and the database is the thing that
/// guarantees it. What this layer adds is turning those violations into
/// error codes an admin UI can act on, rather than letting a `23505` reach
/// the client.

export interface ChainRecord {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly mode: string;
  readonly is_active: boolean;
  readonly created_at: Date;
  readonly step_count: number;
}

export interface CollectionRecord {
  readonly id: string;
  readonly name: string;
  readonly description: string;
  readonly country_code: string | null;
  readonly is_published: boolean;
  readonly created_at: Date;
  readonly quest_count: number;
}

@Injectable()
export class QuestCampaignsRepository {
  constructor(private readonly database: DatabaseService) {}

  // ── Chains ─────────────────────────────────────────────────────────

  async listChains(): Promise<readonly ChainRecord[]> {
    const result = await this.database.query<ChainRecord>(
      `SELECT c.*, count(s.quest_id)::int AS step_count
       FROM quest_chains c
       LEFT JOIN quest_chain_steps s ON s.chain_id = c.id
       GROUP BY c.id
       ORDER BY c.created_at DESC
       LIMIT 500`,
    );
    return result.rows;
  }

  /// A chain with its steps in order, and enough about each quest to render
  /// the shape — which is the question an admin actually has ("what is step
  /// 3, and is it assignable?").
  async chainDetail(id: string): Promise<Record<string, unknown> | null> {
    const chain = await this.database.query<ChainRecord>(
      `SELECT c.*, 0 AS step_count FROM quest_chains c WHERE c.id = $1`,
      [id],
    );
    if (!chain.rows[0]) return null;
    const steps = await this.database.query(
      `SELECT s.step_order, s.quest_id, q.title, q.category, q.difficulty,
              q.xp_reward, q.is_active, q.is_hidden,
              d.place_id, p.name AS place_name, p.country_code
       FROM quest_chain_steps s
       JOIN quests q ON q.id = s.quest_id
       LEFT JOIN quest_destinations d ON d.quest_id = q.id
       LEFT JOIN map_places p ON p.id = d.place_id
       WHERE s.chain_id = $1
       ORDER BY s.step_order`,
      [id],
    );
    return { ...chain.rows[0], step_count: steps.rowCount ?? 0, steps: steps.rows };
  }

  async createChain(input: {
    name: string;
    description: string;
    mode: 'solo' | 'group';
    isActive: boolean;
  }, actorId: string): Promise<ChainRecord> {
    const result = await this.database.query<ChainRecord>(
      `INSERT INTO quest_chains (name, description, mode, is_active, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *, 0 AS step_count`,
      [input.name.trim(), input.description.trim(), input.mode, input.isActive, actorId],
    );
    return result.rows[0];
  }

  async updateChain(id: string, input: {
    name?: string;
    description?: string;
    mode?: 'solo' | 'group';
    isActive?: boolean;
  }): Promise<ChainRecord | null> {
    const result = await this.database.query<ChainRecord>(
      `UPDATE quest_chains SET
         name = COALESCE($2, name),
         description = COALESCE($3, description),
         mode = COALESCE($4, mode),
         is_active = COALESCE($5, is_active),
         updated_at = now()
       WHERE id = $1
       RETURNING *, (SELECT count(*)::int FROM quest_chain_steps s WHERE s.chain_id = $1) AS step_count`,
      [id, input.name?.trim() ?? null, input.description?.trim() ?? null, input.mode ?? null, input.isActive ?? null],
    );
    return result.rows[0] ?? null;
  }

  /// Deleting a chain frees its quests to be used elsewhere — the steps
  /// cascade, the quests do not. That is the right shape: a chain is an
  /// arrangement of quests, not an owner of them.
  async deleteChain(id: string): Promise<void> {
    const result = await this.database.query('DELETE FROM quest_chains WHERE id = $1', [id]);
    if (!result.rowCount) throw new NotFoundException({ code: 'CHAIN_NOT_FOUND', message: 'Chain not found' });
  }

  /// Appends a quest as the next step.
  ///
  /// The order is computed here rather than taken from the client, because
  /// two admins appending at once would otherwise both claim the same
  /// `step_order` and one would lose to the primary key. Locking the chain
  /// row first makes the read-then-insert atomic.
  async appendStep(chainId: string, questId: string, actorId: string): Promise<{ step_order: number }> {
    return this.database.transaction(async (transaction) => {
      const chain = await transaction.query('SELECT id FROM quest_chains WHERE id = $1 FOR UPDATE', [chainId]);
      if (!chain.rowCount) throw new NotFoundException({ code: 'CHAIN_NOT_FOUND', message: 'Chain not found' });

      const quest = await transaction.query('SELECT id FROM quests WHERE id = $1', [questId]);
      if (!quest.rowCount) throw new NotFoundException({ code: 'QUEST_NOT_FOUND', message: 'Quest not found' });

      // Checked before inserting so the admin gets a reason rather than a
      // constraint name. The UNIQUE(quest_id) index is still the guarantee.
      const existing = await transaction.query<{ chain_id: string; step_order: number }>(
        'SELECT chain_id, step_order FROM quest_chain_steps WHERE quest_id = $1',
        [questId],
      );
      if (existing.rows[0]) {
        throw new ConflictException({
          code: 'QUEST_ALREADY_IN_CHAIN',
          message: existing.rows[0].chain_id === chainId
            ? `This quest is already step ${existing.rows[0].step_order} of this chain`
            : 'This quest already belongs to another chain, and a quest can only be one step',
        });
      }

      const next = await transaction.query<{ step_order: number }>(
        'SELECT COALESCE(max(step_order), 0) + 1 AS step_order FROM quest_chain_steps WHERE chain_id = $1',
        [chainId],
      );
      const order = next.rows[0].step_order;
      await transaction.query(
        'INSERT INTO quest_chain_steps (chain_id, quest_id, step_order) VALUES ($1, $2, $3)',
        [chainId, questId, order],
      );
      await this.audit(actorId, chainId, 'chain.step.append', { quest_id: questId, step_order: order }, transaction);
      return { step_order: order };
    });
  }

  /// Removes a step and closes the gap.
  ///
  /// Renumbering matters rather than being tidy-up: `offerable()` excludes
  /// any quest whose `step_order > 1`, and `assignSpecific` unlocks a step by
  /// looking for approved proof of `step_order - 1`. A hole in the sequence
  /// would leave every later step permanently unreachable.
  async removeStep(chainId: string, questId: string, actorId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      await transaction.query('SELECT id FROM quest_chains WHERE id = $1 FOR UPDATE', [chainId]);
      const removed = await transaction.query<{ step_order: number }>(
        'DELETE FROM quest_chain_steps WHERE chain_id = $1 AND quest_id = $2 RETURNING step_order',
        [chainId, questId],
      );
      if (!removed.rows[0]) {
        throw new NotFoundException({ code: 'CHAIN_STEP_NOT_FOUND', message: 'That quest is not a step of this chain' });
      }
      // Shifted down one at a time in ascending order: the primary key on
      // (chain_id, step_order) would collide on a bulk decrement.
      const later = await transaction.query<{ quest_id: string; step_order: number }>(
        'SELECT quest_id, step_order FROM quest_chain_steps WHERE chain_id = $1 AND step_order > $2 ORDER BY step_order',
        [chainId, removed.rows[0].step_order],
      );
      for (const step of later.rows) {
        await transaction.query(
          'UPDATE quest_chain_steps SET step_order = $3 WHERE chain_id = $1 AND quest_id = $2',
          [chainId, step.quest_id, step.step_order - 1],
        );
      }
      await this.audit(actorId, chainId, 'chain.step.remove', { quest_id: questId, was_step: removed.rows[0].step_order }, transaction);
    });
  }

  /// Moves a step to a new position, shifting the rest.
  ///
  /// The moved row is parked *above* the sequence first, so the intermediate
  /// shifts cannot collide with it on `PRIMARY KEY (chain_id, step_order)`.
  /// Parking it below — at 0 or a negative — would be the obvious trick and
  /// violates migration 0024's `CHECK (step_order >= 1)`, which is how the
  /// tests caught the first version of this.
  async reorderStep(chainId: string, questId: string, toOrder: number, actorId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      await transaction.query('SELECT id FROM quest_chains WHERE id = $1 FOR UPDATE', [chainId]);
      const current = await transaction.query<{ step_order: number }>(
        'SELECT step_order FROM quest_chain_steps WHERE chain_id = $1 AND quest_id = $2',
        [chainId, questId],
      );
      if (!current.rows[0]) {
        throw new NotFoundException({ code: 'CHAIN_STEP_NOT_FOUND', message: 'That quest is not a step of this chain' });
      }
      const total = await transaction.query<{ count: number }>(
        'SELECT count(*)::int AS count FROM quest_chain_steps WHERE chain_id = $1',
        [chainId],
      );
      const target = Math.min(Math.max(toOrder, 1), total.rows[0].count);
      const from = current.rows[0].step_order;
      if (target === from) return;

      // One past the end: satisfies the CHECK, and no real step occupies it.
      const parked = total.rows[0].count + 1;
      await transaction.query(
        'UPDATE quest_chain_steps SET step_order = $3 WHERE chain_id = $1 AND quest_id = $2',
        [chainId, questId, parked],
      );
      if (target < from) {
        // Shift the block down, highest first, so each row moves into a slot
        // the previous update has already vacated.
        const between = await transaction.query<{ quest_id: string; step_order: number }>(
          `SELECT quest_id, step_order FROM quest_chain_steps
           WHERE chain_id = $1 AND step_order >= $2 AND step_order < $3
           ORDER BY step_order DESC`,
          [chainId, target, from],
        );
        for (const step of between.rows) {
          await transaction.query(
            'UPDATE quest_chain_steps SET step_order = $3 WHERE chain_id = $1 AND quest_id = $2',
            [chainId, step.quest_id, step.step_order + 1],
          );
        }
      } else {
        const between = await transaction.query<{ quest_id: string; step_order: number }>(
          `SELECT quest_id, step_order FROM quest_chain_steps
           WHERE chain_id = $1 AND step_order > $2 AND step_order <= $3
           ORDER BY step_order ASC`,
          [chainId, from, target],
        );
        for (const step of between.rows) {
          await transaction.query(
            'UPDATE quest_chain_steps SET step_order = $3 WHERE chain_id = $1 AND quest_id = $2',
            [chainId, step.quest_id, step.step_order - 1],
          );
        }
      }
      await transaction.query(
        'UPDATE quest_chain_steps SET step_order = $3 WHERE chain_id = $1 AND quest_id = $2',
        [chainId, questId, target],
      );
      await this.audit(actorId, chainId, 'chain.step.reorder', { quest_id: questId, from, to: target }, transaction);
    });
  }

  // ── Collections ────────────────────────────────────────────────────

  async listCollections(): Promise<readonly CollectionRecord[]> {
    const result = await this.database.query<CollectionRecord>(
      `SELECT c.*, count(i.quest_id)::int AS quest_count
       FROM quest_collections c
       LEFT JOIN quest_collection_items i ON i.collection_id = c.id
       GROUP BY c.id
       ORDER BY c.created_at DESC
       LIMIT 500`,
    );
    return result.rows;
  }

  async collectionDetail(id: string): Promise<Record<string, unknown> | null> {
    const collection = await this.database.query<CollectionRecord>(
      `SELECT c.*, 0 AS quest_count,
              (SELECT name FROM map_countries WHERE code = c.country_code) AS country_name
       FROM quest_collections c WHERE c.id = $1`,
      [id],
    );
    if (!collection.rows[0]) return null;
    const items = await this.database.query(
      `SELECT q.id AS quest_id, q.title, q.category, q.difficulty, q.xp_reward,
              q.is_active, q.is_hidden
       FROM quest_collection_items i
       JOIN quests q ON q.id = i.quest_id
       WHERE i.collection_id = $1
       ORDER BY q.title, q.id`,
      [id],
    );
    return { ...collection.rows[0], quest_count: items.rowCount ?? 0, quests: items.rows };
  }

  async createCollection(input: {
    name: string;
    description: string;
    countryCode: string | null;
    isPublished: boolean;
  }, actorId: string): Promise<CollectionRecord> {
    const result = await this.database.query<CollectionRecord>(
      `INSERT INTO quest_collections (name, description, country_code, is_published, created_by)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *, 0 AS quest_count`,
      [input.name.trim(), input.description.trim(), input.countryCode, input.isPublished, actorId],
    );
    return result.rows[0];
  }

  async updateCollection(id: string, input: {
    name?: string;
    description?: string;
    countryCode?: string | null;
    isPublished?: boolean;
  }): Promise<CollectionRecord | null> {
    const result = await this.database.query<CollectionRecord>(
      `UPDATE quest_collections SET
         name = COALESCE($2, name),
         description = COALESCE($3, description),
         -- Distinguishes "leave it alone" (undefined) from "clear it"
         -- (explicit null), which COALESCE alone cannot express.
         country_code = CASE WHEN $5 THEN $4 ELSE country_code END,
         is_published = COALESCE($6, is_published),
         updated_at = now()
       WHERE id = $1
       RETURNING *, (SELECT count(*)::int FROM quest_collection_items i WHERE i.collection_id = $1) AS quest_count`,
      [
        id,
        input.name?.trim() ?? null,
        input.description?.trim() ?? null,
        input.countryCode ?? null,
        input.countryCode !== undefined,
        input.isPublished ?? null,
      ],
    );
    return result.rows[0] ?? null;
  }

  async deleteCollection(id: string): Promise<void> {
    const result = await this.database.query('DELETE FROM quest_collections WHERE id = $1', [id]);
    if (!result.rowCount) {
      throw new NotFoundException({ code: 'COLLECTION_NOT_FOUND', message: 'Collection not found' });
    }
  }

  /// Adds a quest to a collection. Idempotent: membership is a set, and an
  /// admin clicking twice should not see an error.
  async addToCollection(collectionId: string, questId: string, actorId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const collection = await transaction.query('SELECT id FROM quest_collections WHERE id = $1', [collectionId]);
      if (!collection.rowCount) {
        throw new NotFoundException({ code: 'COLLECTION_NOT_FOUND', message: 'Collection not found' });
      }
      const quest = await transaction.query('SELECT id FROM quests WHERE id = $1', [questId]);
      if (!quest.rowCount) throw new NotFoundException({ code: 'QUEST_NOT_FOUND', message: 'Quest not found' });

      await transaction.query(
        `INSERT INTO quest_collection_items (collection_id, quest_id) VALUES ($1, $2)
         ON CONFLICT DO NOTHING`,
        [collectionId, questId],
      );
      await this.audit(actorId, collectionId, 'collection.quest.add', { quest_id: questId }, transaction);
    });
  }

  async removeFromCollection(collectionId: string, questId: string, actorId: string): Promise<void> {
    await this.database.transaction(async (transaction) => {
      const removed = await transaction.query(
        'DELETE FROM quest_collection_items WHERE collection_id = $1 AND quest_id = $2',
        [collectionId, questId],
      );
      if (!removed.rowCount) {
        throw new NotFoundException({ code: 'COLLECTION_ITEM_NOT_FOUND', message: 'That quest is not in this collection' });
      }
      await this.audit(actorId, collectionId, 'collection.quest.remove', { quest_id: questId }, transaction);
    });
  }

  /// Quests eligible to become a chain step or a collection member.
  ///
  /// Chains exclude anything already in one, because `UNIQUE (quest_id)`
  /// means the picker would otherwise offer choices that cannot be taken.
  /// Collections do not, since membership is many-to-many by design.
  async assignableQuests(scope: 'chain' | 'collection', search: string): Promise<readonly Record<string, unknown>[]> {
    const pattern = `%${search.trim().toLowerCase()}%`;
    const result = await this.database.query(
      `SELECT q.id, q.title, q.category, q.difficulty, q.xp_reward, q.is_active, q.is_hidden
       FROM quests q
       WHERE ($2 = '%%' OR lower(q.title) LIKE $2)
         AND ($1 = 'collection' OR NOT EXISTS (
           SELECT 1 FROM quest_chain_steps s WHERE s.quest_id = q.id
         ))
       ORDER BY q.created_at DESC
       LIMIT 100`,
      [scope, pattern],
    );
    return result.rows;
  }

  /// Sensitive admin actions append an immutable audit record, as CLAUDE.md
  /// requires. Chain membership decides what content a player can reach, so
  /// it belongs in the same trail as moderation.
  private async audit(
    actorId: string,
    targetId: string,
    action: string,
    afterState: Record<string, unknown>,
    transaction: DatabaseTransaction,
  ): Promise<void> {
    await transaction.query(
      `INSERT INTO admin_audit_log (actor_id, action, target_type, target_id, after_state)
       VALUES ($1, $2, 'quest_campaign', $3, $4::jsonb)`,
      [actorId, action, targetId, JSON.stringify(afterState)],
    );
  }
}
