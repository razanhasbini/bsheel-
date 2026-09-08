import { describe, expect, it, vi } from 'vitest';
import { OutboxPublisher } from '../src/infrastructure/messaging/outbox.publisher.js';
import type { DatabaseService } from '../src/infrastructure/database/database.service.js';
import type { ConfigService } from '@nestjs/config';
import type { Environment } from '../src/config/environment.js';
import type { Queue } from 'bullmq';

function fixture() {
  const events = [
    { id: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa', event_type: 'profile.updated', payload: { profileId: 'one' }, attempts: 1 },
    { id: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb', event_type: 'profile.updated', payload: { profileId: 'two' }, attempts: 1 },
  ];
  const database = { query: vi.fn().mockResolvedValueOnce({ rows: events }).mockResolvedValue({ rows: [] }) };
  const queue = { addBulk: vi.fn().mockResolvedValue([]) };
  const config = { get: vi.fn().mockReturnValue(50) };
  const publisher = new OutboxPublisher(database as unknown as DatabaseService, config as unknown as ConfigService<Environment, true>, queue as unknown as Queue);
  return { publisher, database, queue, events };
}

describe('OutboxPublisher', () => {
  it('publishes one atomic batch with stable IDs and acknowledges it in one statement', async () => {
    const { publisher, database, queue, events } = fixture();
    await publisher.drain();
    expect(queue.addBulk).toHaveBeenCalledTimes(1);
    expect(queue.addBulk.mock.calls[0][0].map((job: { opts: { jobId: string } }) => job.opts.jobId)).toEqual(events.map((event) => event.id));
    expect(database.query).toHaveBeenCalledTimes(2);
    expect(database.query.mock.calls[1][0]).toContain('SET processed_at = now()');
    expect(database.query.mock.calls[1][1]).toEqual([events.map((event) => event.id)]);
  });

  it('backs off a failed batch without acknowledging any event', async () => {
    const { publisher, database, queue } = fixture();
    queue.addBulk.mockRejectedValueOnce(new Error('Redis unavailable'));
    await publisher.drain();
    expect(database.query.mock.calls[1][0]).toContain('SET last_error = $2');
    expect(database.query.mock.calls[1][1][1]).toBe('Redis unavailable');
  });

  it('waits for an in-flight drain during shutdown and rejects later polling', async () => {
    const { publisher, database, queue } = fixture();
    let release!: () => void;
    queue.addBulk.mockImplementationOnce(() => new Promise<void>((resolve) => { release = resolve; }));
    const drain = publisher.drain();
    await vi.waitFor(() => expect(queue.addBulk).toHaveBeenCalledTimes(1));
    let stopped = false;
    const shutdown = publisher.onModuleDestroy().then(() => { stopped = true; });
    await Promise.resolve();
    expect(stopped).toBe(false);
    release();
    await Promise.all([drain, shutdown]);
    await publisher.drain();
    expect(database.query).toHaveBeenCalledTimes(2);
  });
});
