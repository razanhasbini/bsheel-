import type { ConfigService } from '@nestjs/config';
import { describe, expect, it, vi } from 'vitest';
import type { Environment } from '../src/config/environment.js';
import { CamaraEvidenceAdapter } from '../src/integrations/camara/camara-evidence.adapter.js';
import type { CamaraClientFactory } from '../src/integrations/camara/camara-client.factory.js';
import type { LocationEvidenceQuery } from '../src/modules/agent/domain/network-evidence.port.js';
import {
  mandatoryEvidenceSatisfied,
  mandatoryEvidenceStatus,
} from '../src/modules/agent/domain/verification-policy.js';
import type { NetworkEvidence } from '../src/modules/agent/domain/agent.schemas.js';

/**
 * Device Reachability (#73): optional context, and never a verdict.
 *
 * The whole reason this capability was chosen is the case where location
 * evidence is UNAVAILABLE. Knowing the handset was off the network explains
 * the gap and argues for a human, where a rejection would be a guess. What
 * it must never do is decide anything itself — reachable is not proof a
 * quest happened, and unreachable is not proof it did not.
 *
 * That guarantee is structural rather than careful: the policy reads only
 * MANDATORY_CAPABILITIES, so evidence filed under ADDITIONAL cannot satisfy
 * or fail the gate however it is shaped. These tests pin that it stays so.
 */
/**
 * Payloads observed from Nokia's live simulator on 2026-09-11, not invented:
 *
 *   +99999991000 → { reachable: true,  connectivity: ['SMS'],  lastStatusTime }
 *   +99999991001 → { reachable: true,  connectivity: ['DATA'], lastStatusTime }
 *   +3637123456  → { reachable: false,                         lastStatusTime }
 *
 * The unreachable case omits `connectivity` entirely rather than sending an
 * empty array, which is exactly the shape a normaliser written against the
 * happy path would crash on.
 */
const SIMULATOR = {
  smsOnly: { reachable: true, connectivity: ['SMS'], lastStatusTime: '2026-09-11T16:06:49.035681Z' },
  dataConnected: { reachable: true, connectivity: ['DATA'], lastStatusTime: '2026-09-11T16:06:49.294412Z' },
  unreachable: { reachable: false, lastStatusTime: '2026-09-11T16:06:49.472653Z' },
} as const;

const query: LocationEvidenceQuery = {
  runId: '00000000-0000-4000-8000-000000000001',
  userId: '00000000-0000-4000-8000-000000000002',
  phoneNumber: '+99999991000',
  userQuestId: '00000000-0000-4000-8000-000000000003',
  submissionId: '00000000-0000-4000-8000-000000000004',
  place: { placeId: '00000000-0000-4000-8000-000000000005', latitude: 25.42, longitude: 51.49, radiusMeters: 500 },
  windowStart: '2026-09-10T10:00:00.000Z',
  windowEnd: '2026-09-10T11:00:00.000Z',
  geofence: null,
};

function adapterWith(
  reachability?: () => Promise<Record<string, unknown>>,
  options: { configured?: boolean; phoneNumber?: string | null } = {},
) {
  const config = {
    get: vi.fn((key: keyof Environment) =>
      key === 'CAMARA_ENABLED' ? (options.configured ?? true) : undefined),
  } as unknown as ConfigService<Environment, true>;
  const retrieveReachabilityStatus = vi.fn(
    reachability ??
      (async () => ({ reachable: true, connectivity: ['DATA'], lastStatusTime: '2026-09-10T10:45:00.000Z' })),
  );
  const client = { location: {}, deviceStatus: { retrieveReachabilityStatus } };
  const clients = {
    clientOrNull: () => (options.configured === false ? null : client),
  } as unknown as CamaraClientFactory;
  return {
    adapter: new CamaraEvidenceAdapter(config, clients),
    retrieveReachabilityStatus,
    query: { ...query, phoneNumber: options.phoneNumber === undefined ? query.phoneNumber : options.phoneNumber },
  };
}

/** The three mandatory results, all unavailable — the case #73 exists for. */
const mandatoryAllUnavailable: NetworkEvidence[] = [
  { provider: 'nokia-network-as-code', providerReference: 'a', capability: 'LOCATION_VERIFICATION', outcome: 'UNAVAILABLE', observedAt: '2026-09-10T10:45:00.000Z', result: {} },
  { provider: 'nokia-network-as-code', providerReference: 'b', capability: 'LOCATION_RETRIEVAL', outcome: 'UNAVAILABLE', observedAt: '2026-09-10T10:45:00.000Z', result: {} },
  { provider: 'nokia-network-as-code', providerReference: 'c', capability: 'GEOFENCING', outcome: 'UNAVAILABLE', observedAt: '2026-09-10T10:45:00.000Z', result: { events: [] } },
];

