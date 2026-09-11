// Reads the quest catalogue and flags quests whose verification contract
// looks wrong, before the agent is allowed to act on them (#47).
//
// Usage:
//   npm run proof:contract                 # audit, read-only
//   npm run proof:contract -- --sql        # also print the UPDATEs to fix it
//
// WHY THIS EXISTS.
//
// Migration 0034 sets a contract per *category*, and says in its own comment
// that a category default cannot be right for every quest in it: "Watch the
// sunrise" and "Spend an hour with no phone" are both adventure, and only one
// of them is checkable from a photograph. Per-quest overrides exist for the
// other kind — and nothing makes anyone author them.
//
// The consequence, once `may_auto_reject` is granted to a category: the agent
// is asked whether a photograph proves something no photograph can, answers
// anyway with a confidence score, and rejects an honest player. That is the
// failure this feature was designed around, and it arrives through the
// catalogue rather than through the code.
//
// On the seeded catalogue this found five of nine content quests mis-marked.
// A real catalogue has never been checked at all.
//
// READ-ONLY. It prints SQL; it never runs it. Deciding what a photograph can
// show is a judgement about your own quests, not something to infer from
// keywords — which is exactly why the flags below are suggestions and the
// last column is for a person.
import process from 'node:process';
import pg from 'pg';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';

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

/// Two different problems, which need two different fixes.
///
/// The distinction is the whole value of this script, and conflating them is
/// the mistake it was written to stop making. "Draw the view from your
/// window — ten minutes minimum" is a *photographable task with an
/// unphotographable clause*: the drawing is right there in the frame, and no
/// photograph shows that ten minutes passed. Overriding it to
/// provenance_only would throw away the part that works. What it needs is a
/// rubric that tells the model not to judge the clause — which is exactly
/// what the seeded fitness rubric already does for counts and durations.
///
/// "Spend an hour with no phone" is the other kind: nothing in any
/// photograph bears on the task, and no rubric can rescue that.

/// The task itself cannot be photographed. Needs a verifiability override.
const TASK_NOT_PHOTOGRAPHABLE = [
  { code: 'phone absence',  why: 'the phone took the photograph',                 suggest: 'none',            test: /\b(no|without|off|away from)\s+(your\s+)?phone\b/i },
  { code: 'conversation',   why: 'speech leaves no photographic trace',           suggest: 'none',            test: /\b(call|called|calling|talk|talked|speak|spoke|compliment|conversation|apolog)\b/i },
  { code: 'reading',        why: 'a photo of a book is not evidence of reading',  suggest: 'provenance_only', test: /\b(read|reading|listen|listened|learn|learned|study|studied|memoris|memoriz)\b/i },
  { code: 'teaching',       why: 'what was explained is not in the frame',        suggest: 'provenance_only', test: /\b(teach|taught|explain|explained)\b/i },
  { code: 'travel extent',  why: 'a place is showable; getting there is not',     suggest: 'provenance_only', test: /\b(to the end|whole route|all the way|furthest|farthest)\b/i },
];

/// The task is photographable but carries a clause that is not. Needs the
/// rubric to say so, not an override.
const CLAUSE_NOT_PHOTOGRAPHABLE = [
  { code: 'a count',    why: 'no photograph shows how many',            test: /\b(\d+|one|two|three|five|ten|twenty|fifty|hundred)\b\s*\w*\s*\b(pages?|reps?|push-?ups?|sit-?ups?|steps?|laps?|times|people|languages?)\b/i },
  { code: 'a duration', why: 'no photograph shows that time passed',    test: /\b(\d+\s*(minute|min|hour|hr|day)s?|an hour|half an hour|all day|ten minutes)\b/i },
];

/// Whether a rubric already tells the model to ignore counts and durations.
/// The seeded fitness rubric does; a hand-written one usually does not.
const RUBRIC_COVERS_CLAUSES = /\b(count|counts|duration|durations|how many|cannot be verified|never reject|do not reject)\b/i;

