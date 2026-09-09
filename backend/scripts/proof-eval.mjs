// Scores AI proof verification against real human decisions (#47).
//
// Read-only on the application: it reads verdicts the agent already recorded
// and the moderator decisions that followed, and writes nothing. Run it to
// decide whether the agent has earned authority, and at what threshold.
//
//   node scripts/proof-eval.mjs                 # summary
//   node scripts/proof-eval.mjs --by-category   # per-category breakdown
//   node scripts/proof-eval.mjs --sweep         # threshold curves
//   node scripts/proof-eval.mjs --json          # machine-readable
//
// WHY ONLY `acted = false` ROWS COUNT.
//
// A verdict that was acted on *caused* the outcome it would be scored
// against, so including live rows would score the agent against itself and
// report near-perfect agreement no matter how wrong it is. Only shadow rows —
// where the agent decided privately and a human decided independently — are
// evidence. The query enforces that; do not relax it to grow the sample.
//
// WHAT GROUND TRUTH IS HERE.
//
// The human decision on the same submission: `approved` or `rejected`. Two
// wrinkles that matter and are handled explicitly:
//
//   * An overturned appeal is a labelled human *reversal*. The final state is
//     the truth, and those rows are the most interesting in the set because
//     they are cases a human initially got wrong too.
//   * A submission still `pending` has no ground truth yet. Excluded rather
//     than assumed.
import process from 'node:process';
import pg from 'pg';

const args = new Set(process.argv.slice(2));
const asJson = args.has('--json');
const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL is not set');
  process.exit(1);
}

const pool = new pg.Pool({ connectionString: DATABASE_URL, connectionTimeoutMillis: 5000 });

/// One row per scoreable decision: what the agent concluded, what the human
/// concluded, and enough context to slice it.
const sampleQuery = `
  SELECT v.submission_id,
         v.verdict::text        AS agent_verdict,
         v.confidence,
         v.stage,
         v.model,
         v.forensics,
         s.status::text         AS human_verdict,
         s.appealed,
         q.category,
         c.verifiability::text  AS verifiability,
         (v.forensics->>'blocksAutomatedApproval')::boolean AS forensics_blocked
  FROM submission_verifications v
  JOIN submissions s ON s.id = v.submission_id
  JOIN user_quests uq ON uq.id = s.user_quest_id
  JOIN quests q ON q.id = uq.quest_id
  JOIN quest_verification_contract c ON c.quest_id = uq.quest_id
  WHERE v.state = 'complete'
    -- Shadow rows only. See the note above: a live verdict caused the outcome.
    AND v.acted = false
    -- Decided by a human, so there is something to score against.
    AND s.status IN ('approved', 'rejected')
    AND s.reviewed_at IS NOT NULL
`;

/// Confusion matrix for one decision side.
///
/// Reported as counts rather than a single accuracy number on purpose:
/// accuracy hides the asymmetry that matters. An agent that escalates
/// everything is 100% precise and useless, and one that approves everything
/// looks good on a queue where most proof is honest.
function score(rows, side) {
  const agentSays = side === 'approve' ? 'pass' : 'fail';
  const humanSays = side === 'approve' ? 'approved' : 'rejected';

  const acted = rows.filter((row) => row.agent_verdict === agentSays);
  const correct = acted.filter((row) => row.human_verdict === humanSays);
  const wrong = acted.filter((row) => row.human_verdict !== humanSays);
  const humanTotal = rows.filter((row) => row.human_verdict === humanSays);
  const missed = humanTotal.filter((row) => row.agent_verdict !== agentSays);

  return {
    side,
    decided: acted.length,
    correct: correct.length,
    wrong: wrong.length,
    // Of the decisions the agent would have made, how many match the human.
    // This is the number that gates authority: it is the rate at which
    // enabling this side would produce a wrong outcome.
    precision: acted.length > 0 ? correct.length / acted.length : null,
    // Of the decisions a human made this way, how many the agent would have
    // handled. This is the workload actually removed from the queue.
    recall: humanTotal.length > 0 ? correct.length / humanTotal.length : null,
    escalated: missed.length,
    // The rows worth reading by hand before turning anything on.
    examples: wrong.slice(0, 5).map((row) => ({
      submissionId: row.submission_id,
      confidence: row.confidence === null ? null : Number(row.confidence),
      stage: row.stage,
      model: row.model,
      humanSaid: row.human_verdict,
    })),
  };
}

/// How precision and coverage trade off as the confidence bar moves.
///
/// This is what a threshold should be chosen from. Picking 0.85 or 0.95 by
/// taste — which is what the defaults in .env.example are — is a placeholder
/// until this table exists for real traffic.
function sweep(rows, side) {
  const agentSays = side === 'approve' ? 'pass' : 'fail';
  const humanSays = side === 'approve' ? 'approved' : 'rejected';
  const steps = [0.5, 0.6, 0.7, 0.75, 0.8, 0.85, 0.9, 0.95, 0.99];

  return steps.map((threshold) => {
    const acted = rows.filter(
      (row) => row.agent_verdict === agentSays
        && row.confidence !== null
        && Number(row.confidence) >= threshold,
    );
    const correct = acted.filter((row) => row.human_verdict === humanSays);
    return {
      threshold,
      decided: acted.length,
      precision: acted.length > 0 ? correct.length / acted.length : null,
      // Share of the whole scoreable set this side would decide at this bar.
      coverage: rows.length > 0 ? acted.length / rows.length : 0,
    };
  });
}

