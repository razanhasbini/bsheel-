// Cuts poster frames for video submissions that do not have one (#map moments).
//
// Usage:
//   npm run build
//   npm run posters:backfill              # drain the whole backlog
//   npm run posters:backfill -- --limit 50
//
// WHY THIS EXISTS.
//
// The worker sweeps for posters on the proof-verification schedule, which is
// every fifteen minutes in batches of ten. That is the right cadence for
// steady state — posters are a nicety, and ffmpeg competes with verification
// for the same core — and the wrong one for a deployment that has just
// gained the feature and owns a year of video proof, which would take days
// to surface and look broken the whole time.
//
// Same service, same partial index, same failure behaviour. This only
// removes the wait.
import process from 'node:process';

const args = process.argv.slice(2);
const limitArg = args.find((value) => value.startsWith('--limit'));
const limit = Number.parseInt(
  limitArg?.split('=')[1] ?? args[args.indexOf('--limit') + 1] ?? '0',
  10,
);
const cap = Number.isFinite(limit) && limit > 0 ? limit : Infinity;

const { NestFactory } = await import('@nestjs/core');
const { ProofBackfillModule } = await import('../dist/modules/submissions/proof-backfill.module.js');
const { PosterFrameService } = await import('../dist/modules/submissions/application/poster-frame.service.js');

const context = await NestFactory.createApplicationContext(ProofBackfillModule, {
  logger: ['error', 'warn'],
});
try {
  const service = context.get(PosterFrameService);
  let written = 0;
  let considered = 0;
  // Sweeps until one pass writes nothing. A pass that considers rows but
  // writes none has hit videos it cannot decode — retrying those forever
  // would spin, so stopping on "no progress" is the termination condition
  // rather than "nothing left to consider".
  for (;;) {
    const pass = await service.sweep();
    considered += pass.considered;
    written += pass.written;
    process.stdout.write(`  +${pass.written} (${written} total)\n`);
    if (pass.written === 0 || written >= cap) break;
  }
  console.log(`\n  posters written  ${written}`);
  console.log(`  videos examined  ${considered}`);
  if (written < considered) {
    console.log('\n  Some videos yielded no frame. That is an ordinary outcome —');
    console.log('  an unreadable container, or no ffmpeg here. They keep the');
    console.log('  category tint on the map and will be retried by the sweep.\n');
  }
} finally {
  await context.close();
}
