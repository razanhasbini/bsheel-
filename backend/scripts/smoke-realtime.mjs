import { randomUUID } from 'node:crypto';
import process from 'node:process';
import pg from 'pg';
import { io } from 'socket.io-client';

const apiBaseUrl = process.env.API_BASE_URL ?? 'http://127.0.0.1:3010/api/v1';
const socketBaseUrl = process.env.SOCKET_BASE_URL ?? 'http://127.0.0.1:3010';
const databaseUrl = process.env.DATABASE_URL;
if (!databaseUrl) throw new Error('DATABASE_URL is required');

async function register(email, username) {
  const response = await fetch(`${apiBaseUrl}/auth/register`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      email,
      password: 'Realtime-Canyon-637!',
      username,
      displayName: username,
      ageVerified: true,
    }),
  });
  const raw = await response.text();
  if (response.status !== 201) throw new Error(`Realtime registration failed: ${raw}`);
  return JSON.parse(raw).data;
}

function connect(token) {
  return io(`${socketBaseUrl}/realtime`, {
    transports: ['websocket'],
    auth: { token },
    reconnection: false,
    forceNew: true,
  });
}

function once(socket, event, timeoutMs = 8000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error(`Timed out waiting for ${event}`)), timeoutMs);
    socket.once(event, (value) => {
      clearTimeout(timer);
      resolve(value);
    });
  });
}

const suffix = randomUUID().slice(0, 8);
const pool = new pg.Pool({ connectionString: databaseUrl, max: 1 });
const userIds = [];
const sockets = [];

try {
  const first = await register(`socket-a-${suffix}@example.test`, `socket_a_${suffix}`);
  const second = await register(`socket-b-${suffix}@example.test`, `socket_b_${suffix}`);
  const rows = await pool.query(
    'SELECT id FROM users WHERE email = ANY($1::text[]) ORDER BY email',
    [[`socket-a-${suffix}@example.test`, `socket-b-${suffix}@example.test`]],
  );
  userIds.push(...rows.rows.map((row) => row.id));
  if (userIds.length !== 2) throw new Error('Realtime fixture accounts were not created');

  const invalid = connect('not-a-valid-token');
  sockets.push(invalid);
  const invalidError = await once(invalid, 'auth.error');
  if (invalidError?.code !== 'INVALID_ACCESS_TOKEN') {
    throw new Error(`Invalid socket returned the wrong auth contract: ${JSON.stringify(invalidError)}`);
  }

  const firstSocket = connect(first.accessToken);
  const secondSocket = connect(second.accessToken);
  sockets.push(firstSocket, secondSocket);
  await Promise.all([once(firstSocket, 'ready'), once(secondSocket, 'ready')]);

  let leaked = false;
  secondSocket.on('domain.event', () => { leaked = true; });
  const firstEvent = once(firstSocket, 'domain.event');
  await pool.query(
    `INSERT INTO outbox_events (aggregate_type, aggregate_id, event_type, payload)
     VALUES ('user', $1, 'notification.read', $2::jsonb)`,
    [userIds[0], JSON.stringify({ userId: userIds[0], notificationId: null })],
  );
  const delivered = await firstEvent;
  if (delivered?.type !== 'notification.read' || delivered?.data?.userId !== userIds[0]) {
    throw new Error(`Realtime event payload was wrong: ${JSON.stringify(delivered)}`);
  }
  await new Promise((resolve) => setTimeout(resolve, 400));
  if (leaked) throw new Error('User-scoped notification event leaked to another authenticated user');

  console.log('Realtime smoke passed: JWT socket authentication, invalid-token rejection, Redis/BullMQ bridge, and user-room isolation');
} finally {
  for (const socket of sockets) socket.disconnect();
  if (userIds.length) await pool.query('DELETE FROM users WHERE id = ANY($1::uuid[])', [userIds]);
  await pool.end();
}
