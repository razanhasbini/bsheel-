import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { ProofProvenanceService } from '../src/modules/submissions/application/proof-provenance.service.js';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';
import { cameraPhoto, reEncodedCopy, screenshot, unrelatedPhoto } from './support/proof-fixtures.js';

/// Stage 0 against real storage and a real database (#47).
///
/// The unit tests prove the pure forensics functions on fixture bytes. This
/// proves the part they cannot: that the service reads an actual object out
/// of S3/MinIO, decodes it, hashes it, persists the facts, and finds
/// duplicates through Postgres. Every link in that chain was written this
/// session and none of it is exercised by the HTTP surface, because the
/// pipeline runs in the worker off an outbox event.
///
/// Needs no API key and makes no model call — which is the point of the
/// stage. It is skipped when object storage is unconfigured, since without
/// it there is nothing to read.
const storageConfigured = Boolean(process.env.R2_ENDPOINT && process.env.R2_ACCESS_KEY_ID);

describe.runIf(storageConfigured)('proof provenance against real storage (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let provenance: ProofProvenanceService;
  let user: TestUser;

  /// Uploads straight to storage with the AWS SDK.
  ///
  /// Production never puts submission bytes server-side — the client PUTs to
  /// a presigned URL — so `ObjectStorageService` has no method for it, and
  /// adding one purely for a fixture would put test-only code in the
  /// production surface. The seed script uploads the same way.
  const s3 = new S3Client({
    endpoint: process.env.R2_ENDPOINT,
    region: process.env.R2_REGION ?? 'us-east-1',
    forcePathStyle: process.env.S3_FORCE_PATH_STYLE === 'true',
    credentials: {
      accessKeyId: process.env.R2_ACCESS_KEY_ID!,
      secretAccessKey: process.env.R2_SECRET_ACCESS_KEY!,
    },
  });

  /// Uploads real bytes and registers the `media_objects` row the upload
  /// flow would create, then returns a submission pointing at it.
  const submissionWith = async (
    bytes: Buffer,
    options: { owner?: TestUser; contentType?: string; assignedDaysAgo?: number } = {},
  ): Promise<{ id: string; objectKey: string }> => {
    const owner = options.owner ?? user;
    const objectKey = `submissions/${owner.id}/${Date.now()}-${Math.random().toString(36).slice(2)}.jpg`;
    await s3.send(new PutObjectCommand({
      Bucket: process.env.R2_BUCKET,
      Key: objectKey,
      Body: bytes,
      ContentType: options.contentType ?? 'image/jpeg',
    }));

    // The `media_objects` row must exist and be 'ready' BEFORE the
    // submission is posted: `create()` refuses media it cannot verify as an
    // owned upload (UNVERIFIED_MEDIA), and a rejected POST would leave the
    // quest assigned and break every later fixture with ACTIVE_QUEST_EXISTS.
    await harness.database.query(
      `INSERT INTO media_objects
         (user_id, client_request_id, object_key, kind, status, content_type,
          declared_size_bytes, stored_size_bytes, upload_expires_at)
       VALUES ($1, gen_random_uuid(), $2, 'submission', 'ready', $3, $4, $4, now())`,
      [owner.id, objectKey, options.contentType ?? 'image/jpeg', bytes.length],
    );

    const submission = await harness.createSubmission(owner, { mediaUrl: objectKey });

    // Duplicate search joins media_objects to submissions, so the link the
    // real flow records has to be present too.
    await harness.database.query(
      'UPDATE media_objects SET submission_id = $2 WHERE object_key = $1',
      [objectKey, submission.id],
    );
    return { id: submission.id, objectKey };
  };

  const facts = async (objectKey: string) => {
    const result = await harness.database.query<{
      perceptual_hash: string | null;
      content_md5: string | null;
      width: number | null;
      height: number | null;
      captured_at: Date | null;
      forensics_at: Date | null;
    }>(
      `SELECT perceptual_hash::text, content_md5, width, height, captured_at, forensics_at
       FROM media_objects WHERE object_key = $1`,
      [objectKey],
    );
    return result.rows[0];
  };

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    provenance = harness.app.get(ProofProvenanceService);
    user = await harness.createUser({ prefix: 'prov' });
  });

  afterAll(async () => {
    await harness?.close();
  });

  it('measures a real object and persists the facts', async () => {
    const captured = new Date(Date.now() - 30 * 60 * 1000);
    const submission = await submissionWith(
      await cameraPhoto({ capturedAt: captured, offsetTimeOriginal: '+00:00' }),
    );

    const outcome = await provenance.inspect(submission.id);
    expect(outcome).not.toBeNull();
    expect(outcome!.images).toHaveLength(1);
    // The base64 came back with the measurement rather than from a second
    // read of the object.
    expect(outcome!.images[0].base64.length).toBeGreaterThan(100);

    const stored = await facts(submission.objectKey);
    expect(stored.perceptual_hash).toMatch(/^[01]{64}$/);
    expect(stored.content_md5).toMatch(/^[0-9a-f]{32}$/);
    expect(stored.width).toBe(640);
    expect(stored.height).toBe(480);
    expect(stored.captured_at).toBeInstanceOf(Date);
    expect(stored.forensics_at).toBeInstanceOf(Date);
  });

  it('writes the report onto the verification row for the moderator to read', async () => {
    const submission = await submissionWith(await cameraPhoto({ capturedAt: new Date() }));
    await provenance.inspect(submission.id);

    const result = await harness.database.query<{ forensics: Record<string, unknown> }>(
      'SELECT forensics FROM submission_verifications WHERE submission_id = $1',
      [submission.id],
    );
    const report = result.rows[0].forensics;
    expect(report).toBeTruthy();
    expect(Array.isArray(report.findings)).toBe(true);
    expect(typeof report.captureWindow).toBe('string');
  });

  // The recycling case that matters most, and the one the unit tests can
  // only simulate: two different objects in storage, matched through
  // Postgres by `bit_count(a # b)`.
  it('finds a near-duplicate of a resized, recompressed copy', async () => {
    const original = await submissionWith(await cameraPhoto());
    await provenance.inspect(original.id);

    const copy = await submissionWith(await reEncodedCopy());
    const outcome = await provenance.inspect(copy.id);

    const codes = outcome!.report.findings.map((finding) => finding.code);
    expect(codes).toContain('near_duplicate');
  });

  // Bsheel's feed is public, so approved proof is a supply of stealable
  // images. Copying another player's is decisive; re-saving your own is not.
  it('treats a byte-identical copy of another user as decisive', async () => {
    const bytes = await cameraPhoto({ capturedAt: new Date() });
    const mine = await submissionWith(bytes);
    await provenance.inspect(mine.id);

    const thief = await harness.createUser({ prefix: 'thief' });
    const stolen = await submissionWith(bytes, { owner: thief });
    const outcome = await provenance.inspect(stolen.id);

    const exact = outcome!.report.findings.find((finding) => finding.code === 'exact_duplicate');
    expect(exact?.weight).toBe('decisive');
    expect(exact?.detail).toContain("another user's");
    expect(outcome!.report.blocksAutomatedApproval).toBe(true);
  });

  it('does not flag an unrelated photograph as a duplicate', async () => {
    const first = await submissionWith(await cameraPhoto());
    await provenance.inspect(first.id);

    const other = await submissionWith(await unrelatedPhoto());
    const outcome = await provenance.inspect(other.id);
    const codes = outcome!.report.findings.map((finding) => finding.code);
    expect(codes).not.toContain('exact_duplicate');
    expect(codes).not.toContain('near_duplicate');
  });

  // A screenshot informs the moderator without becoming an accusation: for
  // a `social` quest a call-log screenshot is an honest attempt.
  it('flags a screenshot without blocking approval on it alone', async () => {
    const submission = await submissionWith(await screenshot(), { contentType: 'image/png' });
    const outcome = await provenance.inspect(submission.id);
    const codes = outcome!.report.findings.map((finding) => finding.code);
    expect(codes).toContain('screen_dimensions');
    expect(outcome!.report.blocksAutomatedApproval).toBe(false);
  });

  // A registered upload whose bytes are gone — reclaimed, or a storage
  // failure. It must degrade to "unexamined" rather than throw, because this
  // runs in a queue worker where an exception fails the whole job and
  // retries every other side effect with it.
  it('reports an object missing from storage as unexamined rather than throwing', async () => {
    const objectKey = `submissions/${user.id}/does-not-exist-${Date.now()}.jpg`;
    // The row exists so the submission is accepted; the bytes never do.
    await harness.database.query(
      `INSERT INTO media_objects
         (user_id, client_request_id, object_key, kind, status, content_type,
          declared_size_bytes, stored_size_bytes, upload_expires_at)
       VALUES ($1, gen_random_uuid(), $2, 'submission', 'ready', 'image/jpeg', 1024, 1024, now())`,
      [user.id, objectKey],
    );
    const submission = await harness.createSubmission(user, { mediaUrl: objectKey });
    const outcome = await provenance.inspect(submission.id);
    expect(outcome).not.toBeNull();
    expect(outcome!.images).toHaveLength(0);
    expect(outcome!.unreadableMedia.length).toBeGreaterThan(0);
  });
});
