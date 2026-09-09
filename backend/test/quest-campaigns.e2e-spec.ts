import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// Admin management of chains and collections (#56).
///
/// The interesting behaviour is ordering, and it is load-bearing rather than
/// cosmetic: `QuestsRepository.offerable()` excludes any quest whose
/// `step_order > 1`, and `assignSpecific` unlocks a step by looking for
/// approved proof of `step_order - 1`. A gap or a duplicate in the sequence
/// leaves every later step permanently unreachable — silently, because
/// nothing errors. So the reordering paths are tested by reading the whole
/// sequence back, not by trusting a status code.
describe('quest campaigns admin (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let admin: TestUser;
  let moderator: TestUser;

  const chainSteps = async (chainId: string): Promise<{ order: number; questId: string }[]> => {
    const response = await harness.get(`/quest-campaigns/chains/${chainId}`, admin).expect(200);
    return response.body.data.steps.map((step: { step_order: number; quest_id: string }) => ({
      order: step.step_order,
      questId: step.quest_id,
    }));
  };

  /// A chain of N quests, appended in order. Returns the quest ids.
  const chainOf = async (size: number): Promise<{ chainId: string; questIds: string[] }> => {
    const created = await harness
      .post('/quest-campaigns/chains', admin)
      .send({ name: `Chain ${harness.uniqueName('c')}`, description: 'Fixture chain' })
      .expect(201);
    const chainId = created.body.data.id;
    const questIds: string[] = [];
    for (let index = 0; index < size; index += 1) {
      const quest = await harness.createQuest({ title: `Step ${index + 1} ${harness.uniqueName('q')}` });
      await harness
        .post(`/quest-campaigns/chains/${chainId}/steps`, admin)
        .send({ questId: quest.id })
        .expect(201);
      questIds.push(quest.id);
    }
    return { chainId, questIds };
  };

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    admin = await harness.createUser({ role: 'super_admin', prefix: 'campadm' });
    moderator = await harness.createUser({ role: 'moderator', prefix: 'campmod' });
  });

  afterAll(async () => {
    await harness?.close();
  });

  describe('chains', () => {
    it('creates a chain and appends steps in order', async () => {
      const { chainId, questIds } = await chainOf(3);
      expect(await chainSteps(chainId)).toEqual([
        { order: 1, questId: questIds[0] },
        { order: 2, questId: questIds[1] },
        { order: 3, questId: questIds[2] },
      ]);
    });

    // `step_order` is decided server-side precisely so two admins appending
    // at once cannot both claim the same position and lose to the primary
    // key. The client never sends a position.
    it('assigns positions server-side, not from the request', async () => {
      const { chainId } = await chainOf(1);
      const quest = await harness.createQuest();
      const response = await harness
        .post(`/quest-campaigns/chains/${chainId}/steps`, admin)
        .send({ questId: quest.id, stepOrder: 99 })
        .expect(400);
      // `forbidNonWhitelisted` rejects the extra property outright, which is
      // the stronger guarantee: the field cannot be silently ignored either.
      expect(response.body.error.message).toBeTruthy();
    });

    // UNIQUE (quest_id) means a quest is one step of one chain. The admin
    // gets a reason rather than a constraint name.
    it('refuses a quest that already belongs to a chain, and says where', async () => {
      const { chainId, questIds } = await chainOf(2);
      const sameChain = await harness
        .post(`/quest-campaigns/chains/${chainId}/steps`, admin)
        .send({ questId: questIds[0] })
        .expect(409);
      expect(sameChain.body.error.code).toBe('QUEST_ALREADY_IN_CHAIN');
      expect(sameChain.body.error.message).toContain('already step 1');

      const other = await chainOf(0);
      const otherChain = await harness
        .post(`/quest-campaigns/chains/${other.chainId}/steps`, admin)
        .send({ questId: questIds[1] })
        .expect(409);
      expect(otherChain.body.error.message).toContain('another chain');
    });

    // The case that would silently break the chain: a hole at position 2
    // makes step 3 unreachable forever, because nothing has approved proof
    // of a step that no longer exists.
    it('closes the gap when a middle step is removed', async () => {
      const { chainId, questIds } = await chainOf(4);
      await harness.delete(`/quest-campaigns/chains/${chainId}/steps/${questIds[1]}`, admin).expect(204);
      expect(await chainSteps(chainId)).toEqual([
        { order: 1, questId: questIds[0] },
        { order: 2, questId: questIds[2] },
        { order: 3, questId: questIds[3] },
      ]);
    });

    it('frees a removed quest to be used in another chain', async () => {
      const { chainId, questIds } = await chainOf(2);
      await harness.delete(`/quest-campaigns/chains/${chainId}/steps/${questIds[0]}`, admin).expect(204);
      const other = await chainOf(0);
      await harness
        .post(`/quest-campaigns/chains/${other.chainId}/steps`, admin)
        .send({ questId: questIds[0] })
        .expect(201);
    });

    it('moves a step earlier, shifting the rest down', async () => {
      const { chainId, questIds } = await chainOf(4);
      await harness
        .patch(`/quest-campaigns/chains/${chainId}/steps`, admin)
        .send({ questId: questIds[3], toOrder: 2 })
        .expect(200);
      expect(await chainSteps(chainId)).toEqual([
        { order: 1, questId: questIds[0] },
        { order: 2, questId: questIds[3] },
        { order: 3, questId: questIds[1] },
        { order: 4, questId: questIds[2] },
      ]);
    });

    it('moves a step later, shifting the rest up', async () => {
      const { chainId, questIds } = await chainOf(4);
      await harness
        .patch(`/quest-campaigns/chains/${chainId}/steps`, admin)
        .send({ questId: questIds[0], toOrder: 3 })
        .expect(200);
      expect(await chainSteps(chainId)).toEqual([
        { order: 1, questId: questIds[1] },
        { order: 2, questId: questIds[2] },
        { order: 3, questId: questIds[0] },
        { order: 4, questId: questIds[3] },
      ]);
    });

    it('clamps an out-of-range position to an end rather than failing', async () => {
      const { chainId, questIds } = await chainOf(3);
      await harness
        .patch(`/quest-campaigns/chains/${chainId}/steps`, admin)
        .send({ questId: questIds[0], toOrder: 99 })
        .expect(200);
      const steps = await chainSteps(chainId);
      expect(steps[steps.length - 1].questId).toBe(questIds[0]);
      // Still 1..n with no gaps, which is the property that actually matters.
      expect(steps.map((step) => step.order)).toEqual([1, 2, 3]);
    });

    it('is a no-op when a step is moved to where it already is', async () => {
      const { chainId, questIds } = await chainOf(3);
      await harness
        .patch(`/quest-campaigns/chains/${chainId}/steps`, admin)
        .send({ questId: questIds[1], toOrder: 2 })
        .expect(200);
      expect(await chainSteps(chainId)).toEqual([
        { order: 1, questId: questIds[0] },
        { order: 2, questId: questIds[1] },
        { order: 3, questId: questIds[2] },
      ]);
    });

    it('deletes a chain without deleting its quests', async () => {
      const { chainId, questIds } = await chainOf(2);
      await harness.delete(`/quest-campaigns/chains/${chainId}`, admin).expect(204);
      await harness.get(`/quest-campaigns/chains/${chainId}`, admin).expect(404);
      // The quests survive — a chain arranges quests, it does not own them.
      const quest = await harness.get(`/quests/${questIds[0]}`, admin).expect(200);
      expect(quest.body.data.id).toBe(questIds[0]);
    });

    it('reports a missing chain and a missing step distinctly', async () => {
      const absent = '00000000-0000-4000-8000-000000000000';
      await harness.get(`/quest-campaigns/chains/${absent}`, admin).expect(404);
      const { chainId } = await chainOf(1);
      const stray = await harness.createQuest();
      const response = await harness
        .delete(`/quest-campaigns/chains/${chainId}/steps/${stray.id}`, admin)
        .expect(404);
      expect(response.body.error.code).toBe('CHAIN_STEP_NOT_FOUND');
    });
  });

  describe('collections', () => {
    const collection = async (body: Record<string, unknown> = {}): Promise<string> => {
      const response = await harness
        .post('/quest-campaigns/collections', admin)
        .send({ name: `Collection ${harness.uniqueName('col')}`, ...body })
        .expect(201);
      return response.body.data.id;
    };

    it('creates a collection and adds quests to it', async () => {
      const id = await collection({ description: 'Discover somewhere' });
      const first = await harness.createQuest();
      const second = await harness.createQuest();
      await harness.post(`/quest-campaigns/collections/${id}/quests`, admin).send({ questId: first.id }).expect(204);
      await harness.post(`/quest-campaigns/collections/${id}/quests`, admin).send({ questId: second.id }).expect(204);

      const detail = await harness.get(`/quest-campaigns/collections/${id}`, admin).expect(200);
      expect(detail.body.data.quest_count).toBe(2);
      expect(detail.body.data.quests.map((q: { quest_id: string }) => q.quest_id).sort())
        .toEqual([first.id, second.id].sort());
    });

    // Membership is a set, so an admin clicking twice is not an error.
    it('is idempotent when the same quest is added twice', async () => {
      const id = await collection();
      const quest = await harness.createQuest();
      await harness.post(`/quest-campaigns/collections/${id}/quests`, admin).send({ questId: quest.id }).expect(204);
      await harness.post(`/quest-campaigns/collections/${id}/quests`, admin).send({ questId: quest.id }).expect(204);
      const detail = await harness.get(`/quest-campaigns/collections/${id}`, admin).expect(200);
      expect(detail.body.data.quest_count).toBe(1);
    });

    // Many-to-many by design: a quest can be in a country journey and a
    // seasonal campaign at once. This is the difference from a chain.
    it('lets one quest belong to several collections', async () => {
      const first = await collection();
      const second = await collection();
      const quest = await harness.createQuest();
      await harness.post(`/quest-campaigns/collections/${first}/quests`, admin).send({ questId: quest.id }).expect(204);
      await harness.post(`/quest-campaigns/collections/${second}/quests`, admin).send({ questId: quest.id }).expect(204);
      for (const id of [first, second]) {
        const detail = await harness.get(`/quest-campaigns/collections/${id}`, admin).expect(200);
        expect(detail.body.data.quest_count).toBe(1);
      }
    });

    it('accepts a known country and rejects an unknown one', async () => {
      const id = await collection({ countryCode: 'LB' });
      const detail = await harness.get(`/quest-campaigns/collections/${id}`, admin).expect(200);
      expect(detail.body.data.country_code).toBe('LB');
      expect(detail.body.data.country_name).toBe('Lebanon');

      // The foreign key to map_countries is the real guard.
      await harness
        .post('/quest-campaigns/collections', admin)
        .send({ name: 'Nowhere', countryCode: 'ZZ' })
        .expect(500);
    });

    it('rejects a malformed country code before it reaches the database', async () => {
      await harness
        .post('/quest-campaigns/collections', admin)
        .send({ name: 'Bad code', countryCode: 'lebanon' })
        .expect(400);
    });

    // Distinguishing "leave it alone" from "clear it" is why the repository
    // does not use COALESCE for this column.
    it('clears a country with an empty string and leaves it alone when omitted', async () => {
      const id = await collection({ countryCode: 'LB' });

      await harness.patch(`/quest-campaigns/collections/${id}`, admin).send({ name: 'Renamed' }).expect(200);
      let detail = await harness.get(`/quest-campaigns/collections/${id}`, admin).expect(200);
      expect(detail.body.data.country_code).toBe('LB');
      expect(detail.body.data.name).toBe('Renamed');

      await harness.patch(`/quest-campaigns/collections/${id}`, admin).send({ countryCode: '' }).expect(200);
      detail = await harness.get(`/quest-campaigns/collections/${id}`, admin).expect(200);
      expect(detail.body.data.country_code).toBeNull();
    });

    it('removes a quest and reports one that was never a member', async () => {
      const id = await collection();
      const quest = await harness.createQuest();
      await harness.post(`/quest-campaigns/collections/${id}/quests`, admin).send({ questId: quest.id }).expect(204);
      await harness.delete(`/quest-campaigns/collections/${id}/quests/${quest.id}`, admin).expect(204);

      const response = await harness
        .delete(`/quest-campaigns/collections/${id}/quests/${quest.id}`, admin)
        .expect(404);
      expect(response.body.error.code).toBe('COLLECTION_ITEM_NOT_FOUND');
    });

    it('deletes a collection without deleting its quests', async () => {
      const id = await collection();
      const quest = await harness.createQuest();
      await harness.post(`/quest-campaigns/collections/${id}/quests`, admin).send({ questId: quest.id }).expect(204);
      await harness.delete(`/quest-campaigns/collections/${id}`, admin).expect(204);
      await harness.get(`/quest-campaigns/collections/${id}`, admin).expect(404);
      await harness.get(`/quests/${quest.id}`, admin).expect(200);
    });
  });

  describe('assignable quests', () => {
    // The chain picker must not offer a choice that cannot be taken, since
    // UNIQUE (quest_id) would reject it.
    it('hides quests already in a chain from the chain picker only', async () => {
      const { questIds } = await chainOf(1);
      const inChain = questIds[0];

      const forChain = await harness
        .get('/quest-campaigns/assignable-quests?scope=chain', admin)
        .expect(200);
      expect(forChain.body.data.map((q: { id: string }) => q.id)).not.toContain(inChain);

      // Collections are many-to-many, so the same quest stays offerable.
      const forCollection = await harness
        .get('/quest-campaigns/assignable-quests?scope=collection', admin)
        .expect(200);
      expect(forCollection.body.data.map((q: { id: string }) => q.id)).toContain(inChain);
    });

    it('filters by title', async () => {
      const needle = harness.uniqueName('needle');
      const quest = await harness.createQuest({ title: `Findable ${needle}` });
      const response = await harness
        .get(`/quest-campaigns/assignable-quests?search=${needle}`, admin)
        .expect(200);
      expect(response.body.data.map((q: { id: string }) => q.id)).toEqual([quest.id]);
    });
  });

  describe('authorisation', () => {
    // super_admin rather than moderator: chain membership decides what
    // content a player can reach, which is authoring rather than moderation,
    // and it matches how quest creation is already gated.
    it('refuses a moderator and a signed-out caller', async () => {
      await harness.get('/quest-campaigns/chains', moderator).expect(403);
      await harness.post('/quest-campaigns/chains', moderator).send({ name: 'Nope' }).expect(403);
      await harness.get('/quest-campaigns/chains').expect(401);
      await harness.get('/quest-campaigns/collections').expect(401);
    });
  });

  describe('audit trail', () => {
    // CLAUDE.md requires sensitive admin actions to append an immutable
    // record, and chain membership decides reachable content.
    it('records who changed a chain', async () => {
      const { chainId, questIds } = await chainOf(2);
      const rows = await harness.auditRows('chain.step.append', chainId);
      expect(rows.length).toBeGreaterThanOrEqual(2);
      expect(rows.every((row) => row.actor_id === admin.id)).toBe(true);
      expect(rows.some((row) => (row.after_state as { quest_id?: string })?.quest_id === questIds[0])).toBe(true);
    });
  });
});