describe('device reachability as optional context (#73)', () => {
  it('is the only capability on the allowlist — not roaming, not SIM swap', () => {
    const { adapter } = adapterWith();
    expect(adapter.supportedAdditionalCapabilities).toEqual(['DEVICE_REACHABILITY']);
  });

  it('normalises a data-connected device without leaking the raw payload', async () => {
    const { adapter, query: q } = adapterWith(async () => ({
      ...SIMULATOR.dataConnected,
      connectivity: ['DATA', 'SMS'],
      // The provider echoes the device back; it must not travel onward.
      device: { phoneNumber: '+99999991000' },
    }));
    const evidence = await adapter.getAdditionalEvidence(q, 'DEVICE_REACHABILITY');
    expect(evidence.capability).toBe('ADDITIONAL');
    expect(evidence.outcome).toBe('SUPPORTED');
    const result = evidence.result as Record<string, unknown>;
    expect(result.reachable).toBe(true);
    expect(result.dataConnected).toBe(true);
    expect(result.smsOnly).toBe(false);
    // The device identifier is not echoed back into anything the model reads.
    expect(JSON.stringify(evidence)).not.toContain('+99999991000');
  });

  it('keeps SMS-only distinct from data-connected', async () => {
    const { adapter, query: q } = adapterWith(async () => ({ ...SIMULATOR.smsOnly }));
    const result = (await adapter.getAdditionalEvidence(q, 'DEVICE_REACHABILITY')).result as Record<string, unknown>;
    expect(result.smsOnly).toBe(true);
    expect(result.dataConnected).toBe(false);
  });

  it('reports an unreachable device without calling it CONTRADICTED', async () => {
    // The simulator's real unreachable payload: no `connectivity` key at all.
    const { adapter, query: q } = adapterWith(async () => ({ ...SIMULATOR.unreachable }));
    const evidence = await adapter.getAdditionalEvidence(q, 'DEVICE_REACHABILITY');
    // CONTRADICTED is the shape that argues for rejection. An unreachable
    // handset argues for nothing of the sort — it explains a gap.
    expect(evidence.outcome).toBe('SUPPORTED');
    expect((evidence.result as Record<string, unknown>).reachable).toBe(false);
  });

  it('a provider failure is UNAVAILABLE, never "unreachable"', async () => {
    const { adapter, query: q } = adapterWith(async () => {
      throw new Error('nokia 503');
    });
    const evidence = await adapter.getAdditionalEvidence(q, 'DEVICE_REACHABILITY');
    expect(evidence.outcome).toBe('UNAVAILABLE');
    // Concluding the device was off because the provider was down would be
    // inventing evidence.
    expect((evidence.result as Record<string, unknown>).reachable).toBeUndefined();
  });

  it('is unavailable when CAMARA is unconfigured or the user has no verified number', async () => {
    const unconfigured = adapterWith(undefined, { configured: false });
    expect((await unconfigured.adapter.getAdditionalEvidence(unconfigured.query, 'DEVICE_REACHABILITY')).outcome)
      .toBe('UNAVAILABLE');

    const noPhone = adapterWith(undefined, { phoneNumber: null });
    const evidence = await noPhone.adapter.getAdditionalEvidence(noPhone.query, 'DEVICE_REACHABILITY');
    expect(evidence.outcome).toBe('UNAVAILABLE');
    // Never attempted without a device identifier, rather than guessed at.
    expect(noPhone.retrieveReachabilityStatus).not.toHaveBeenCalled();
  });

  it('refuses a capability that is not on the allowlist, without calling out', async () => {
    const { adapter, query: q, retrieveReachabilityStatus } = adapterWith();
    for (const invented of ['SIM_SWAP', 'DEVICE_ROAMING', 'QOS_ON_DEMAND']) {
      const evidence = await adapter.getAdditionalEvidence(q, invented);
      expect(evidence.outcome, invented).toBe('UNAVAILABLE');
    }
    expect(retrieveReachabilityStatus).not.toHaveBeenCalled();
  });

  it('cannot approve: a reachable device leaves the mandatory gate unsatisfied', async () => {
    const { adapter, query: q } = adapterWith();
    const reachability = await adapter.getAdditionalEvidence(q, 'DEVICE_REACHABILITY');
    const withContext = [...mandatoryAllUnavailable, reachability];
    // Reachable, data-connected, SUPPORTED — and the gate is still not met,
    // because the policy only ever reads the mandatory three.
    expect(mandatoryEvidenceSatisfied(withContext)).toBe(false);
    expect(mandatoryEvidenceStatus(withContext)).toBe('UNAVAILABLE');
  });

  it('cannot reject: an unreachable device leaves a SUPPORTED baseline intact', async () => {
    const { adapter, query: q } = adapterWith(async () => ({ ...SIMULATOR.unreachable }));
    const reachability = await adapter.getAdditionalEvidence(q, 'DEVICE_REACHABILITY');
    const supported: NetworkEvidence[] = [
      { provider: 'n', providerReference: 'a', capability: 'LOCATION_VERIFICATION', outcome: 'SUPPORTED', observedAt: '2026-09-10T10:45:00.000Z', result: {} },
      { provider: 'n', providerReference: 'b', capability: 'LOCATION_RETRIEVAL', outcome: 'SUPPORTED', observedAt: '2026-09-10T10:45:00.000Z', result: {} },
      { provider: 'n', providerReference: 'c', capability: 'GEOFENCING', outcome: 'SUPPORTED', observedAt: '2026-09-10T10:45:00.000Z', result: { events: [] } },
      reachability,
    ];
    expect(mandatoryEvidenceSatisfied(supported)).toBe(true);
    expect(mandatoryEvidenceStatus(supported)).toBe('SUPPORTED');
  });

  it('mandatory evidence stays exactly the three location capabilities', () => {
    // If a later change ever promoted reachability into the baseline, this
    // is where it would be caught — it is optional by definition, and the
    // baseline is what a location quest is actually judged on.
    const { adapter } = adapterWith();
    expect(adapter.supportedAdditionalCapabilities).not.toContain('LOCATION_VERIFICATION');
    expect(mandatoryEvidenceStatus(mandatoryAllUnavailable)).toBe('UNAVAILABLE');
  });
});
