import type { ConfigService } from '@nestjs/config';
import { describe, expect, it, vi } from 'vitest';
import type { Environment } from '../src/config/environment.js';
import { CamaraEvidenceAdapter } from '../src/integrations/camara/camara-evidence.adapter.js';
import { CamaraGeofencingAdapter } from '../src/integrations/camara/camara-geofencing.adapter.js';
import type { CamaraClientFactory } from '../src/integrations/camara/camara-client.factory.js';
import type { LocationEvidenceQuery } from '../src/modules/agent/domain/network-evidence.port.js';

const query: LocationEvidenceQuery = {
  runId: '00000000-0000-4000-8000-000000000001',
  userId: '00000000-0000-4000-8000-000000000002',
  phoneNumber: '+99999991000',
  userQuestId: '00000000-0000-4000-8000-000000000003',
  submissionId: '00000000-0000-4000-8000-000000000004',
  place: {
    placeId: '00000000-0000-4000-8000-000000000005',
    latitude: 33.8938,
    longitude: 35.5018,
    radiusMeters: 500,
  },
  windowStart: '2026-09-10T10:00:00.000Z',
  windowEnd: '2026-09-10T11:00:00.000Z',
  geofence: { status: 'active', events: [{ type: 'ENTER', occurredAt: '2026-09-10T10:30:00.000Z' }] },
};

function evidenceAdapter(input: {
  verify?: () => Promise<Record<string, unknown>>;
  retrieve?: () => Promise<Record<string, unknown>>;
  configured?: boolean;
}) {
  const config = {
    get: vi.fn((key: keyof Environment) => key === 'CAMARA_ENABLED' ? (input.configured ?? true) : undefined),
  } as unknown as ConfigService<Environment, true>;
  const client = {
    location: {
      verify: vi.fn(input.verify ?? (async () => ({ verificationResult: 'TRUE', lastLocationTime: '2026-09-10T10:30:00.000Z' }))),
      retrieve: vi.fn(input.retrieve ?? (async () => ({
        area: { areaType: 'CIRCLE', center: { latitude: 33.8938, longitude: 35.5018 }, radius: 120 },
        lastLocationTime: '2026-09-10T10:31:00.000Z',
      }))),
    },
  };
  const clients = { clientOrNull: () => client } as unknown as CamaraClientFactory;
  return { adapter: new CamaraEvidenceAdapter(config, clients), client };
}

describe('CAMARA location evidence mapping', () => {
  it.each([
    ['TRUE', undefined, 'SUPPORTED'],
    ['PARTIAL', 90, 'SUPPORTED'],
    ['PARTIAL', 50, 'CONTRADICTED'],
    ['FALSE', undefined, 'CONTRADICTED'],
    ['UNKNOWN', undefined, 'UNAVAILABLE'],
  ] as const)('preserves Location Verification %s', async (verificationResult, matchRate, outcome) => {
    const { adapter } = evidenceAdapter({
      verify: async () => ({ verificationResult, matchRate, lastLocationTime: '2026-09-10T10:30:00.000Z' }),
    });
    const evidence = (await adapter.getBaselineEvidence(query))[0];
    expect(evidence.outcome).toBe(outcome);
    expect(evidence.capability).toBe('LOCATION_VERIFICATION');
    if (evidence.capability === 'LOCATION_VERIFICATION') {
      expect(evidence.result.verificationResult).toBe(verificationResult);
      expect(evidence.result.matchRate).toBe(matchRate);
    }
  });

  it('preserves retrieved coordinates, radius and timestamp', async () => {
    const { adapter } = evidenceAdapter({});
    const evidence = (await adapter.getBaselineEvidence(query))[1];
    expect(evidence.capability).toBe('LOCATION_RETRIEVAL');
    if (evidence.capability === 'LOCATION_RETRIEVAL') {
      expect(evidence.outcome).toBe('SUPPORTED');
      expect(evidence.result.coordinates?.accuracyMeters).toBe(120);
      expect(evidence.result.radiusMeters).toBe(120);
      expect(evidence.result.lastLocationTime).toBe('2026-09-10T10:31:00.000Z');
    }
  });

  it('maps malformed and failed retrievals to UNAVAILABLE', async () => {
    const malformed = evidenceAdapter({ retrieve: async () => ({ area: { areaType: 'POLYGON' }, lastLocationTime: '2026-09-10T10:31:00.000Z' }) });
    expect((await malformed.adapter.getBaselineEvidence(query))[1].outcome).toBe('UNAVAILABLE');
    const failed = evidenceAdapter({ retrieve: async () => { throw Object.assign(new Error('secret body'), { statusCode: 503 }); } });
    expect((await failed.adapter.getBaselineEvidence(query))[1].outcome).toBe('UNAVAILABLE');
  });

  it('distinguishes an active geofence with no entry from unavailable setup', async () => {
    const { adapter } = evidenceAdapter({});
    const noEntry = await adapter.getBaselineEvidence({ ...query, geofence: { status: 'active', events: [] } });
    expect(noEntry[2].outcome).toBe('CONTRADICTED');
    const failed = await adapter.getBaselineEvidence({ ...query, geofence: { status: 'failed', events: [] } });
    expect(failed[2].outcome).toBe('UNAVAILABLE');
  });
});

describe('CAMARA geofencing subscriptions', () => {
  it('creates separate authenticated enter and exit subscriptions', async () => {
    const createSubscription = vi.fn()
      .mockResolvedValueOnce({ id: 'enter-id' })
      .mockResolvedValueOnce({ id: 'exit-id' });
    const config = { get: vi.fn(() => true) } as unknown as ConfigService<Environment, true>;
    const clients = { clientOrNull: () => ({ geofencing: { createSubscription, deleteSubscription: vi.fn() } }) } as unknown as CamaraClientFactory;
    const adapter = new CamaraGeofencingAdapter(config, clients);
    await expect(adapter.createSubscription({
      phoneNumber: '+99999991000',
      place: query.place,
      sink: 'https://api.bsheel.app/api/v1/integrations/camara/geofencing/local-id',
      sinkBearerToken: 'callback-secret',
      expiresAt: new Date('2026-09-11T10:00:00.000Z'),
    })).resolves.toEqual({ ok: true, providerSubscriptionIds: ['enter-id', 'exit-id'] });
    expect(createSubscription).toHaveBeenCalledTimes(2);
    expect(createSubscription.mock.calls[0][0].types[0]).toContain('area-entered');
    expect(createSubscription.mock.calls[1][0].types[0]).toContain('area-left');
    expect(createSubscription.mock.calls[0][0].sink).not.toContain('callback-secret');
    expect(createSubscription.mock.calls[0][0].sinkCredential.accessToken).toBe('callback-secret');
  });
});
