import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestSubmission, type TestUser } from './support/e2e-harness.js';

// Blocking is the only safety tool a user has that the product promises works
// immediately and in both directions, and the follow/reaction/save toggles are
// the calls a flaky mobile connection retries most. Both are asserted against
// the rows, not just the status codes: a duplicate row here means a duplicate
// notification, a wrong count, or a blocked user reappearing in a feed.
describe('social graph and blocking (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let moderator: TestUser;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    moderator = await harness.createUser({ role: 'moderator', prefix: 's0' });
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  const feedIds = async (viewer: TestUser): Promise<string[]> => {
    const response = await harness.get('/feed?limit=50', viewer).expect(200);
    return response.body.data.map((row: { submission_id: string }) => row.submission_id);
  };

  describe('a block hides the feed in both directions', () => {
    let blocker: TestUser;
    let blocked: TestUser;
    let blockerPost: TestSubmission;
    let blockedPost: TestSubmission;

    beforeAll(async () => {
      blocker = await harness.createUser({ prefix: 's1' });
      blocked = await harness.createUser({ prefix: 's2' });
      blockerPost = await harness.createApprovedPost(blocker, moderator);
      blockedPost = await harness.createApprovedPost(blocked, moderator);
      await harness.post(`/social/users/${blocked.id}/follow`, blocker).send().expect(201);
      await harness.post(`/social/users/${blocker.id}/follow`, blocked).send().expect(201);
    }, 300_000);

    it('shows both posts before the block', async () => {
      expect(await feedIds(blocker)).toContain(blockedPost.id);
      expect(await feedIds(blocked)).toContain(blockerPost.id);
    });

    it('removes the blocked user posts from the blocker feed and the reverse', async () => {
      await harness
        .post(`/social/users/${blocked.id}/block`, blocker)
        .send({ reason: 'e2e block' })
        .expect(204);

      const blockerFeed = await feedIds(blocker);
      expect(blockerFeed).not.toContain(blockedPost.id);
      expect(blockerFeed).toContain(blockerPost.id);

      // The filter is symmetric: the blocked user also stops seeing the
      // blocker, so a block cannot be detected by its absence alone.
      const blockedFeed = await feedIds(blocked);
      expect(blockedFeed).not.toContain(blockerPost.id);
      expect(blockedFeed).toContain(blockedPost.id);
    });

    it('drops the follow edge in both directions', async () => {
      expect(
        await harness.countRows(
          `SELECT count(*) FROM follows
           WHERE (follower_id = $1 AND following_id = $2) OR (follower_id = $2 AND following_id = $1)`,
          [blocker.id, blocked.id],
        ),
      ).toBe(0);

      expect((await harness.get(`/social/users/${blocked.id}/following`, blocker).expect(200)).body.data.following).toBe(false);
      expect((await harness.get(`/social/users/${blocker.id}/following`, blocked).expect(200)).body.data.following).toBe(false);
    });

    it('files one report and notifies the admins once', async () => {
      expect(
        await harness.countRows(
          `SELECT count(*) FROM reports WHERE reporter_id = $1 AND reported_type = 'user' AND reported_id = $2`,
          [blocker.id, blocked.id],
        ),
      ).toBe(1);

      const notifications = await harness.notificationsFor(moderator.id);
      expect(notifications.filter((row) => row.type === 'content_report')).toHaveLength(1);
    });

    it('is idempotent: blocking again changes nothing', async () => {
      await harness.post(`/social/users/${blocked.id}/block`, blocker).send({ reason: 'again' }).expect(204);

      expect(
        await harness.countRows('SELECT count(*) FROM blocked_users WHERE blocker_id = $1 AND blocked_id = $2', [
          blocker.id,
          blocked.id,
        ]),
      ).toBe(1);
      expect(
        await harness.countRows(
          `SELECT count(*) FROM reports WHERE reporter_id = $1 AND reported_type = 'user' AND reported_id = $2`,
          [blocker.id, blocked.id],
        ),
      ).toBe(1);
      const notifications = await harness.notificationsFor(moderator.id);
      expect(notifications.filter((row) => row.type === 'content_report')).toHaveLength(1);
    });

    it('refuses a new follow in either direction while the block stands', async () => {
      const forward = await harness.post(`/social/users/${blocked.id}/follow`, blocker).send().expect(403);
      expect(forward.body.error.code).toBe('FOLLOW_BLOCKED');
      const reverse = await harness.post(`/social/users/${blocker.id}/follow`, blocked).send().expect(403);
      expect(reverse.body.error.code).toBe('FOLLOW_BLOCKED');
    });

    it('lists the block for the blocker', async () => {
      const response = await harness.get('/social/blocked-users', blocker).expect(200);
      expect(response.body.data.map((row: { id: string }) => row.id)).toContain(blocked.id);
      // The blocked user is not told, so their own list stays empty of this pair.
      const reverse = await harness.get('/social/blocked-users', blocked).expect(200);
      expect(reverse.body.data.map((row: { id: string }) => row.id)).not.toContain(blocker.id);
    });

    it('restores feed visibility on unblock but not the follow edge', async () => {
      await harness.delete(`/social/users/${blocked.id}/block`, blocker).expect(204);

      expect(await feedIds(blocker)).toContain(blockedPost.id);
      expect(await feedIds(blocked)).toContain(blockerPost.id);
      expect(
        await harness.countRows(
          `SELECT count(*) FROM follows
           WHERE (follower_id = $1 AND following_id = $2) OR (follower_id = $2 AND following_id = $1)`,
          [blocker.id, blocked.id],
        ),
      ).toBe(0);
    });

    it('refuses a self block', async () => {
      const response = await harness.post(`/social/users/${blocker.id}/block`, blocker).send({}).expect(409);
      expect(response.body.error.code).toBe('SELF_BLOCK');
    });
  });

  describe('repeat follows', () => {
    let follower: TestUser;
    let target: TestUser;

    beforeAll(async () => {
      follower = await harness.createUser({ prefix: 's3' });
      target = await harness.createUser({ prefix: 's4' });
    }, 300_000);

    it('returns the same row and notifies once however many times it is called', async () => {
      const first = await harness.post(`/social/users/${target.id}/follow`, follower).send().expect(201);
      const second = await harness.post(`/social/users/${target.id}/follow`, follower).send().expect(201);
      const third = await harness.post(`/social/users/${target.id}/follow`, follower).send().expect(201);

      expect(second.body.data.id).toBe(first.body.data.id);
      expect(third.body.data.id).toBe(first.body.data.id);

      expect(
        await harness.countRows('SELECT count(*) FROM follows WHERE follower_id = $1 AND following_id = $2', [
          follower.id,
          target.id,
        ]),
      ).toBe(1);

      // Only the insert notifies; the retries must stay silent.
      const notifications = await harness.notificationsFor(target.id);
      expect(notifications.filter((row) => row.type === 'new_follower')).toHaveLength(1);

      const counts = await harness.get(`/social/users/${target.id}/follow-counts`, follower).expect(200);
      expect(counts.body.data.followers).toBe(1);
    });

    it('is idempotent on unfollow too', async () => {
      await harness.delete(`/social/users/${target.id}/follow`, follower).expect(204);
      await harness.delete(`/social/users/${target.id}/follow`, follower).expect(204);
      expect(
        await harness.countRows('SELECT count(*) FROM follows WHERE follower_id = $1 AND following_id = $2', [
          follower.id,
          target.id,
        ]),
      ).toBe(0);
    });

    it('refuses a self follow', async () => {
      const response = await harness.post(`/social/users/${follower.id}/follow`, follower).send().expect(409);
      expect(response.body.error.code).toBe('SELF_FOLLOW');
    });
  });

  describe('repeat reactions', () => {
    let author: TestUser;
    let voter: TestUser;
    let post: TestSubmission;

    beforeAll(async () => {
      author = await harness.createUser({ prefix: 's5' });
      voter = await harness.createUser({ prefix: 's6' });
      post = await harness.createApprovedPost(author, moderator);
    }, 300_000);

    it('keeps one row and commits the reaction with its outbox event', async () => {
      const first = await harness.put(`/social/posts/${post.id}/vote`, voter).send({ type: 'upvote' }).expect(200);
      const repeat = await harness.put(`/social/posts/${post.id}/vote`, voter).send({ type: 'upvote' }).expect(200);
      expect(repeat.body.data.id).toBe(first.body.data.id);

      expect(
        await harness.countRows('SELECT count(*) FROM reactions WHERE submission_id = $1 AND user_id = $2', [
          post.id,
          voter.id,
        ]),
      ).toBe(1);

      // The domain row and its event are written by the same transaction, so
      // one can never exist without the other.
      const events = await harness.outboxEvents(post.id, 'social.reaction.changed');
      expect(events.length).toBeGreaterThanOrEqual(1);
      expect(events[0].payload).toMatchObject({ submissionId: post.id, userId: voter.id, type: 'upvote' });

      // Only the first insert notifies the author.
      const notifications = await harness.notificationsFor(author.id, post.id);
      expect(notifications.filter((row) => row.type === 'reaction_received')).toHaveLength(1);
    });

    it('switches the type in place rather than adding a row', async () => {
      const switched = await harness.put(`/social/posts/${post.id}/vote`, voter).send({ type: 'downvote' }).expect(200);
      expect(switched.body.data.type).toBe('downvote');

      expect(
        await harness.countRows('SELECT count(*) FROM reactions WHERE submission_id = $1 AND user_id = $2', [
          post.id,
          voter.id,
        ]),
      ).toBe(1);
      const notifications = await harness.notificationsFor(author.id, post.id);
      expect(notifications.filter((row) => row.type === 'reaction_received')).toHaveLength(1);

      const read = await harness.get(`/social/posts/${post.id}/vote`, voter).expect(200);
      expect(read.body.data.type).toBe('downvote');
    });

    it('emits nothing extra when a removal has nothing to remove', async () => {
      await harness.delete(`/social/posts/${post.id}/vote`, voter).expect(204);
      const afterFirst = (await harness.outboxEvents(post.id, 'social.reaction.changed')).length;

      await harness.delete(`/social/posts/${post.id}/vote`, voter).expect(204);
      expect((await harness.outboxEvents(post.id, 'social.reaction.changed')).length).toBe(afterFirst);
      expect(
        await harness.countRows('SELECT count(*) FROM reactions WHERE submission_id = $1 AND user_id = $2', [
          post.id,
          voter.id,
        ]),
      ).toBe(0);
    });

    it('refuses a reaction to your own post', async () => {
      const response = await harness.put(`/social/posts/${post.id}/vote`, author).send({ type: 'upvote' }).expect(403);
      expect(response.body.error.code).toBe('SELF_REACTION');
    });
  });

  describe('repeat saves', () => {
    let saver: TestUser;
    let post: TestSubmission;
    let questId: string;

    beforeAll(async () => {
      const author = await harness.createUser({ prefix: 's7' });
      saver = await harness.createUser({ prefix: 's8' });
      const quest = await harness.createQuest();
      questId = quest.id;
      post = await harness.createApprovedPost(author, moderator, { questId });
    }, 300_000);

    it('saves a post at most once', async () => {
      await harness.put(`/social/saved/posts/${post.id}`, saver).expect(204);
      await harness.put(`/social/saved/posts/${post.id}`, saver).expect(204);

      expect(
        await harness.countRows('SELECT count(*) FROM saved_posts WHERE user_id = $1 AND submission_id = $2', [
          saver.id,
          post.id,
        ]),
      ).toBe(1);
      expect((await harness.get(`/social/saved/posts/${post.id}`, saver).expect(200)).body.data.saved).toBe(true);
      const list = await harness.get('/social/saved/posts', saver).expect(200);
      expect(list.body.data.filter((row: { submission_id: string }) => row.submission_id === post.id)).toHaveLength(1);
    });

    it('unsaves idempotently', async () => {
      await harness.delete(`/social/saved/posts/${post.id}`, saver).expect(204);
      await harness.delete(`/social/saved/posts/${post.id}`, saver).expect(204);
      expect(
        await harness.countRows('SELECT count(*) FROM saved_posts WHERE user_id = $1 AND submission_id = $2', [
          saver.id,
          post.id,
        ]),
      ).toBe(0);
      expect((await harness.get(`/social/saved/posts/${post.id}`, saver).expect(200)).body.data.saved).toBe(false);
    });

    it('saves a quest at most once', async () => {
      await harness.put(`/social/saved/quests/${questId}`, saver).expect(204);
      await harness.put(`/social/saved/quests/${questId}`, saver).expect(204);

      expect(
        await harness.countRows('SELECT count(*) FROM saved_quests WHERE user_id = $1 AND quest_id = $2', [
          saver.id,
          questId,
        ]),
      ).toBe(1);
      expect((await harness.get(`/social/saved/quests/${questId}`, saver).expect(200)).body.data.saved).toBe(true);

      await harness.delete(`/social/saved/quests/${questId}`, saver).expect(204);
      await harness.delete(`/social/saved/quests/${questId}`, saver).expect(204);
      expect(
        await harness.countRows('SELECT count(*) FROM saved_quests WHERE user_id = $1 AND quest_id = $2', [
          saver.id,
          questId,
        ]),
      ).toBe(0);
    });

    it('refuses to save an unknown post or quest', async () => {
      const post404 = await harness.put('/social/saved/posts/00000000-0000-4000-8000-000000000000', saver).expect(404);
      expect(post404.body.error.code).toBe('POST_NOT_FOUND');
      const quest404 = await harness.put('/social/saved/quests/00000000-0000-4000-8000-000000000000', saver).expect(404);
      expect(quest404.body.error.code).toBe('QUEST_NOT_FOUND');
    });
  });

  describe('repeat reports', () => {
    it('rejects the same report twice with DUPLICATE_REPORT', async () => {
      const reporter = await harness.createUser({ prefix: 's9' });
      const reported = await harness.createUser({ prefix: 'sa' });

      const first = await harness
        .post('/social/reports', reporter)
        .send({ reportedType: 'user', reportedId: reported.id, reason: 'e2e duplicate report' })
        .expect(201);
      expect(first.body.data.id).toBeTruthy();

      const second = await harness
        .post('/social/reports', reporter)
        .send({ reportedType: 'user', reportedId: reported.id, reason: 'e2e duplicate report' })
        .expect(409);
      expect(second.body.error.code).toBe('DUPLICATE_REPORT');

      expect(
        await harness.countRows('SELECT count(*) FROM reports WHERE reporter_id = $1 AND reported_id = $2', [
          reporter.id,
          reported.id,
        ]),
      ).toBe(1);
    });
  });
});
