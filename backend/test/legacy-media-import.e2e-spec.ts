import { execFile } from 'node:child_process';
import { createServer, type Server } from 'node:http';
import { promisify } from 'node:util';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { cameraPhoto } from './support/proof-fixtures.js';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

const run = promisify(execFile);

/// The legacy media import (#57), end to end against real storage.
///
/// `import-legacy.mjs` carries `media_url` across verbatim and creates no
/// media rows, so an imported submission points at a path that does not
/// resolve against the new bucket — and signed-URL serving, proof
/// verification and the media quota all silently see nothing, because every
/// one of them keys off `media_objects`.
///
/// A local HTTP server stands in for legacy storage. That is closer to the
/// real thing than pointing at MinIO would be: legacy objects are fetched
/// over plain HTTP from somewhere this process has no credentials for, which
/// is exactly what the script has to handle.
describe('legacy media import (e2e)', { timeout: 180_000 }, () => {
  let harness: E2eHarness;
  let author: TestUser;
  let legacy: Server;
  let legacyBase: string;
  let photo: Buffer;

  /// A submission in the state `import-legacy.mjs` leaves behind: the row is
  /// there, `media_url` points at a legacy path, and nothing links it to any
  /// media object.
  const importedSubmission = async (legacyPath: string): Promise<string> => {
    const submission = await harness.createSubmission(author, { caption: 'imported from legacy' });
    await harness.database.query(
      'DELETE FROM media_submission_links WHERE submission_id = $1',
      [submission.id],
    );
    await harness.database.query(
      'DELETE FROM media_objects WHERE submission_id = $1',
      [submission.id],
    );
    await harness.database.query('UPDATE submissions SET media_url = $2 WHERE id = $1', [
      submission.id,
      legacyPath,
    ]);
    return submission.id;
  };

  /// `harness.submission()` projects the review-state columns and not
  /// `media_url`, which is the one column this suite is about.
  const mediaUrlOf = async (submissionId: string): Promise<string> => {
    const result = await harness.database.query<{ media_url: string }>(
      'SELECT media_url FROM submissions WHERE id = $1',
      [submissionId],
    );
    return result.rows[0].media_url;
  };

  const importMedia = (args: readonly string[], extraEnv: Record<string, string> = {}) =>
    run('node', ['scripts/legacy-import/import-media.mjs', ...args], {
      cwd: process.cwd(),
      env: { ...process.env, LEGACY_MEDIA_BASE_URL: legacyBase, ...extraEnv },
      timeout: 120_000,
    });

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    author = await harness.createUser({ prefix: 'legmedia' });
    photo = await cameraPhoto({ capturedAt: new Date() });

    // Serves `/storage/…` (the legacy paths) AND `/submissions/…` (the key
    // shape the real upload flow produces). The second one is what makes the
    // "never touches a live submission" case able to fail: if the script
    // wrongly treats a live submission as unmigrated, its key resolves here,
    // the bytes are fetched, and `media_url` is rewritten — which the
    // assertion then catches. With only `/storage/` served, that case passed
    // because the fetch 404'd, not because the submission was excluded.
    //
    // `/nowhere/…` is left unserved, so the failure path stays testable.
    legacy = createServer((request, response) => {
      if (request.url?.startsWith('/storage/') || request.url?.startsWith('/submissions/')) {
        response.writeHead(200, { 'content-type': 'image/jpeg', 'content-length': photo.length });
        response.end(photo);
        return;
      }
      response.writeHead(404).end();
    });
    await new Promise<void>((done) => legacy.listen(0, '127.0.0.1', done));
    const address = legacy.address();
    legacyBase = `http://127.0.0.1:${typeof address === 'object' && address ? address.port : 0}`;
  }, 300_000);

  afterAll(async () => {
    await new Promise<void>((done) => legacy?.close(() => done()));
    await harness?.close();
  });

  it('reports what it would migrate, and writes nothing', async () => {
    const submissionId = await importedSubmission('storage/proof/one.jpg');

    const { stdout } = await importMedia([]);
    expect(stdout).toContain('Dry run');

    // Nothing written: no object row, and the legacy path is untouched.
    expect(
      await harness.countRows('SELECT count(*) FROM media_objects WHERE submission_id = $1', [submissionId]),
    ).toBe(0);
    expect(await mediaUrlOf(submissionId)).toBe('storage/proof/one.jpg');
  });

  it('fetches the bytes, stores them, and records the object the upload flow would have', async () => {
    const submissionId = await importedSubmission('storage/proof/two.jpg');

    await importMedia(['--apply', '--limit', '25']);

    const media = await harness.database.query<{
      object_key: string;
      content_type: string;
      status: string;
      kind: string;
      stored_size_bytes: string;
      content_md5: string;
      etag: string | null;
    }>(
      `SELECT object_key, content_type, status::text, kind::text, stored_size_bytes, content_md5, etag
       FROM media_objects WHERE submission_id = $1`,
      [submissionId],
    );
    expect(media.rowCount).toBe(1);
    const object = media.rows[0];
    expect(object.status).toBe('ready');
    expect(object.kind).toBe('submission');
    expect(object.content_type).toBe('image/jpeg');
    // The key convention the real flow produces, so nothing downstream has to
    // special-case an imported object.
    expect(object.object_key).toMatch(new RegExp(`^submissions/${author.id}/[0-9a-f-]{36}\\.jpg$`));
    expect(Number(object.stored_size_bytes)).toBe(photo.length);
    // content_md5, not the etag: a multipart etag is a hash of part hashes
    // and is not comparable across objects, which is why the column exists.
    expect(object.content_md5).toHaveLength(32);

    // The link the real upload flow writes, and the one findSubmissionMedia
    // reads — without it the agent's CV provider sees no media at all, which
    // is most of what #57 was about.
    expect(
      await harness.countRows(
        `SELECT count(*) FROM media_submission_links l
         JOIN media_objects m ON m.id = l.media_object_id
         WHERE l.submission_id = $1 AND m.submission_id = $1`,
        [submissionId],
      ),
    ).toBe(1);

    // And the submission now points at the new key rather than the legacy path.
    expect(await mediaUrlOf(submissionId)).toBe(object.object_key);
  });

  // Re-running an importer is normal — a batch dies, someone runs it again —
  // and duplicating objects would inflate every user's quota and give
  // duplicate detection two copies of the same picture to find.
  it('is idempotent: a second run migrates nothing', async () => {
    const submissionId = await importedSubmission('storage/proof/three.jpg');

    await importMedia(['--apply']);
    const afterFirst = await harness.countRows(
      'SELECT count(*) FROM media_objects WHERE submission_id = $1',
      [submissionId],
    );
    const keyAfterFirst = await mediaUrlOf(submissionId);

    const { stdout } = await importMedia(['--apply']);

    expect(
      await harness.countRows('SELECT count(*) FROM media_objects WHERE submission_id = $1', [submissionId]),
    ).toBe(afterFirst);
    expect(await mediaUrlOf(submissionId)).toBe(keyAfterFirst);
    expect(stdout).toMatch(/Nothing to migrate|migrated 0/);
  });

  // The bug that would have done real damage. A submission uploaded through
  // the real flow is linked ONLY by media_submission_links, so a candidate
  // query that checks `media_objects.submission_id` alone treats every live
  // submission as needing migration — and under --apply re-fetches and
  // re-uploads live media, rewriting media_url to new keys.
  it('never touches a submission uploaded through the real flow', async () => {
    const live = await harness.createSubmission(author, { caption: 'uploaded normally' });
    const beforeUrl = await mediaUrlOf(live.id);
    const objectsBefore = await harness.countRows(
      `SELECT count(*) FROM media_submission_links WHERE submission_id = $1`,
      [live.id],
    );

    await importMedia(['--apply']);

    expect(await mediaUrlOf(live.id)).toBe(beforeUrl);
    expect(
      await harness.countRows('SELECT count(*) FROM media_submission_links WHERE submission_id = $1', [live.id]),
    ).toBe(objectsBefore);
  });

  // A reference it cannot turn into something fetchable is reported, never
  // guessed at: a wrong URL would 404, or worse fetch the wrong object into
  // someone else's submission.
  it('reports an unresolvable reference rather than inventing a URL', async () => {
    const submissionId = await importedSubmission('storage/proof/four.jpg');

    const { stdout } = await importMedia([], { LEGACY_MEDIA_BASE_URL: '' });
    expect(stdout).toContain('unresolvable');
    expect(stdout).toContain('LEGACY_MEDIA_BASE_URL is not set');
    expect(
      await harness.countRows('SELECT count(*) FROM media_objects WHERE submission_id = $1', [submissionId]),
    ).toBe(0);
  });

  // A source that 404s must fail that submission and no other, leaving it
  // re-runnable rather than half-migrated.
  it('fails one submission without writing anything for it', async () => {
    const missing = await importedSubmission('nowhere/gone.jpg');

    const { stdout } = await importMedia(['--apply']);
    expect(stdout).toContain('FAILED');
    expect(
      await harness.countRows('SELECT count(*) FROM media_objects WHERE submission_id = $1', [missing]),
    ).toBe(0);
    expect(await mediaUrlOf(missing)).toBe('nowhere/gone.jpg');
  });
});