/// How often the free stage was right on its own.
///
/// Worth reporting separately because it needs no model and no threshold: if
/// forensics alone accounts for most agreed rejections, the expensive rungs
/// are carrying less than they appear to.
function forensicsOnly(rows) {
  const blocked = rows.filter((row) => row.forensics_blocked === true);
  const agreed = blocked.filter((row) => row.human_verdict === 'rejected');
  return {
    flagged: blocked.length,
    humanAlsoRejected: agreed.length,
    precision: blocked.length > 0 ? agreed.length / blocked.length : null,
  };
}

function percent(value) {
  return value === null ? 'n/a' : `${(value * 100).toFixed(1)}%`;
}

function reportSide(label, result) {
  console.log(`\n  ${label}`);
  console.log(`    would decide      ${result.decided}`);
  console.log(`    agreed with human ${result.correct}`);
  console.log(`    disagreed         ${result.wrong}`);
  console.log(`    precision         ${percent(result.precision)}`);
  console.log(`    recall            ${percent(result.recall)}`);
  if (result.examples.length > 0) {
    console.log('    disagreements to read by hand:');
    for (const example of result.examples) {
      console.log(
        `      ${example.submissionId}  human=${example.humanSaid}  `
        + `stage=${example.stage ?? '-'}  confidence=${example.confidence ?? 'n/a'}`,
      );
    }
  }
}

try {
  const { rows } = await pool.query(sampleQuery);

  const report = {
    sample: rows.length,
    approve: score(rows, 'approve'),
    reject: score(rows, 'reject'),
    forensics: forensicsOnly(rows),
    escalationRate: rows.length > 0
      ? rows.filter((row) => row.agent_verdict === 'unclear').length / rows.length
      : 0,
  };

  if (args.has('--by-category')) {
    const categories = [...new Set(rows.map((row) => row.category))].sort();
    report.byCategory = categories.map((category) => {
      const subset = rows.filter((row) => row.category === category);
      return {
        category,
        verifiability: subset[0]?.verifiability,
        sample: subset.length,
        approve: score(subset, 'approve'),
        reject: score(subset, 'reject'),
      };
    });
  }

  if (args.has('--sweep')) {
    report.sweep = { approve: sweep(rows, 'approve'), reject: sweep(rows, 'reject') };
  }

  if (asJson) {
    console.log(JSON.stringify(report, null, 2));
  } else if (rows.length === 0) {
    console.log('\nNo scoreable decisions yet.\n');
    console.log('This needs shadow-mode verdicts on submissions a human has since decided:');
    console.log('  - AI_VERIFICATION_ENABLED=true');
    console.log('  - AI_VERIFICATION_SHADOW_MODE=true   (so `acted` stays false)');
    console.log('  - and moderators reviewing as normal.');
    console.log('\nUntil then the thresholds in .env.example are placeholders, not measurements,');
    console.log('and may_auto_approve / may_auto_reject should stay off.\n');
  } else {
    console.log(`\nProof verification eval — ${rows.length} scoreable shadow decisions`);
    console.log(`  escalation rate: ${percent(report.escalationRate)} (left to a human)`);
    reportSide('AUTO-APPROVE', report.approve);
    reportSide('AUTO-REJECT', report.reject);
    console.log('\n  DETERMINISTIC FORENSICS ALONE (no model, no threshold)');
    console.log(`    flagged             ${report.forensics.flagged}`);
    console.log(`    human also rejected ${report.forensics.humanAlsoRejected}`);
    console.log(`    precision           ${percent(report.forensics.precision)}`);

    if (report.byCategory) {
      console.log('\n  BY CATEGORY');
      for (const entry of report.byCategory) {
        console.log(
          `    ${entry.category.padEnd(12)} ${String(entry.sample).padStart(4)} rows  `
          + `${entry.verifiability.padEnd(16)} `
          + `approve ${percent(entry.approve.precision).padStart(7)}  `
          + `reject ${percent(entry.reject.precision).padStart(7)}`,
        );
      }
    }

    if (report.sweep) {
      for (const side of ['approve', 'reject']) {
        console.log(`\n  THRESHOLD SWEEP — ${side.toUpperCase()}`);
        console.log('    bar    decided  precision  coverage');
        for (const step of report.sweep[side]) {
          console.log(
            `    ${step.threshold.toFixed(2)}   ${String(step.decided).padStart(7)}  `
            + `${percent(step.precision).padStart(9)}  ${percent(step.coverage).padStart(8)}`,
          );
        }
      }
    }

    console.log('\n  Choose each threshold from its own curve, then set');
    console.log('  may_auto_approve / may_auto_reject per category in');
    console.log('  quest_verification_defaults. Neither should be enabled on a');
    console.log('  precision number you have not looked at.\n');
  }
} finally {
  await pool.end();
}
