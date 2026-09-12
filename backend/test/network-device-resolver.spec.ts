import { describe, expect, it, vi } from 'vitest';
import { ForbiddenException } from '@nestjs/common';
import { ConfigurableNetworkDeviceResolver } from '../src/modules/agent/infrastructure/network-device.resolver.js';

/// The resolver is the only thing standing between "a demo switch" and "a
/// simulator device deciding a real person's quest", so these are safety
/// tests before they are behaviour tests.
describe('NetworkDeviceResolver', () => {
  const build = (options: { personasEnabled?: boolean; phoneNumber?: string | null } = {}) => {
    // `??` would swallow an explicit null, which is the case that matters
    // most here — "the user has no verified number" is not the same as
    // "the test did not say".
    const phoneNumber = 'phoneNumber' in options ? options.phoneNumber : '+96170123456';
    const contextService = {
      phoneNumberForUser: vi.fn(async () => phoneNumber),
    };
    const config = {
      get: vi.fn((key: string) =>
        key === 'CAMARA_DEMO_PERSONAS_ENABLED' ? (options.personasEnabled ?? false) : undefined),
    };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return { resolver: new ConfigurableNetworkDeviceResolver(contextService as any, config as any), contextService };
  };

  it('resolves a live user to their own verified number', async () => {
    const { resolver, contextService } = build();
    await expect(resolver.resolve({ userId: 'u1' })).resolves.toEqual({
      identifier: '+96170123456',
      source: 'LIVE_OPERATOR',
    });
    expect(contextService.phoneNumberForUser).toHaveBeenCalledWith('u1');
  });

  it('returns null with a reason when the user has no verified number', async () => {
    // Null, never a substitute. Every adapter turns this into UNAVAILABLE,
    // which routes to a human — the one correct answer when we cannot say
    // which device to ask about.
    const { resolver } = build({ phoneNumber: null });
    const device = await resolver.resolve({ userId: 'u1' });
    expect(device).toMatchObject({ identifier: null, source: 'LIVE_OPERATOR' });
    expect(device.unavailableReason).toMatch(/no camara-verified phone number/i);
  });

  it('refuses a persona when the deployment is not entitled to one', async () => {
    // The production guarantee: a payload carrying a persona changes
    // nothing on a box where personas are off. It is refused rather than
    // ignored, so the caller cannot believe it got a demo run.
    const { resolver } = build({ personasEnabled: false });
    await expect(resolver.resolve({ userId: 'u1', personaId: 'LOCATION_INSIDE' }))
      .rejects.toBeInstanceOf(ForbiddenException);
  });

  it('refuses an unknown persona even when personas are enabled', async () => {
    // Falling back to the live number here would produce a run labelled as
    // a demo that actually asked about a real person's handset.
    const { resolver, contextService } = build({ personasEnabled: true });
    await expect(resolver.resolve({ userId: 'u1', personaId: 'LOCATION_ALWAYS_YES' }))
      .rejects.toBeInstanceOf(ForbiddenException);
    expect(contextService.phoneNumberForUser).not.toHaveBeenCalled();
  });

  it('refuses a raw phone number as a persona', async () => {
    // Personas are ids, not numbers. Accepting a number would make the
    // endpoint an "ask CAMARA about any handset" tool.
    const { resolver } = build({ personasEnabled: true });
    await expect(resolver.resolve({ userId: 'u1', personaId: '+99999991001' }))
      .rejects.toBeInstanceOf(ForbiddenException);
  });

  it('resolves a known persona to its Nokia simulator device', async () => {
    const { resolver, contextService } = build({ personasEnabled: true });
    const device = await resolver.resolve({ userId: 'u1', personaId: 'LOCATION_INSIDE' });
    expect(device.identifier).toBe('+99999991001');
    expect(device.source).toBe('NOKIA_SIMULATOR');
    expect(device.persona?.id).toBe('LOCATION_INSIDE');
    // The user's own number is never read on this path, and never written:
    // authentication identity is untouched by a demo selection.
    expect(contextService.phoneNumberForUser).not.toHaveBeenCalled();
  });

  it('treats an empty persona as no persona at all', async () => {
    const { resolver } = build({ personasEnabled: true });
    await expect(resolver.resolve({ userId: 'u1', personaId: '   ' }))
      .resolves.toMatchObject({ source: 'LIVE_OPERATOR' });
  });
});
