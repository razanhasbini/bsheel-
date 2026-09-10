import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { createServer } from 'node:http';
import process from 'node:process';
import pg from 'pg';

const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');
const apiBase = 'http://127.0.0.1:3013/api/v1';
const mockPort = 3912;
const secret = 'telegram-smoke-secret';
const chatId = 42;
const calls = [];
let messageId = 700;

const mock = createServer(async (request, response) => {
  const chunks = [];
  for await (const chunk of request) chunks.push(chunk);
  const body = JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}');
  calls.push({ path: request.url, body });
  response.writeHead(200, { 'content-type': 'application/json' });
  response.end(JSON.stringify({ ok: true, result: { message_id: ++messageId } }));
});

async function post(update, expected = 200, suppliedSecret = secret) {
  const response = await fetch(`${apiBase}/integrations/telegram/webhook`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'x-telegram-bot-api-secret-token': suppliedSecret,
    },
    body: JSON.stringify(update),
  });
  const raw = await response.text();
  if (response.status !== expected) throw new Error(`Telegram webhook expected ${expected}, got ${response.status}: ${raw}`);
}

async function waitForApi(child) {
  const started = Date.now();
  while (Date.now() - started < 20_000) {
    if (child.exitCode !== null) throw new Error(`API exited before Telegram smoke started (${child.exitCode})`);
    try {
      const response = await fetch('http://127.0.0.1:3013/api/v1/health/live');
      if (response.ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  throw new Error('Timed out waiting for Telegram smoke API');
}

function update(updateId, text) {
  return { update_id: updateId, message: { message_id: updateId, chat: { id: chatId }, text } };
}

const suffix = randomUUID().slice(0, 8);
const pool = new pg.Pool({ connectionString: databaseUrl, max: 1 });
const ids = { users: [], quests: [], submissions: [], reports: [] };
let api;

try {
  await new Promise((resolve, reject) => {
    mock.once('error', reject);
    mock.listen(mockPort, '127.0.0.1', resolve);
  });
  api = spawn(process.execPath, ['--enable-source-maps', 'dist/main.js'], {
    cwd: process.cwd(),
    env: {
      ...process.env,
      NODE_ENV: 'test', PORT: '3013', DATABASE_URL: databaseUrl,
      REDIS_URL: 'redis://127.0.0.1:63799', REDIS_KEY_PREFIX: `bsheel:telegram-smoke:${suffix}:`,
      AUTH_EMAIL_CONFIRMATION_REQUIRED: 'false', PUSH_NOTIFICATIONS_ENABLED: 'false',
      TELEGRAM_ENABLED: 'true', TELEGRAM_BOT_TOKEN: 'fixture-token',
      TELEGRAM_ADMIN_CHAT_ID: String(chatId), TELEGRAM_ALLOWED_CHAT_IDS: String(chatId),
      TELEGRAM_WEBHOOK_SECRET: secret, TELEGRAM_API_BASE_URL: `http://127.0.0.1:${mockPort}`,
      SWAGGER_ENABLED: 'false', LOG_LEVEL: 'silent',
    },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let apiOutput = '';
  api.stdout.on('data', (chunk) => { apiOutput += chunk; });
  api.stderr.on('data', (chunk) => { apiOutput += chunk; });
  await waitForApi(api).catch((error) => { throw new Error(`${error.message}\n${apiOutput}`); });

  await post(update(7001, '/help'), 403, 'wrong-secret');
  await post(update(7002, '/help'));
  const afterHelp = calls.length;
  await post(update(7002, '/help'));
  if (calls.length !== afterHelp) throw new Error('Duplicate Telegram update executed twice');

  const title = `Telegram Quest ${suffix}`;
  for (const [id, input] of [
    [7010, '/quest add'], [7011, title], [7012, 'Complete a careful migration task'],
    [7013, 'learning'], [7014, 'hard'], [7015, '25'], [7016, 'YES'],
  ]) await post(update(id, input));
  const createdQuest = await pool.query('SELECT id, xp_reward FROM quests WHERE title = $1', [title]);
  if (createdQuest.rowCount !== 1 || createdQuest.rows[0].xp_reward !== 25) {
    throw new Error('Telegram quest state machine did not create the expected quest');
  }
  ids.quests.push(createdQuest.rows[0].id);

  const reviewer = await pool.query(
    `INSERT INTO users (email, password_hash, email_verified_at) VALUES ($1, 'fixture', now()) RETURNING id`,
    [`telegram-reviewer-${suffix}@example.test`],
  );
  const offender = await pool.query(
    `INSERT INTO users (email, password_hash, email_verified_at) VALUES ($1, 'fixture', now()) RETURNING id`,
    [`telegram-offender-${suffix}@example.test`],
  );
  ids.users.push(reviewer.rows[0].id, offender.rows[0].id);
  await pool.query(
    `INSERT INTO profiles (id, username, display_name) VALUES ($1, $2, 'Telegram Reviewer'), ($3, $4, 'Telegram Offender')`,
    [reviewer.rows[0].id, `tg_review_${suffix}`, offender.rows[0].id, `tg_offend_${suffix}`],
  );
  const reviewQuest = await pool.query(
    `INSERT INTO quests (title, description, category, difficulty, xp_reward)
     VALUES ($1, 'Telegram callback review fixture', 'learning', 'easy', 19) RETURNING id`,
    [`Telegram Review ${suffix}`],
  );
  ids.quests.push(reviewQuest.rows[0].id);
  const assignment = await pool.query(
    `INSERT INTO user_quests (user_id, quest_id, status, expires_at)
     VALUES ($1, $2, 'submitted', now() + interval '4 hours') RETURNING id`,
    [reviewer.rows[0].id, reviewQuest.rows[0].id],
  );
  const submission = await pool.query(
    `INSERT INTO submissions (user_quest_id, user_id, media_url, status)
     VALUES ($1, $2, 'fixture.jpg', 'pending') RETURNING id`,
    [assignment.rows[0].id, reviewer.rows[0].id],
  );
  ids.submissions.push(submission.rows[0].id);
  await post({
    update_id: 7020,
    callback_query: {
      id: 'approve-callback', data: `approve:${submission.rows[0].id}`,
      message: { message_id: 88, chat: { id: chatId }, text: 'Review this submission' },
    },
  });
  const approved = await pool.query(
    `SELECT submission.status, submission.reviewed_by, profile.xp
     FROM submissions submission JOIN profiles profile ON profile.id = submission.user_id
     WHERE submission.id = $1`, [submission.rows[0].id],
  );
  if (approved.rows[0]?.status !== 'approved' || approved.rows[0].reviewed_by !== null || approved.rows[0].xp !== 19) {
    throw new Error(`Telegram approval did not use the canonical review logic: ${JSON.stringify(approved.rows[0])}`);
  }

  const report = await pool.query(
    `INSERT INTO reports (reporter_id, reported_type, reported_id, reason)
     VALUES ($1, 'user', $2, 'Telegram action smoke') RETURNING id`,
    [reviewer.rows[0].id, offender.rows[0].id],
  );
  ids.reports.push(report.rows[0].id);
  await post({
    update_id: 7030,
    callback_query: {
      id: 'report-callback', data: `report_action:${report.rows[0].id}`,
      message: { message_id: 89, chat: { id: chatId }, text: 'Review this report' },
    },
  });
  const actioned = await pool.query(
    `SELECT report.status, users.status AS user_status FROM reports report
     JOIN users ON users.id::text = report.reported_id WHERE report.id = $1`, [report.rows[0].id],
  );
  if (actioned.rows[0]?.status !== 'actioned' || actioned.rows[0].user_status !== 'banned') {
    throw new Error('Telegram report action did not atomically ban and action the report');
  }

  const updates = await pool.query(
    `SELECT count(*)::integer AS count FROM telegram_webhook_updates
     WHERE update_id = ANY($1::bigint[]) AND status = 'processed'`,
    [[7002, 7010, 7011, 7012, 7013, 7014, 7015, 7016, 7020, 7030]],
  );
  if (updates.rows[0].count !== 10) throw new Error('Telegram webhook updates were not marked processed');
  console.log('Telegram smoke passed: secret gate, duplicate suppression, admin commands/FSM, canonical submission review, report action, and mocked Bot API calls');
} finally {
  if (api && api.exitCode === null) api.kill('SIGTERM');
  await new Promise((resolve) => mock.close(resolve));
  await pool.query(
    `DELETE FROM outbox_events WHERE payload->>'userId' = ANY($1::text[])
       OR aggregate_id = ANY($2::uuid[])`,
    [ids.users, ids.submissions],
  ).catch(() => undefined);
  // admin_audit_log is append-only (migration 0027), so the DELETE that used
  // to run here now raises restrict_violation. The rows this smoke run appends
  // are left in place: they are the record that these admin commands ran, and
  // nothing points at them.
  if (ids.users.length) await pool.query('DELETE FROM users WHERE id = ANY($1::uuid[])', [ids.users]);
  if (ids.quests.length) await pool.query('DELETE FROM quests WHERE id = ANY($1::uuid[])', [ids.quests]);
  await pool.query('DELETE FROM telegram_command_state WHERE chat_id = $1', [chatId]);
  await pool.query('DELETE FROM telegram_webhook_updates WHERE update_id BETWEEN 7000 AND 7099');
  await pool.end();
}
