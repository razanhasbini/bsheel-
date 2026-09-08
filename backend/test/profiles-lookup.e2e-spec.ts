import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

// Usernames are stored as citext, so a handle typed with any capitalisation
// has to resolve to the same profile. The app deep-links to profiles by
// handle, which makes this route the only place a stray uppercase letter
// could turn into a 404 for a real account.
describe('profile lookup by username (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let user: TestUser;
  let viewer: TestUser;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    user = await harness.createUser({ prefix: 'p1' });
    viewer = await harness.createUser({ prefix: 'p2' });
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  it('resolves the exact handle', async () => {
    const response = await harness.get(`/profiles/by-username/${user.username}`, viewer).expect(200);
    expect(response.body.data.id).toBe(user.id);
    expect(response.body.data.username).toBe(user.username);
    expect(response.body.data.display_name).toBe(user.displayName);
  });

  it('resolves the handle case-insensitively', async () => {
    const upper = await harness.get(`/profiles/by-username/${user.username.toUpperCase()}`, viewer).expect(200);
    expect(upper.body.data.id).toBe(user.id);

    const mixed = user.username
      .split('')
      .map((character, index) => (index % 2 === 0 ? character.toUpperCase() : character))
      .join('');
    const alternating = await harness.get(`/profiles/by-username/${mixed}`, viewer).expect(200);
    expect(alternating.body.data.id).toBe(user.id);
  });

  it('returns the same payload as the id route', async () => {
    const byUsername = await harness.get(`/profiles/by-username/${user.username}`, viewer).expect(200);
    const byId = await harness.get(`/profiles/${user.id}`, viewer).expect(200);
    expect(byUsername.body.data).toEqual(byId.body.data);
  });

  it('returns PROFILE_NOT_FOUND for an unknown handle', async () => {
    const response = await harness.get('/profiles/by-username/nobodyownsthishandle', viewer).expect(404);
    expect(response.body.error.code).toBe('PROFILE_NOT_FOUND');
  });

  it('does not match a partial handle', async () => {
    await harness.get(`/profiles/by-username/${user.username.slice(0, 4)}`, viewer).expect(404);
    await harness.get(`/profiles/by-username/${user.username}x`, viewer).expect(404);
  });

  it('requires a token', async () => {
    await harness.get(`/profiles/by-username/${user.username}`).expect(401);
  });
});
