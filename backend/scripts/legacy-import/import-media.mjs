#!/usr/bin/env node
// Copies imported submissions' media into the configured bucket and creates
// the `media_objects` rows the real upload flow would have created (#57).
//
// Usage:
//   LEGACY_MEDIA_BASE_URL=https://… node scripts/legacy-import/import-media.mjs
//   LEGACY_MEDIA_BASE_URL=https://… node scripts/legacy-import/import-media.mjs --apply
//   … --apply --limit 50
//
// Dry run by default: it resolves every reference, reports what it would
// fetch and what it cannot, and writes nothing.
//
// WHY THIS IS SEPARATE FROM import-legacy.mjs
//
// It needs no legacy *database* connection. Everything it works from —
// `submissions.media_url` — is already in the Bsheel database once the row
// import has run. So it is independently runnable, independently
// re-runnable, and testable end to end against MinIO, none of which is true
// of a stage wedged inside a script that holds a read-only transaction open
// against a production Supabase instance.
//
// WHAT WAS BROKEN
//
// `import-legacy.mjs` carries `media_url` across verbatim and creates no
// `media_objects` rows, so an imported submission points at a path in legacy
// storage that does not resolve against the new bucket and has no record in
// our media tables. Three things then silently do nothing, because all of
// them key off `media_objects`:
//
//   * signed-URL serving — `/media/sign` has no object to sign, so imported
//     proof cannot be displayed at all
//   * AI proof verification (#47) — forensics reads bytes to compute EXIF,
//     the perceptual hash and the content hash. No bytes, no provenance, and
//     `npm run proof:backfill` skips the row
//   * media quota and orphan reclaim — both count rows in `media_objects`
//
// Its own comment cited "STORAGE notes in ACCESS.md", which contains zero
// mentions of storage. That note is now this file.
//
// WHAT IT ASSUMES, AND WHY IT ASKS
//
// Legacy `media_url` may be a full URL or a bare storage path, and may be a
// single value or a JSON array — the app's own parseMediaKeys accepts both,
// so this does too. A bare path is joined onto LEGACY_MEDIA_BASE_URL. If a
// reference cannot be turned into something fetchable it is reported and
// skipped, never guessed at: a wrong URL would either 404 or, worse, fetch
// the wrong object into someone's submission.
import { createHash, randomUUID } from 'node:crypto';
import process from 'node:process';
import { readFile } from 'node:fs/promises';
import { resolve as resolvePath } from 'node:path';
import pg from 'pg';
import { HeadObjectCommand, PutObjectCommand, S3Client } from '@aws-sdk/client-s3';

const args = process.argv.slice(2);
const APPLY = args.includes('--apply');
const limitIndex = args.indexOf('--limit');
const LIMIT = Number.parseInt(
  args.find((value) => value.startsWith('--limit='))?.split('=')[1]
    ?? (limitIndex >= 0 ? args[limitIndex + 1] : '')
    ?? '',
  10,
);
const limit = Number.isFinite(LIMIT) && LIMIT > 0 ? LIMIT : 100;

function fail(message) {
  console.error(`\n  ${message}\n`);
  process.exit(1);
}

