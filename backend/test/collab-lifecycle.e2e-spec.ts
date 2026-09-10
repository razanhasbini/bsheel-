import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/**
 * The group lifecycle: taking a slot, giving one up, and the ballot.
 *
 * Joining used to require the client to abandon its own quest first, as a
 * separate request, so a join that failed afterwards had already destroyed
 * the quest. Leaving did not exist at all, abandoning left the membership
 * row behind, and the ballot never closed.
 */
describe('collab group lifecycle (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let moderator: TestUser;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    moderator = await harness.createUser({ role: 'moderator', prefix: 'clbmod' });
  });

  afterAll(async () => {
    await harness.close();
  });

  /** Creates a group and returns its code plus the creator's assignment. */
  const openGroup = async (
    creator: TestUser,
    mode: 'with' | 'versus' = 'versus',
  ): Promise<{ code: string; groupId: string; userQuestId: string }> => {
    const quest = await harness.createQuest({ durationHours: 24 });
    const assignment = await harness.assignQuest(creator, quest.id);
    const response = await harness
      .post('/collab/groups', creator)
      .send({ userQuestId: assignment.id, mode })
      .expect(201);
    return {
      code: response.body.data.code,
      groupId: response.body.data.group_id ?? response.body.data.id,
      userQuestId: assignment.id,
    };
  };

  const activeQuestId = async (user: TestUser): Promise<string | null> => {
    const response = await harness.get('/quests/active', user).expect(200);
    return response.body.data?.id ?? null;
  };

  describe('POST /collab/groups/join', () => {
    it('refuses without the swap intent, leaving the quest in place', async () => {
      const creator = await harness.createUser({ prefix: 'clbc' });
      const joiner = await harness.createUser({ prefix: 'clbj' });
      const { code } = await openGroup(creator);

      const ownQuest = await harness.createQuest({ durationHours: 24 });
      const own = await harness.assignQuest(joiner, ownQuest.id);

      const response = await harness
        .post('/collab/groups/join', joiner)
        .send({ code })
        .expect(409);
      expect(response.body.error.code).toBe('ACTIVE_QUEST_EXISTS');
      expect(await activeQuestId(joiner)).toBe(own.id);
    });

    it('swaps the active quest for the group quest in one request', async () => {
      const creator = await harness.createUser({ prefix: 'clbc' });
      const joiner = await harness.createUser({ prefix: 'clbj' });
      const { code } = await openGroup(creator);

      const ownQuest = await harness.createQuest({ durationHours: 24 });
      const own = await harness.assignQuest(joiner, ownQuest.id);

      await harness
        .post('/collab/groups/join', joiner)
        .send({ code, abandonActiveQuest: true })
        .expect(201);

      const nowActive = await activeQuestId(joiner);
      expect(nowActive).not.toBe(own.id);
      expect(nowActive).not.toBeNull();
    });

    it('keeps the caller’s quest when the join fails', async () => {
      const creator = await harness.createUser({ prefix: 'clbc' });
      const joiner = await harness.createUser({ prefix: 'clbj' });
      const { code, groupId } = await openGroup(creator);

      const ownQuest = await harness.createQuest({ durationHours: 24 });
      const own = await harness.assignQuest(joiner, ownQuest.id);

      // The group expires between the user tapping JOIN and the request
      // landing — the window that used to cost them their quest.
      await harness.database.query(
        "UPDATE collab_groups SET expires_at = now() - interval '1 minute' WHERE id = $1",
        [groupId],
      );

      const response = await harness
        .post('/collab/groups/join', joiner)
        .send({ code, abandonActiveQuest: true })
        .expect(404);
      expect(response.body.error.code).toBe('COLLAB_GROUP_NOT_FOUND');

      // The whole point: the swap was atomic, so nothing was given up.
      expect(await activeQuestId(joiner)).toBe(own.id);
    });

    it('says a full group is full rather than claiming it does not exist', async () => {
      const creator = await harness.createUser({ prefix: 'clbc' });
      const { code, groupId } = await openGroup(creator);
      const { max_members: max } = (
        await harness.database.query<{ max_members: number }>(
          'SELECT max_members FROM collab_groups WHERE id = $1',
          [groupId],
        )
      ).rows[0];

      // Fill every remaining slot.
      for (let i = 1; i < max; i += 1) {
        const member = await harness.createUser({ prefix: 'clbm' });
        await harness.post('/collab/groups/join', member).send({ code }).expect(201);
      }

      const late = await harness.createUser({ prefix: 'clbl' });
      const response = await harness
        .post('/collab/groups/join', late)
        .send({ code })
        .expect(409);
      expect(response.body.error.code).toBe('COLLAB_GROUP_FULL');
    });
  });

  describe('DELETE /collab/groups/:groupId/members/me', () => {
    it('lets a member leave and keep the quest, freeing the slot', async () => {
      const creator = await harness.createUser({ prefix: 'clbc' });
      const member = await harness.createUser({ prefix: 'clbm' });
      const { code, groupId } = await openGroup(creator);
      await harness.post('/collab/groups/join', member).send({ code }).expect(201);
      const questBefore = await activeQuestId(member);

      await harness.delete(`/collab/groups/${groupId}/members/me`, member).expect(204);

      expect(await activeQuestId(member)).toBe(questBefore);
      const roster = await harness.database.query(
        'SELECT 1 FROM collab_group_members WHERE group_id = $1 AND user_id = $2',
        [groupId, member.id],
      );
      expect(roster.rowCount).toBe(0);
    });

    it('refuses when the caller is not a member', async () => {
      const creator = await harness.createUser({ prefix: 'clbc' });
      const outsider = await harness.createUser({ prefix: 'clbo' });
      const { groupId } = await openGroup(creator);
      const response = await harness
        .delete(`/collab/groups/${groupId}/members/me`, outsider)
        .expect(409);
      expect(response.body.error.code).toBe('NOT_COLLAB_MEMBER');
    });
  });

  describe('POST /collab/assignments/:id/abandon', () => {
    it('takes the member off the roster instead of leaving a ghost', async () => {
      const creator = await harness.createUser({ prefix: 'clbc' });
      const member = await harness.createUser({ prefix: 'clbm' });
      const { code, groupId } = await openGroup(creator);
      await harness.post('/collab/groups/join', member).send({ code }).expect(201);
      const questId = await activeQuestId(member);

      await harness.post(`/collab/assignments/${questId}/abandon`, member).expect(204);

      // The row used to survive: still counted against max_members, still
      // on the roster, still notified, with an expired quest behind it.
      const roster = await harness.database.query(
        'SELECT 1 FROM collab_group_members WHERE group_id = $1 AND user_id = $2',
        [groupId, member.id],
      );
      expect(roster.rowCount).toBe(0);
    });

    it('reopens a group that had closed only because it filled', async () => {
      const creator = await harness.createUser({ prefix: 'clbc' });
      const { code, groupId } = await openGroup(creator);
      const { max_members: max } = (
        await harness.database.query<{ max_members: number }>(
          'SELECT max_members FROM collab_groups WHERE id = $1',
          [groupId],
        )
      ).rows[0];

      const members: TestUser[] = [];
      for (let i = 1; i < max; i += 1) {
        const member = await harness.createUser({ prefix: 'clbm' });
        await harness.post('/collab/groups/join', member).send({ code }).expect(201);
        members.push(member);
      }
      const closed = await harness.database.query<{ status: string }>(
        'SELECT status::text FROM collab_groups WHERE id = $1',
        [groupId],
      );
      expect(closed.rows[0].status).toBe('closed');

      const leaver = members[members.length - 1]!;
      const questId = await activeQuestId(leaver);
      await harness.post(`/collab/assignments/${questId}/abandon`, leaver).expect(204);

      const reopened = await harness.database.query<{ status: string }>(
        'SELECT status::text FROM collab_groups WHERE id = $1',
        [groupId],
      );
      expect(reopened.rows[0].status).toBe('open');

      // And the freed slot is actually usable.
      const replacement = await harness.createUser({ prefix: 'clbr' });
      await harness.post('/collab/groups/join', replacement).send({ code }).expect(201);
    });
  });

  describe('PUT /collab/groups/:groupId/votes/:submissionId', () => {
    /** A group whose creator has an approved submission to be voted on. */
    const groupWithEntry = async () => {
      const creator = await harness.createUser({ prefix: 'clbc' });
      const quest = await harness.createQuest({ durationHours: 24 });
      const assignment = await harness.assignQuest(creator, quest.id);
      const group = await harness
        .post('/collab/groups', creator)
        .send({ userQuestId: assignment.id, mode: 'versus' })
        .expect(201);
      const groupId = group.body.data.group_id ?? group.body.data.id;

      const mediaKey = await harness.createMediaObject(creator);
      const submission = await harness
        .post('/submissions', creator)
        .send({
          userQuestId: assignment.id,
          mediaUrl: mediaKey,
          mediaType: 'image',
          caption: 'collab entry',
          showInFeed: true,
        })
        .expect(201);
      await harness
        .post(`/submissions/${submission.body.data.id}/approve`, moderator)
        .send({})
        .expect(204);
      return { creator, groupId, submissionId: submission.body.data.id as string };
    };

    it('refuses a vote for the voter’s own entry', async () => {
      const { creator, groupId, submissionId } = await groupWithEntry();
      const response = await harness
        .put(`/collab/groups/${groupId}/votes/${submissionId}`, creator)
        .expect(409);
      expect(response.body.error.code).toBe('COLLAB_SELF_VOTE');
    });

    it('accepts a vote from someone else', async () => {
      const { groupId, submissionId } = await groupWithEntry();
      const voter = await harness.createUser({ prefix: 'clbv' });
      await harness.put(`/collab/groups/${groupId}/votes/${submissionId}`, voter).expect(204);
    });

    it('closes the ballot when the group expires', async () => {
      const { groupId, submissionId } = await groupWithEntry();
      const voter = await harness.createUser({ prefix: 'clbv' });
      await harness.database.query(
        "UPDATE collab_groups SET expires_at = now() - interval '1 minute' WHERE id = $1",
        [groupId],
      );
      const response = await harness
        .put(`/collab/groups/${groupId}/votes/${submissionId}`, voter)
        .expect(409);
      expect(response.body.error.code).toBe('COLLAB_VOTING_CLOSED');
    });
  });
});
