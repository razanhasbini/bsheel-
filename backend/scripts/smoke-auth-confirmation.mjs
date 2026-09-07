import { createHash, randomUUID } from 'node:crypto';
import process from 'node:process';
import pg from 'pg';

const baseUrl = process.env.API_BASE_URL ?? 'http://127.0.0.1:3010/api/v1';
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

async function request(path, { expected = 200, ...options } = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: { 'content-type': 'application/json', ...options.headers },
  });
  const raw = await response.text();
  const body = raw ? JSON.parse(raw) : undefined;
  if (response.status !== expected) {
    throw new Error(`${options.method ?? 'GET'} ${path}: expected ${expected}, got ${response.status}: ${raw}`);
  }
  return body;
}

const suffix = randomUUID().slice(0, 8);
const email = `confirm-${suffix}@example.test`;
const pool = new pg.Pool({ connectionString: databaseUrl, max: 1 });
let userId;

try {
  const signup = await request('/auth/register', {
    method: 'POST', expected: 201,
    body: JSON.stringify({
      email,
      password: 'Confirmation-Canyon-382!',
      username: `confirm_${suffix}`,
      displayName: 'Confirmation User',
      ageVerified: true,
    }),
  });
  if (signup.data?.confirmationRequired !== true || signup.data?.accessToken) {
    throw new Error(`Signup bypassed email confirmation: ${JSON.stringify(signup)}`);
  }
  const account = await pool.query(
    'SELECT id, email_verified_at FROM users WHERE email = $1',
    [email],
  );
  userId = account.rows[0]?.id;
  if (!userId || account.rows[0].email_verified_at !== null) {
    throw new Error('Password account was not created in the unconfirmed state');
  }
  const initialAction = await pool.query(
    `SELECT token.id, token.encrypted_token, token.token_hash,
            EXISTS (
              SELECT 1 FROM outbox_events event
              WHERE event.aggregate_id = token.id
                AND event.event_type = 'auth.email_confirmation.requested'
            ) AS queued
     FROM auth_action_tokens token
     WHERE token.user_id = $1 AND token.purpose = 'email_confirmation'
       AND token.consumed_at IS NULL`,
    [userId],
  );
  if (initialAction.rowCount !== 1
      || initialAction.rows[0].encrypted_token.length <= 28
      || initialAction.rows[0].token_hash.length !== 32
      || !initialAction.rows[0].queued) {
    throw new Error('Initial confirmation token was not protected and queued atomically');
  }
  const rejectedLogin = await request('/auth/login', {
    method: 'POST', expected: 403,
    body: JSON.stringify({ email, password: 'Confirmation-Canyon-382!' }),
  });
  if (rejectedLogin.error?.code !== 'EMAIL_NOT_CONFIRMED') {
    throw new Error(`Unconfirmed login returned the wrong contract: ${JSON.stringify(rejectedLogin)}`);
  }

  const countBeforeUnknown = await pool.query(
    "SELECT count(*)::integer AS count FROM auth_action_tokens WHERE purpose = 'email_confirmation'",
  );
  await request('/auth/email-confirmation/resend', {
    method: 'POST', expected: 202,
    body: JSON.stringify({ email: `missing-${suffix}@example.test` }),
  });
  const countAfterUnknown = await pool.query(
    "SELECT count(*)::integer AS count FROM auth_action_tokens WHERE purpose = 'email_confirmation'",
  );
  if (countAfterUnknown.rows[0].count !== countBeforeUnknown.rows[0].count) {
    throw new Error('Unknown-email confirmation resend created a token');
  }

  await request('/auth/email-confirmation/resend', {
    method: 'POST', expected: 202,
    body: JSON.stringify({ email }),
  });
  const replacementState = await pool.query(
    `SELECT count(*) FILTER (WHERE consumed_at IS NULL)::integer AS active,
            count(*) FILTER (WHERE consumed_at IS NOT NULL)::integer AS consumed
     FROM auth_action_tokens
     WHERE user_id = $1 AND purpose = 'email_confirmation'`,
    [userId],
  );
  if (replacementState.rows[0].active !== 1 || replacementState.rows[0].consumed !== 1) {
    throw new Error(`Confirmation resend did not supersede the old link: ${JSON.stringify(replacementState.rows[0])}`);
  }

  const rawToken = `confirmation-token-${randomUUID()}`;
  await pool.query(
    `INSERT INTO auth_action_tokens
       (user_id, purpose, token_hash, encrypted_token, expires_at)
     VALUES ($1, 'email_confirmation', $2, $3, now() + interval '10 minutes')`,
    [
      userId,
      createHash('sha256').update(rawToken, 'utf8').digest(),
      Buffer.from('integration-placeholder-ciphertext'),
    ],
  );
  await request('/auth/email-confirmation/complete', {
    method: 'POST', expected: 204,
    body: JSON.stringify({ token: rawToken }),
  });
  await request('/auth/email-confirmation/complete', {
    method: 'POST', expected: 400,
    body: JSON.stringify({ token: rawToken }),
  });
  const login = await request('/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password: 'Confirmation-Canyon-382!' }),
  });
  if (!login.data?.accessToken || !login.data?.refreshToken) {
    throw new Error('Confirmed account did not receive a token pair');
  }
  console.log('Email-confirmation smoke passed: protected outbox delivery, enumeration resistance, resend supersession, login gate, one-time confirmation, and successful login');
} finally {
  if (userId) await pool.query('DELETE FROM users WHERE id = $1', [userId]);
  await pool.end();
}