const pool = new pg.Pool({ connectionString: databaseUrl, connectionTimeoutMillis: 5000 });
try {
  const { rows } = await pool.query(`
    SELECT q.id, q.title, q.description, q.category::text AS category,
           c.verifiability::text AS verifiability, c.evidence_rubric,
           c.may_auto_approve, c.may_auto_reject,
           q.verifiability IS NOT NULL AS has_override
    FROM quests q
    JOIN quest_verification_contract c ON c.quest_id = q.id
    WHERE q.is_active
    ORDER BY c.may_auto_reject DESC, q.category, q.title
  `);

  if (rows.length === 0) {
    console.log('No active quests.');
    process.exit(0);
  }

  const wrongContract = [];
  const rubricGap = [];
  console.log(`\n${rows.length} active quests\n`);
  console.log('      reject  verifiability     category     quest');
  console.log('  ' + '-'.repeat(86));
  for (const row of rows) {
    const text = `${row.title} ${row.description ?? ''}`;
    // Only a problem where content is what decides. For provenance_only and
    // none the contract already says a photograph cannot settle the task, so
    // an unphotographable quest there is correctly marked.
    const content = row.verifiability === 'content';
    const taskReasons = content ? TASK_NOT_PHOTOGRAPHABLE.filter((r) => r.test.test(text)) : [];
    const clauseReasons = content && taskReasons.length === 0
      ? CLAUSE_NOT_PHOTOGRAPHABLE.filter((r) => r.test.test(text))
      : [];
    // A clause is only a gap if the rubric does not already cover it.
    const uncovered = clauseReasons.length > 0 && !RUBRIC_COVERS_CLAUSES.test(row.evidence_rubric ?? '');
    if (taskReasons.length > 0) wrongContract.push({ ...row, reasons: taskReasons });
    else if (uncovered) rubricGap.push({ ...row, reasons: clauseReasons });
    const mark = taskReasons.length > 0 ? 'WRONG' : uncovered ? 'rubric' : '     ';
    console.log(
      `  ${mark} ${String(row.may_auto_reject).padEnd(6)}`
      + ` ${row.verifiability.padEnd(17)} ${row.category.padEnd(12)} ${row.title.slice(0, 40)}`,
    );
  }

  console.log(`\n${'='.repeat(90)}`);

  if (wrongContract.length === 0 && rubricGap.length === 0) {
    console.log('\nNothing flagged. That is a keyword check, not a guarantee — the list above');
    console.log('is still worth reading once, especially any row with reject = true.\n');
  }

  if (wrongContract.length > 0) {
    console.log(`\nWRONG CONTRACT — ${wrongContract.length} quest(s) marked 'content' that no`);
    console.log("photograph can show. The agent is being asked an unanswerable question.\n");
    for (const row of wrongContract) {
      console.log(`  ${row.title}`);
      console.log(`    ${row.category}${row.has_override ? ', already overridden' : ''} · may_auto_reject ${row.may_auto_reject}`);
      for (const reason of row.reasons) console.log(`    · ${reason.code} — ${reason.why}`);
      console.log('');
    }
    console.log('Each is a question for a person: can a photograph show this task at all?');
    console.log('  yes → leave it; the keyword was a coincidence.');
    console.log('  no  → override it. Run again with --sql for the statements.\n');
  }

  if (rubricGap.length > 0) {
    console.log(`\nRUBRIC GAP — ${rubricGap.length} quest(s) that ARE photographable but carry a`);
    console.log('clause no photograph can settle, and whose rubric never says so.\n');
    for (const row of rubricGap) {
      console.log(`  ${row.title}`);
      for (const reason of row.reasons) console.log(`    · ${reason.code} — ${reason.why}`);
      console.log(`    rubric: ${(row.evidence_rubric ?? '').slice(0, 100)}…`);
      console.log('');
    }
    console.log('These do NOT want a verifiability override — that would discard the part');
    console.log('a photograph does show. They want a rubric that tells the model to ignore');
    console.log('the clause, the way the seeded fitness rubric already does:');
    console.log('');
    console.log('  "Counts and durations (\'50 push-ups\', \'30 minutes\') CANNOT be verified');
    console.log('   from an image — never reject for failing to show a count."');
    console.log('');
    console.log('Set quests.evidence_rubric for the quest, or amend the category default in');
    console.log('quest_verification_defaults.\n');
  }

  if (process.argv.includes('--sql') && wrongContract.length > 0) {
    console.log('-- Review each line before running. `none` means nothing in the image bears');
    console.log('-- on the task; `provenance_only` means the image cannot show the task but');
    console.log('-- its authenticity still matters. may_auto_reject is set false either way:');
    console.log('-- finalizeDecision gates rejection on that flag, so the verifiability');
    console.log('-- override alone would still let the agent reject one of these.');
    for (const row of wrongContract) {
      // The strongest reason wins: 'none' means nothing in the image bears on
      // the task at all, which is a stronger claim than provenance_only.
      const suggested = row.reasons.some((r) => r.suggest === 'none') ? 'none' : 'provenance_only';
      console.log(`\n-- ${row.title}  (${row.reasons.map((r) => r.code).join(', ')})`);
      console.log(`UPDATE quests SET verifiability = '${suggested}', may_auto_reject = false`);
      console.log(`  WHERE id = '${row.id}';`);
    }
    console.log('');
  }
} finally {
  await pool.end();
}
