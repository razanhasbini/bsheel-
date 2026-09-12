import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness } from './support/e2e-harness.js';

// The request side of branded video exports (0050). The render itself needs
// ffmpeg and object storage and lives on the worker; what is pinned here is
// who may ask, for what, and what the answer looks like before a render
// exists.
describe('branded exports (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;

  beforeAll(async () => {
    harness = await E2eHarness.boot();
  }, 300_000);

  afterAll(async () => {
    await harness?.close();
  });

  it('refuses a photo post — photos are branded on the device', async () => {
    const admin = await harness.createUser({ role: 'super_admin', prefix: 'beAdmin' });
    const author = await harness.createUser({ prefix: 'beAuthor' });
    const post = await harness.createApprovedPost(author, admin);
    const response = await harness
      .post('/media/branded-exports', author)
      .send({ submissionId: post.id })
      .expect(400);
    expect(response.body.error?.code ?? response.body.code).toBe('NOT_A_VIDEO');
  });

  it('answers 404 for a post that does not exist or was never requested', async () => {
    const viewer = await harness.createUser({ prefix: 'beViewer' });
    await harness.post('/media/branded-exports', viewer).send({ submissionId: randomUUID() }).expect(404);
    await harness.get(`/media/branded-exports/${randomUUID()}`, viewer).expect(404);
  });

  it('validates the id', async () => {
    const viewer = await harness.createUser({ prefix: 'beViewer' });
    await harness.post('/media/branded-exports', viewer).send({ submissionId: 'nope' }).expect(400);
  });
});
