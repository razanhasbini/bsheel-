import { createHash } from 'node:crypto';
import { readdir, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import process from 'node:process';
import pg from 'pg';

const { Pool } = pg;
const directory = resolve('migrations');
const checkOnly = process.argv.includes('--check');

// Read DATABASE_URL from backend/.env when it is not already exported.
//
// CLAUDE.md and the README both document `npm run db:migrate` as a bare
// command, and the API itself resolves .env through Nest's ConfigModule — so
// a developer who has a working .env would reasonably expect this to work.
// It did not, and the failure ("DATABASE_URL is required") gave no hint that
// a file sitting right there held the answer.
//
// An exported variable still wins, which is what CI and the migration-replay
// check rely on to point at a scratch database.
async function databaseUrlFromEnvFile() {
  try {
    const contents = await readFile(resolve('.env'), 'utf8');
    for (const line of contents.split('\n')) {
      const match = /^\s*DATABASE_URL\s*=\s*(.*)$/.exec(line);
      if (!match) continue;
      // Strip matched surrounding quotes and any trailing comment.
      return match[1].trim().replace(/^(['"])(.*)\1$/, '$2');
    }
  } catch {
    // No .env is normal in CI, where the variable is exported instead.
  }
  return undefined;
}

const databaseUrl = process.env.DATABASE_URL ?? (await databaseUrlFromEnvFile());

if (!databaseUrl) {
  throw new Error('DATABASE_URL is required (export it, or set it in backend/.env)');
}

const pool = new Pool({ connectionString: databaseUrl, max: 1 });
const client = await pool.connect();

try {
  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      name text PRIMARY KEY,
      checksum text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    )
  `);

  const files = (await readdir(directory))
    .filter((file) => /^\d{4}_.+\.sql$/.test(file))
    .sort();

  for (const file of files) {
    const sql = await readFile(resolve(directory, file), 'utf8');
    const checksum = createHash('sha256').update(sql).digest('hex');
    const applied = await client.query(
      'SELECT checksum FROM schema_migrations WHERE name = $1',
      [file],
    );

    if (applied.rowCount === 1) {
      if (applied.rows[0].checksum !== checksum) {
        throw new Error(`Applied migration was modified: ${file}`);
      }
      continue;
    }

    if (checkOnly) {
      throw new Error(`Pending migration: ${file}`);
    }

    console.log(`Applying ${file}`);
    await client.query('BEGIN');
    try {
      await client.query(sql);
      await client.query(
        'INSERT INTO schema_migrations (name, checksum) VALUES ($1, $2)',
        [file, checksum],
      );
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    }
  }

  console.log(checkOnly ? 'Migration check passed' : 'Database is up to date');
} finally {
  client.release();
  await pool.end();
}

