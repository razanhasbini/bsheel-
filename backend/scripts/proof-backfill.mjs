// Scores the agent against decisions people already made (#47).
//
// Usage:
//   npm run build                                  # this runs against dist/
//   npm run proof:backfill                         # dry run: what it would score
//   npm run proof:backfill -- --apply --limit 25   # score them
//   npm run proof:eval                             # then read the numbers
//
// WHY THIS EXISTS.
//
// The authority model says the agent earns the right to act from a measured
// precision number, and `proof:eval` computes it from stored verdicts paired
// with the human decision that followed. But `verify()` refuses to analyse
// anything a human already decided — correct operationally, since a vision
// call on a settled submission buys nothing — so that pairing can only
// accumulate going forward. A deployment with a year of moderation history
// still has to run in shadow mode for weeks before it can answer "is this
// good enough yet", and the history it already owns is invisible.
//
// This reads that history. Same forensics, same cascade, same policy; the
// verdict recorded is the one the agent *would* have reached on a submission
// whose outcome a person settled before the verdict existed — which makes it
// cleaner eval data than shadow mode, not dirtier: it cannot have influenced
// the decision it is scored against even in principle.
//
// WHAT IT COSTS, AND WHAT IT WILL NOT DO.
//
// Real vision calls, on the tiered models, one submission at a time. Hence
// the limit and the dry run being the default. It never acts, never claims,
// and never alerts — see backfillForEval for why each of those matters.
import process from 'node:process';
import pg from 'pg';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const limitArg = args.find((value) => value.startsWith('--limit'));
const limit = Number.parseInt(limitArg?.split('=')[1] ?? args[args.indexOf('--limit') + 1] ?? '10', 10);

if (!Number.isFinite(limit) || limit < 1) {
  console.error('--limit must be a positive integer');
  process.exit(1);
}

async function databaseUrlFromEnvFile() {
  try {
    const contents = await readFile(resolve('.env'), 'utf8');
    for (const line of contents.split('\n')) {
      const match = /^\s*DATABASE_URL\s*=\s*(.*)$/.exec(line);
      if (match) return match[1].trim().replace(/^(['"])(.*)\1$/, '$2');
    }
  } catch {
    // No .env is normal in CI, where the variable is exported instead.
  }
  return undefined;
}

const databaseUrl = process.env.DATABASE_URL ?? (await databaseUrlFromEnvFile());
if (!databaseUrl) {
  console.error('DATABASE_URL is required (export it, or set it in backend/.env)');
  process.exit(1);
}
process.env.DATABASE_URL = databaseUrl;

// The dry run answers the only question worth asking before spending money:
// is there anything here to score, and does it look like ground truth?
const pool = new pg.Pool({ connectionString: databaseUrl, connectionTimeoutMillis: 5000 });
try {
  const { rows: summary } = await pool.query(`
    SELECT
      count(*) FILTER (WHERE s.status IN ('approved','rejected')
                         AND s.reviewed_by IS NOT NULL
                         AND s.deleted_at IS NULL)::int          AS human_decided,
      count(*) FILTER (WHERE s.status IN ('approved','rejected')
                         AND s.reviewed_by IS NULL
                         AND s.deleted_at IS NULL)::int          AS machine_decided,
      count(*) FILTER (WHERE v.state = 'complete')::int          AS already_scored
    FROM submissions s
    LEFT JOIN submission_verifications v ON v.submission_id = s.id
  `);
  const { rows: pending } = await pool.query(`
    SELECT q.category::text AS category, c.verifiability::text AS verifiability, count(*)::int AS n
    FROM submissions s
    LEFT JOIN submission_verifications v ON v.submission_id = s.id AND v.state = 'complete'
    JOIN user_quests uq ON uq.id = s.user_quest_id
    JOIN quests q ON q.id = uq.quest_id
    JOIN quest_verification_contract c ON c.quest_id = q.id
    WHERE s.status IN ('approved','rejected') AND s.reviewed_by IS NOT NULL
      AND s.reviewed_at IS NOT NULL AND s.deleted_at IS NULL
      AND s.visibility <> 'deleted' AND v.submission_id IS NULL
    GROUP BY 1, 2 ORDER BY n DESC
  `);

  const stats = summary[0];
  console.log('\nGround truth available');
  console.log(`  decided by a person        ${stats.human_decided}   ← scoreable`);
  console.log(`  decided by automation      ${stats.machine_decided}   ← never scoreable, the agent would mark its own work`);
  console.log(`  already carry a verdict    ${stats.already_scored}`);

  const total = pending.reduce((sum, row) => sum + row.n, 0);
  if (total === 0) {
    console.log('\nNothing to backfill. Either every human decision already has a verdict,');
    console.log('or there are no human decisions yet.\n');
    process.exit(0);
  }

  console.log(`\n${total} submission(s) could be scored, by contract:`);
  for (const row of pending) {
    const vision = row.verifiability === 'content' ? 'vision call' : 'forensics only, no model';
    console.log(`  ${String(row.n).padStart(4)}  ${row.category.padEnd(12)} ${row.verifiability.padEnd(17)} ${vision}`);
  }
  const visionCalls = pending
    .filter((row) => row.verifiability === 'content')
    .reduce((sum, row) => sum + row.n, 0);
  console.log(`\n  of which ${visionCalls} would make at least one vision call.`);
  console.log(`  provenance_only and none quests make none — that is the cost model working.`);

  if (!apply) {
    console.log(`\nDry run. Re-run with --apply --limit N to score the newest N.`);
    console.log('Then `npm run proof:eval` for the precision numbers.\n');
    process.exit(0);
  }
} finally {
  await pool.end();
}

// Only now boot Nest, so a dry run costs nothing and needs no working
// analyzer, storage or OpenAI key.
const { NestFactory } = await import('@nestjs/core');
const { ProofBackfillModule } = await import('../dist/modules/submissions/proof-backfill.module.js');
const { ProofVerificationService } = await import('../dist/modules/submissions/application/proof-verification.service.js');

const context = await NestFactory.createApplicationContext(ProofBackfillModule, {
  logger: ['error', 'warn', 'log'],
});
try {
  const service = context.get(ProofVerificationService);
  console.log(`\nScoring up to ${limit} submission(s). This spends vision calls.\n`);
  const outcome = await service.backfillForEval(limit);
  console.log(`\n  scored   ${outcome.scored}`);
  console.log(`  skipped  ${outcome.skipped}   (media gone, or no resolvable contract)`);
  console.log(`  failed   ${outcome.failed}   (retryable — nothing was written for these)`);
  console.log('\nNow run: npm run proof:eval\n');
} finally {
  await context.close();
}
