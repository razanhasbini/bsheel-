import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestSubmission, type TestUser } from './support/e2e-harness.js';

// One comment fans out to several people, and the rule is subtractive: a
// mention wins over the owner notice and over the thread notice, and the
// author of the comment is never told about their own comment. Getting this
// wrong means either a silent mention or the same person being pinged three
// times for one comment, so the recipients are asserted row by row.
describe('comment notification recipients (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let moderator: TestUser;
  let owner: TestUser;
  let actor: TestUser;
  let threadOnly: TestUser;
  let mentionOnly: TestUser;
  let threadAndMentioned: TestUser;
  let post: TestSubmission;
  let everyone: TestUser[];

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    moderator = await harness.createUser({ role: 'moderator', prefix: 'c0' });
    owner = await harness.createUser({ prefix: 'c1' });
    actor = await harness.createUser({ prefix: 'c2' });
    threadOnly = await harness.createUser({ prefix: 'c3' });
    mentionOnly = await harness.createUser({ prefix: 'c4' });
    threadAndMentioned = await harness.createUser({ prefix: 'c5' });
    everyone = [owner, actor, threadOnly, mentionOnly, threadAndMentioned];

    post = await harness.createApprovedPost(owner, moderator);

    // Two prior comments make both users thread participants, which is the
    // only way to tell a thread notice apart from a mention notice.
    await harness.post(`/social/posts/${post.id}/comments`, threadOnly).send({ body: 'first comment here' }).expect(201);
    await harness
      .post(`/social/posts/${post.id}/comments`, threadAndMentioned)
      .send({ body: 'second comment here' })
      .expect(201);
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  const snapshot = async (): Promise<Set<string>> => {
    const result = await harness.database.query<{ id: string }>(
      'SELECT id FROM notifications WHERE user_id = ANY($1::uuid[])',
      [everyone.map((user) => user.id)],
    );
    return new Set(result.rows.map((row) => row.id));
  };

  const since = async (before: Set<string>) => {
    const result = await harness.database.query<{
      id: string;
      user_id: string;
      type: string;
      actor_id: string | null;
      reference_id: string | null;
    }>(
      `SELECT id, user_id, type, actor_id, reference_id FROM notifications
       WHERE user_id = ANY($1::uuid[]) ORDER BY created_at, id`,
      [everyone.map((user) => user.id)],
    );
    return result.rows.filter((row) => !before.has(row.id));
  };

  const label = (userId: string): string => {
    const named = everyone.find((user) => user.id === userId);
    return named ? named.username : userId;
  };

  it('notifies the owner, the other participants and each mentioned user exactly once', async () => {
    const before = await snapshot();

    await harness
      .post(`/social/posts/${post.id}/comments`, actor)
      .send({ body: `solid work @${mentionOnly.username} and @${threadAndMentioned.username} take a look` })
      .expect(201);

    const created = await since(before);
    const pairs = created.map((row) => `${label(row.user_id)}:${row.type}`).sort();

    expect(pairs).toEqual(
      [
        `${owner.username}:new_comment`,
        `${threadOnly.username}:comment_reply`,
        `${mentionOnly.username}:mention`,
        `${threadAndMentioned.username}:mention`,
      ].sort(),
    );

    // Never the actor, whatever role they also hold in the thread.
    expect(created.filter((row) => row.user_id === actor.id)).toHaveLength(0);
    // A mention replaces the thread notice rather than adding to it.
    expect(created.filter((row) => row.user_id === threadAndMentioned.id)).toHaveLength(1);
    // Every notification points back at the post and names the commenter.
    for (const row of created) {
      expect(row.reference_id).toBe(post.id);
      expect(row.actor_id).toBe(actor.id);
    }
  });

  it('gives a mentioned owner the mention instead of the owner notice', async () => {
    const before = await snapshot();

    await harness
      .post(`/social/posts/${post.id}/comments`, actor)
      .send({ body: `hey @${owner.username} what do you think of this` })
      .expect(201);

    const created = await since(before);
    const ownerRows = created.filter((row) => row.user_id === owner.id);
    expect(ownerRows).toHaveLength(1);
    expect(ownerRows[0].type).toBe('mention');
    expect(created.filter((row) => row.type === 'new_comment')).toHaveLength(0);
  });

  it('mentions a user once even when their handle appears twice', async () => {
    const before = await snapshot();

    await harness
      .post(`/social/posts/${post.id}/comments`, actor)
      .send({ body: `@${mentionOnly.username} seriously @${mentionOnly.username} look at this` })
      .expect(201);

    const created = await since(before);
    expect(created.filter((row) => row.user_id === mentionOnly.id)).toHaveLength(1);
    expect(created.filter((row) => row.user_id === mentionOnly.id)[0].type).toBe('mention');
  });

  it('does not notify the actor for a self mention', async () => {
    const before = await snapshot();

    await harness
      .post(`/social/posts/${post.id}/comments`, actor)
      .send({ body: `noting for myself @${actor.username} remember this` })
      .expect(201);

    const created = await since(before);
    expect(created.filter((row) => row.user_id === actor.id)).toHaveLength(0);
    expect(created.filter((row) => row.user_id === owner.id).map((row) => row.type)).toEqual(['new_comment']);
  });

  it('ignores a handle that belongs to nobody', async () => {
    const before = await snapshot();

    await harness
      .post(`/social/posts/${post.id}/comments`, actor)
      .send({ body: 'shout out to @nobodyhasthishandle at all' })
      .expect(201);

    const created = await since(before);
    expect(created.every((row) => ['new_comment', 'comment_reply'].includes(row.type))).toBe(true);
  });

  it('notifies nobody when the owner comments on their own post with no mentions', async () => {
    const solo = await harness.createUser({ prefix: 'c6' });
    everyone.push(solo);
    const soloPost = await harness.createApprovedPost(solo, moderator);
    const before = await snapshot();

    await harness.post(`/social/posts/${soloPost.id}/comments`, solo).send({ body: 'my own first note' }).expect(201);

    const created = await since(before);
    expect(created.filter((row) => row.reference_id === soloPost.id)).toHaveLength(0);
  });

  it('commits the comment and its outbox event together', async () => {
    const response = await harness
      .post(`/social/posts/${post.id}/comments`, threadOnly)
      .send({ body: 'and one more for the outbox' })
      .expect(201);

    expect(
      await harness.countRows('SELECT count(*) FROM comments WHERE id = $1', [response.body.data.id]),
    ).toBe(1);
    const events = await harness.outboxEvents(post.id, 'social.comment.changed');
    expect(
      events.filter((event) => event.payload.commentId === response.body.data.id && event.payload.operation === 'created'),
    ).toHaveLength(1);
  });

  it('refuses a comment on a post that is not publicly visible', async () => {
    const author = await harness.createUser({ prefix: 'c7' });
    const pending = await harness.createSubmission(author);
    const response = await harness
      .post(`/social/posts/${pending.id}/comments`, actor)
      .send({ body: 'should not be possible' })
      .expect(404);
    expect(response.body.error.code).toBe('POST_NOT_FOUND');
  });

  it('refuses a reply whose parent belongs to another post', async () => {
    const otherAuthor = await harness.createUser({ prefix: 'c8' });
    const otherPost = await harness.createApprovedPost(otherAuthor, moderator);
    const foreign = await harness
      .post(`/social/posts/${otherPost.id}/comments`, actor)
      .send({ body: 'a comment on another post' })
      .expect(201);

    const response = await harness
      .post(`/social/posts/${post.id}/comments`, actor)
      .send({ body: 'replying across posts', parentId: foreign.body.data.id })
      .expect(409);
    expect(response.body.error.code).toBe('INVALID_COMMENT_PARENT');
  });

  it('requires a token', async () => {
    await harness.post(`/social/posts/${post.id}/comments`).send({ body: 'anonymous comment' }).expect(401);
  });
});
