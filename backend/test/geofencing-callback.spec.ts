import { NotFoundException } from '@nestjs/common';
import { describe, expect, it, vi } from 'vitest';
import { GeofencingCallbackController } from '../src/modules/agent/presentation/geofencing-callback.controller.js';
import type { GeofencingRepository } from '../src/modules/agent/infrastructure/geofencing.repository.js';

function build() {
  const repository = {
    findById: vi.fn().mockResolvedValue({
      id: '00000000-0000-4000-8000-000000000001',
      callbackSecret: 'expected-token',
    }),
    recordEvent: vi.fn().mockResolvedValue(undefined),
  } as unknown as GeofencingRepository;
  return { controller: new GeofencingCallbackController(repository), repository };
}

describe('CAMARA geofencing callback', () => {
  it('rejects a missing or invalid bearer sink credential', async () => {
    const { controller } = build();
    await expect(controller.receive(
      { subscriptionId: '00000000-0000-4000-8000-000000000001' },
      'Bearer wrong',
      {},
    )).rejects.toBeInstanceOf(NotFoundException);
  });

  it.each([
    ['area-entered', 'ENTER'],
    ['area-left', 'EXIT'],
  ] as const)('records %s events with the provider timestamp', async (suffix, mapped) => {
    const { controller, repository } = build();
    await controller.receive(
      { subscriptionId: '00000000-0000-4000-8000-000000000001' },
      'Bearer expected-token',
      {
        id: `event-${mapped}`,
        type: `org.camaraproject.geofencing-subscriptions.v0.${suffix}`,
        time: '2026-09-10T10:30:00.000Z',
      },
    );
    expect(repository.recordEvent).toHaveBeenCalledWith({
      subscriptionId: '00000000-0000-4000-8000-000000000001',
      type: mapped,
      occurredAt: new Date('2026-09-10T10:30:00.000Z'),
      providerEventId: `event-${mapped}`,
    });
  });
});
