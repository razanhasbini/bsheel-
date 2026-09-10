import { describe, expect, it, vi } from 'vitest';
import type { ConfigService } from '@nestjs/config';
import type { JwtService } from '@nestjs/jwt';
import type { Server } from 'socket.io';
import type { Environment } from '../src/config/environment.js';
import type { AuthRepository } from '../src/modules/auth/infrastructure/auth.repository.js';
import { RealtimeGateway } from '../src/infrastructure/realtime/realtime.gateway.js';
import type { RealtimeDomainEvent } from '../src/infrastructure/realtime/realtime-event.publisher.js';

interface Delivery {
  rooms: string[];
  excluded: string[];
  data: Record<string, unknown>;
}

/**
 * Records where each event went, so a test can ask the question the audit
 * asked: does a user with no relationship to this event receive it?
 */
function fakeServer() {
  const deliveries: Delivery[] = [];

  function operator(rooms: string[], excluded: string[] = []) {
    return {
      except(more: string | string[]) {
        return operator(rooms, [
          ...excluded,
          ...(Array.isArray(more) ? more : [more]),
        ]);
      },
      emit(_name: string, event: RealtimeDomainEvent) {
        deliveries.push({ rooms, excluded, data: event.data });
      },
    };
  }

  const server = {
    to(rooms: string | string[]) {
      return operator(Array.isArray(rooms) ? rooms : [rooms]);
    },
  };
  return { server: server as unknown as Server, deliveries };
}

function gateway(auth: Partial<AuthRepository> = {}) {
  const { server, deliveries } = fakeServer();
  const instance = new RealtimeGateway(
    {} as unknown as JwtService,
    { get: vi.fn() } as unknown as ConfigService<Environment, true>,
    auth as AuthRepository,
  );
  instance.server = server;
  return { instance, deliveries };
}

function event(
  type: string,
  data: Record<string, unknown>,
): RealtimeDomainEvent {
  return {
    messageId: 'm1',
    type,
    data,
    aggregateType: type.split('.')[0]!,
    aggregateId: 'a1',
    occurredAt: '2026-09-10T00:00:00.000Z',
  };
}

/** Every room a socket for `userId` (a plain user) sits in. */
function roomsOf(userId: string, extra: string[] = []) {
  return new Set([`user:${userId}`, 'feed', ...extra]);
}

function receivedBy(
  deliveries: Delivery[],
  rooms: Set<string>,
): Record<string, unknown>[] {
  return deliveries
    .filter(
      (delivery) =>
        delivery.rooms.some((room) => rooms.has(room)) &&
        !delivery.excluded.some((room) => rooms.has(room)),
    )
    .map((delivery) => delivery.data);
}

const AUTHOR = '11111111-1111-4111-8111-111111111111';
const STRANGER = '22222222-2222-4222-8222-222222222222';
const SUBMISSION = '33333333-3333-4333-8333-333333333333';

