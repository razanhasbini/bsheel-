import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { E2eHarness, type TestUser } from './support/e2e-harness.js';

/// Exposure telemetry ingest (#81 §28).
///
/// These counts are sold to businesses and nothing server-side can verify
/// them, so the properties worth testing are the ones that stop them being
/// inflated: a retried flush must not double-count, and a client must not
/// be able to report on somebody else's behalf.
describe('analytics ingest (e2e)', { timeout: 120_000 }, () => {
  let harness: E2eHarness;
  let user: TestUser;
  let other: TestUser;
  let questId: string;

  const event = (overrides: Record<string, unknown> = {}) => ({
    clientEventId: randomUUID(),
    eventType: 'quest_impression',
    questId,
    surface: 'feed',
    occurredAt: new Date().toISOString(),
    ...overrides,
  });

  const countFor = (userId: string) =>
    harness.countRows('SELECT count(*) FROM analytics_events WHERE user_id = $1', [userId]);

  beforeAll(async () => {
    harness = await E2eHarness.boot();
    user = await harness.createUser({ prefix: 'evuser' });
    other = await harness.createUser({ prefix: 'evother' });
    questId = (await harness.createQuest({ title: `Event quest ${randomUUID()}` })).id;
  });

  afterAll(async () => {
    if (harness) {
      await harness.database.query('DELETE FROM analytics_events WHERE user_id = ANY($1::uuid[])',
        [[user.id, other.id]]);
    }
    await harness?.close();
  });

  it('records a batch and says how many it took', async () => {
    const before = await countFor(user.id);

    const response = await harness
      .post('/analytics/events', user)
      .send({ events: [event(), event({ eventType: 'quest_detail_view' })] })
      .expect(202);

    expect(response.body.data.recorded).toBe(2);
    expect(await countFor(user.id)).toBe(before + 2);
  });

  /// The property that protects the numbers. A phone that loses its
  /// connection mid-flush resends the same client ids; if that inflated
  /// impressions, the one figure nobody can audit would be the easiest to
  /// corrupt by accident.
  it('takes a replayed flush once', async () => {
    const batch = { events: [event(), event()] };

    const first = await harness.post('/analytics/events', user).send(batch).expect(202);
    const second = await harness.post('/analytics/events', user).send(batch).expect(202);

    expect(first.body.data.recorded).toBe(2);
    // Accepted, not rejected — a retry is normal — but recorded zero more.
    expect(second.body.data.recorded).toBe(0);
  });

  // Attribution is the caller's, always. There is no userId in the payload,
  // and sending one must not change whose events these are.
  it('attributes events to the caller, whatever the payload says', async () => {
    const before = await countFor(other.id);

    await harness
      .post('/analytics/events', user)
      .send({ events: [{ ...event(), userId: other.id }] })
      // The extra property is refused outright by the global validation
      // pipe, which is the strongest form of this guarantee.
      .expect(400);

    expect(await countFor(other.id)).toBe(before);
  });

  it('refuses an anonymous caller', async () => {
    await harness.post('/analytics/events').send({ events: [event()] }).expect(401);
  });

  describe('what it will not accept', () => {
    it('rejects an unknown event type', async () => {
      await harness
        .post('/analytics/events', user)
        .send({ events: [event({ eventType: 'quest_approved' })] })
        .expect(400);
    });

    it('rejects an unknown surface', async () => {
      await harness
        .post('/analytics/events', user)
        .send({ events: [event({ surface: 'billboard' })] })
        .expect(400);
    });

    it('rejects an empty batch and an oversized one', async () => {
      await harness.post('/analytics/events', user).send({ events: [] }).expect(400);
      await harness
        .post('/analytics/events', user)
        .send({ events: Array.from({ length: 201 }, () => event()) })
        .expect(400);
    });
  });

  // A quest deleted between the impression and the flush must not take the
  // rest of the batch down with it: losing one event beats losing the
  // nineteen it travelled with.
  it('drops an event for a deleted quest and keeps the rest of the batch', async () => {
    const before = await countFor(user.id);

    const response = await harness
      .post('/analytics/events', user)
      .send({
        events: [
          event(),
          event({ questId: '00000000-0000-4000-8000-000000000000' }),
        ],
      })
      .expect(202);

    expect(response.body.data.recorded).toBe(1);
    expect(await countFor(user.id)).toBe(before + 1);
  });

  /// Clock clamping, visible in the row. Both timestamps are stored so the
  /// clamp can be seen rather than silently rewriting when something
  /// happened.
  it('clamps a timestamp from a badly wrong clock', async () => {
    const clientEventId = randomUUID();
    await harness
      .post('/analytics/events', user)
      .send({ events: [event({ clientEventId, occurredAt: '2019-04-02T00:00:00.000Z' })] })
      .expect(202);

    const row = await harness.database.query<{ occurred_at: Date; received_at: Date }>(
      'SELECT occurred_at, received_at FROM analytics_events WHERE client_event_id = $1',
      [clientEventId],
    );
    const { occurred_at: occurred, received_at: received } = row.rows[0];
    expect(occurred.getFullYear()).toBe(received.getFullYear());
    // Pulled up to the backdate limit rather than dropped.
    expect(received.getTime() - occurred.getTime()).toBeLessThanOrEqual(2 * 60 * 60 * 1000 + 5_000);
  });
});