/// Reads one key out of backend/.env, like every other script here.
async function fromEnvFile(key) {
  try {
    const contents = await readFile(resolvePath('.env'), 'utf8');
    for (const line of contents.split('\n')) {
      const match = new RegExp(`^\\s*${key}\\s*=\\s*(.*)$`).exec(line);
      if (match) {
        const value = match[1].trim().replace(/^(['"])(.*)\1$/, '$2');
        if (value) return value;
      }
    }
  } catch {
    // No .env is normal in CI, where these are exported instead.
  }
  return undefined;
}

const env = async (key) => process.env[key] ?? (await fromEnvFile(key));

const DATABASE_URL = await env('DATABASE_URL');
const MEDIA_BASE = await env('LEGACY_MEDIA_BASE_URL');
if (!DATABASE_URL) fail('DATABASE_URL is required (export it, or set it in backend/.env)');

const R2_ENDPOINT = await env('S3_INTERNAL_ENDPOINT') ?? (await env('R2_ENDPOINT'));
const R2_BUCKET = await env('R2_BUCKET');
const R2_KEY = await env('R2_ACCESS_KEY_ID');
const R2_SECRET = await env('R2_SECRET_ACCESS_KEY');
const R2_REGION = (await env('R2_REGION')) ?? 'auto';
const FORCE_PATH_STYLE = ((await env('S3_FORCE_PATH_STYLE')) ?? 'true') !== 'false';

/// Extensions the media DTO accepts, so an imported object lands on a key the
/// real upload flow could have produced.
const EXTENSIONS = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/gif': 'gif',
  'image/webp': 'webp',
  'video/mp4': 'mp4',
  'video/quicktime': 'mov',
  'video/webm': 'webm',
};

/// Same shape the app parses: one to ten keys, as a bare string or a JSON
/// array. Anything else is not a reference this script will invent a meaning
/// for.
function parseReferences(raw) {
  if (typeof raw !== 'string' || raw.trim().length === 0) return [];
  try {
    const parsed = raw.trim().startsWith('[') ? JSON.parse(raw) : [raw];
    if (!Array.isArray(parsed)) return [];
    return parsed.filter((value) => typeof value === 'string' && value.trim().length > 0);
  } catch {
    return [];
  }
}

/// A legacy reference turned into something fetchable, or null.
function sourceUrl(reference) {
  if (/^https?:\/\//i.test(reference)) return reference;
  if (!MEDIA_BASE) return null;
  return `${MEDIA_BASE.replace(/\/$/, '')}/${reference.replace(/^\//, '')}`;
}

/// Whether a submission already has its media recorded.
///
/// There are TWO links, and missing either one is how this script nearly did
/// real damage: `media_objects.submission_id` is what the seed and this
/// importer set, while `media_submission_links` is what the real upload flow
/// writes — and it is the one `findSubmissionMedia` reads, so it is what the
/// CV provider actually sees. Checking only the column flagged every
/// correctly-uploaded submission as needing migration, which under --apply
/// would have re-fetched and re-uploaded live media and rewritten
/// `media_url` to new keys.
async function alreadyMigrated(target, submissionId) {
  const { rows } = await target.query(
    `SELECT 1 FROM media_objects m
     WHERE m.kind = 'submission' AND m.status = 'ready' AND m.deleted_at IS NULL
       AND (m.submission_id = $1
            OR EXISTS (SELECT 1 FROM media_submission_links l
                       WHERE l.media_object_id = m.id AND l.submission_id = $1))
     LIMIT 1`,
    [submissionId],
  );
  return rows.length > 0;
}

const pool = new pg.Pool({ connectionString: DATABASE_URL, connectionTimeoutMillis: 5000 });
const target = await pool.connect();

try {
  const { rows: candidates } = await target.query(
    // Both links, for the reason in alreadyMigrated: a submission uploaded
    // through the real flow is linked only by media_submission_links, and
    // treating those as unmigrated would re-import live media.
    `SELECT s.id, s.user_id, s.media_url, s.media_type::text AS media_type, s.submitted_at
     FROM submissions s
     WHERE s.deleted_at IS NULL
       AND NOT EXISTS (
         SELECT 1 FROM media_objects m
         WHERE m.kind = 'submission' AND m.status = 'ready' AND m.deleted_at IS NULL
           AND (m.submission_id = s.id
                OR EXISTS (SELECT 1 FROM media_submission_links l
                           WHERE l.media_object_id = m.id AND l.submission_id = s.id)))
     ORDER BY s.submitted_at DESC
     LIMIT $1`,
    [limit],
  );

  if (candidates.length === 0) {
    console.log('\nEvery submission already has a media_objects row. Nothing to migrate.\n');
    process.exit(0);
  }

  const resolvable = [];
  const unresolvable = [];
  for (const row of candidates) {
    const references = parseReferences(row.media_url);
    if (references.length === 0) {
      unresolvable.push({ id: row.id, why: 'media_url is empty or not a string/JSON array' });
      continue;
    }
    const urls = references.map((reference) => ({ reference, url: sourceUrl(reference) }));
    const missing = urls.filter((entry) => entry.url === null);
    if (missing.length > 0) {
      unresolvable.push({
        id: row.id,
        why: `${missing.length} bare path(s) and no LEGACY_MEDIA_BASE_URL to join them onto`,
      });
      continue;
    }
    resolvable.push({ ...row, urls });
  }

  console.log(`\n${candidates.length} submission(s) without a media_objects row`);
  console.log(`  resolvable    ${resolvable.length}`);
  console.log(`  unresolvable  ${unresolvable.length}`);
  for (const row of unresolvable.slice(0, 10)) console.log(`    ${row.id} — ${row.why}`);
  if (unresolvable.length > 10) console.log(`    … and ${unresolvable.length - 10} more`);

  if (!MEDIA_BASE) {
    console.log('\n  LEGACY_MEDIA_BASE_URL is not set. Only references that are already full');
    console.log('  URLs can be fetched; bare storage paths need a base to join onto.');
  }

  if (!APPLY) {
    console.log('\nDry run. Re-run with --apply to fetch, upload and record.\n');
    process.exit(0);
  }
  if (!R2_ENDPOINT || !R2_BUCKET || !R2_KEY || !R2_SECRET) {
    fail('Object storage is not configured (R2_ENDPOINT/R2_BUCKET/R2_ACCESS_KEY_ID/R2_SECRET_ACCESS_KEY)');
  }

  const s3 = new S3Client({
    endpoint: R2_ENDPOINT,
    region: R2_REGION,
    credentials: { accessKeyId: R2_KEY, secretAccessKey: R2_SECRET },
    forcePathStyle: FORCE_PATH_STYLE,
    maxAttempts: 3,
  });

  let migrated = 0;
  let failed = 0;
  for (const row of resolvable) {
    if (await alreadyMigrated(target, row.id)) continue;
    try {
      const newKeys = [];
      for (const { url } of row.urls) {
        const response = await fetch(url, { signal: AbortSignal.timeout(60_000) });
        if (!response.ok) throw new Error(`GET ${url} → ${response.status}`);
        const bytes = Buffer.from(await response.arrayBuffer());
        // The legacy store's own content type, falling back to the
        // submission's declared media type. Never guessed from the
        // extension: a mislabelled object would be signed with the wrong
        // type and fail to render.
        const contentType = (response.headers.get('content-type') ?? '').split(';')[0].trim()
          || (row.media_type === 'video' ? 'video/mp4' : 'image/jpeg');
        const extension = EXTENSIONS[contentType];
        if (!extension) throw new Error(`unsupported content type ${contentType}`);

        const objectKey = `submissions/${row.user_id}/${randomUUID()}.${extension}`;
        await s3.send(new PutObjectCommand({
          Bucket: R2_BUCKET, Key: objectKey, Body: bytes, ContentType: contentType,
          Metadata: { 'uploaded-by': row.user_id, 'imported-from-legacy': 'true' },
        }));
        // Read back rather than trusting the write: stored_size_bytes and
        // etag are what reclaim and duplicate detection compare against.
        const head = await s3.send(new HeadObjectCommand({ Bucket: R2_BUCKET, Key: objectKey }));

        const inserted = await target.query(
          `INSERT INTO media_objects
             (user_id, client_request_id, object_key, kind, status, content_type,
              declared_size_bytes, stored_size_bytes, etag, content_md5,
              submission_id, upload_expires_at, completed_at)
           VALUES ($1, gen_random_uuid(), $2, 'submission', 'ready', $3,
                   $4, $5, $6, $7, $8, now(), now())
           RETURNING id`,
          [
            row.user_id, objectKey, contentType, bytes.length,
            Number(head.ContentLength ?? bytes.length),
            head.ETag ?? null,
            // content_md5, not the etag: a multipart etag is a hash of part
            // hashes and is not comparable across objects, which is the
            // whole reason this column exists.
            createHash('md5').update(bytes).digest('hex'),
            row.id,
          ],
        );
        // The link the real upload flow writes, and the one
        // findSubmissionMedia reads — without it the agent's CV provider
        // sees no media for an imported submission, which is most of what
        // #57 was about.
        await target.query(
          `INSERT INTO media_submission_links (media_object_id, submission_id)
           VALUES ($1, $2) ON CONFLICT DO NOTHING`,
          [inserted.rows[0].id, row.id],
        );
        newKeys.push(objectKey);
      }

      // Rewritten to the same shape the app writes: a bare key for one
      // object, a JSON array for several.
      await target.query('UPDATE submissions SET media_url = $2 WHERE id = $1', [
        row.id,
        newKeys.length === 1 ? newKeys[0] : JSON.stringify(newKeys),
      ]);
      migrated += 1;
      console.log(`  migrated ${row.id} → ${newKeys.length} object(s)`);
    } catch (error) {
      failed += 1;
      console.log(`  FAILED   ${row.id} — ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  console.log(`\n  migrated ${migrated}`);
  console.log(`  failed   ${failed}   (nothing was written for these; safe to re-run)`);
  console.log('\nNext: npm run proof:backfill  — those rows can now be scored.\n');
} finally {
  target.release();
  await pool.end();
}