describe('RealtimeGateway event scoping', () => {
  it('does not send a stranger another user’s submission transitions', () => {
    const { instance, deliveries } = gateway();
    for (const type of [
      'submission.created',
      'submission.approved',
      'submission.rejected',
      'submission.appealed',
      'submission.visibility_changed',
      'submission.deleted',
    ]) {
      instance.broadcast(
        event(type, { submissionId: SUBMISSION, userId: AUTHOR }),
      );
    }
    expect(receivedBy(deliveries, roomsOf(STRANGER))).toEqual([]);
  });

  it('still delivers those transitions to the author, the post and staff', () => {
    const { instance, deliveries } = gateway();
    instance.broadcast(
      event('submission.approved', {
        submissionId: SUBMISSION,
        userId: AUTHOR,
      }),
    );
    expect(receivedBy(deliveries, roomsOf(AUTHOR))).toHaveLength(1);
    expect(
      receivedBy(deliveries, roomsOf(STRANGER, [`post:${SUBMISSION}`])),
    ).toHaveLength(1);
    expect(receivedBy(deliveries, roomsOf(STRANGER, ['admin']))).toHaveLength(
      1,
    );
  });

  it('gives a stranger the profile id but never the reason behind the update', () => {
    const { instance, deliveries } = gateway();
    instance.broadcast(
      event('profile.updated', { profileId: AUTHOR, reason: 'xp_restored' }),
    );

    // The leaderboard and an open profile page both still refresh.
    const toStranger = receivedBy(deliveries, roomsOf(STRANGER));
    expect(toStranger).toEqual([{ profileId: AUTHOR }]);

    // The owner keeps the full payload.
    expect(receivedBy(deliveries, roomsOf(AUTHOR))).toEqual([
      { profileId: AUTHOR, reason: 'xp_restored' },
    ]);
  });

  it('tells a stranger a follow happened without saying who followed whom', () => {
    const { instance, deliveries } = gateway();
    instance.broadcast(
      event('social.follow.changed', {
        userId: AUTHOR,
        targetUserId: STRANGER,
      }),
    );
    const bystander = '44444444-4444-4444-8444-444444444444';
    expect(receivedBy(deliveries, roomsOf(bystander))).toEqual([{}]);
    // Both participants get the real thing.
    expect(receivedBy(deliveries, roomsOf(AUTHOR))[0]).toMatchObject({
      userId: AUTHOR,
      targetUserId: STRANGER,
    });
    expect(receivedBy(deliveries, roomsOf(STRANGER))[0]).toMatchObject({
      targetUserId: STRANGER,
    });
  });

  it('keeps reactions and comments to the post’s own subscribers', () => {
    const { instance, deliveries } = gateway();
    instance.broadcast(
      event('social.reaction.changed', {
        submissionId: SUBMISSION,
        userId: AUTHOR,
      }),
    );
    expect(receivedBy(deliveries, roomsOf(STRANGER))).toEqual([]);
    expect(
      receivedBy(deliveries, roomsOf(STRANGER, [`post:${SUBMISSION}`])),
    ).toHaveLength(1);
  });

  it('keeps reports to staff', () => {
    const { instance, deliveries } = gateway();
    instance.broadcast(event('report.created', { reportId: 'r1' }));
    expect(receivedBy(deliveries, roomsOf(STRANGER))).toEqual([]);
    expect(receivedBy(deliveries, roomsOf(STRANGER, ['admin']))).toHaveLength(
      1,
    );
  });
});

function fakeSocket(userId: string, tokenVersion: number) {
  return {
    data: { user: { id: userId, email: 'x@y.z', role: null, tokenVersion } },
    emit: vi.fn(),
    disconnect: vi.fn(),
  };
}

/** Registers sockets on the gateway without going through a handshake. */
function attach(instance: RealtimeGateway, sockets: unknown[]): void {
  const connected = (
    instance as unknown as { connected: Set<unknown> }
  ).connected;
  for (const socket of sockets) connected.add(socket);
}

async function sweep(instance: RealtimeGateway): Promise<void> {
  await (
    instance as unknown as {
      expireRevokedSockets(ids?: readonly string[]): Promise<void>;
    }
  ).expireRevokedSockets();
}

describe('RealtimeGateway session revalidation', () => {
  it('closes a socket whose token version has moved on', async () => {
    const liveTokenVersions = vi.fn().mockResolvedValue(new Map([[AUTHOR, 4]]));
    const { instance } = gateway({ liveTokenVersions } as never);
    const stale = fakeSocket(AUTHOR, 3);
    attach(instance, [stale]);

    await sweep(instance);

    expect(stale.emit).toHaveBeenCalledWith('auth.error', {
      code: 'SESSION_REVOKED',
    });
    expect(stale.disconnect).toHaveBeenCalledWith(true);
  });

  it('closes a socket whose account is no longer active', async () => {
    const liveTokenVersions = vi.fn().mockResolvedValue(new Map());
    const { instance } = gateway({ liveTokenVersions } as never);
    const banned = fakeSocket(AUTHOR, 3);
    attach(instance, [banned]);

    await sweep(instance);

    expect(banned.disconnect).toHaveBeenCalledWith(true);
  });

  it('leaves a current session alone', async () => {
    const liveTokenVersions = vi.fn().mockResolvedValue(new Map([[AUTHOR, 3]]));
    const { instance } = gateway({ liveTokenVersions } as never);
    const current = fakeSocket(AUTHOR, 3);
    attach(instance, [current]);

    await sweep(instance);

    expect(current.disconnect).not.toHaveBeenCalled();
  });

  it('disconnects nobody when the lookup itself fails', async () => {
    const liveTokenVersions = vi
      .fn()
      .mockRejectedValue(new Error('database unreachable'));
    const { instance } = gateway({ liveTokenVersions } as never);
    const socket = fakeSocket(AUTHOR, 3);
    attach(instance, [socket]);

    await sweep(instance);

    // An unreachable database is not evidence that a session was revoked.
    expect(socket.disconnect).not.toHaveBeenCalled();
  });
});
