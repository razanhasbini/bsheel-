import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness } from './support/e2e-harness.js';

// The review card's network panel reads one dossier per submission. The
// per-submission query shipped with a second WHERE glued onto a SELECT that
// already had one — a Postgres syntax error, so the endpoint 500'd on every
// submission while the list endpoint (which appends only ORDER BY) kept
// working and hid it. Both shapes are exercised here, through HTTP, so the
// SQL is actually parsed by the database rather than assumed to be.
describe('agent evidence dossier (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  it('answers null, not 500, for a submission with no verification run', async () => {
    const moderator = await harness.createUser({ role: 'moderator', prefix: 'aeMod' });
    const response = await harness
      .get(`/agent/evidence/submissions/${randomUUID()}`, moderator)
      .expect(200);
    expect(response.body.data).toBeNull();
  });

  it('lists recent dossiers for a moderator', async () => {
    const moderator = await harness.createUser({ role: 'moderator', prefix: 'aeMod' });
    const response = await harness.get('/agent/evidence?limit=5', moderator).expect(200);
    expect(Array.isArray(response.body.data)).toBe(true);
  });

  it('refuses an ordinary player', async () => {
    const player = await harness.createUser({ prefix: 'aePlayer' });
    await harness.get(`/agent/evidence/submissions/${randomUUID()}`, player).expect(403);
  });

  it('accepts a re-run request from a moderator and rejects a malformed id', async () => {
    const moderator = await harness.createUser({ role: 'moderator', prefix: 'aeMod' });
    const accepted = await harness
      .post(`/agent/evidence/submissions/${randomUUID()}/rerun`, moderator)
      .expect(202);
    expect(accepted.body.data.queued).toBe(true);
    await harness.post('/agent/evidence/submissions/not-a-uuid/rerun', moderator).expect(400);
  });
});
