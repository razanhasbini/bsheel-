import { describe, expect, it } from 'vitest';
import type { NetworkEvidence, VerificationDecision } from '../src/modules/agent/domain/agent.schemas.js';
import { finalizeDecision, mandatoryEvidenceStatus, resolvePolicyBounds } from '../src/modules/agent/domain/verification-policy.js';

const bounds = resolvePolicyBounds(
  { baseXp: 20, defaultDurationHours: 24 },
  { globalMinDurationMinutes: 240, globalMaxDurationMinutes: 20160, globalMinXp: 5, globalMaxXp: 100, approveThreshold: 0.85, rejectThreshold: 0.85 },
);
const decision = (value: VerificationDecision['decision'], confidence = 0.95): VerificationDecision => ({
  decision: value,
  confidence,
  reasons: ['Evidence assessment completed.'],
  evidenceAssessment: { cv: 'SUPPORTS', locationVerification: 'SUPPORTS', locationRetrieval: 'SUPPORTS', geofencing: 'SUPPORTS', timing: 'SUPPORTS' },
  additionalCapabilitiesUsed: [],
  conflicts: [],
  ...(value === 'HUMAN_REVIEW' ? { humanReviewReason: 'Needs review.' } : {}),
});
const evidence = (capability: NetworkEvidence['capability'], outcome: NetworkEvidence['outcome']): NetworkEvidence => {
  const base = { provider: 'test', providerReference: `${capability}:${outcome}`, outcome, observedAt: '2026-09-10T10:00:00.000Z' };
  if (capability === 'LOCATION_VERIFICATION') return { ...base, capability, result: {} };
  if (capability === 'LOCATION_RETRIEVAL') return { ...base, capability, result: {} };
  if (capability === 'GEOFENCING') return { ...base, capability, result: { events: [] } };
  return { ...base, capability, apiName: 'test', result: {} };
};

describe('submission verification policy', () => {
  it('does not require CAMARA evidence for non-location quests', () => {
    expect(finalizeDecision(decision('APPROVED'), false, 'SUPPORTED', true, bounds).decision).toBe('APPROVED');
  });

  it('requires all location capabilities for approval', () => {
    const status = mandatoryEvidenceStatus([
      evidence('LOCATION_VERIFICATION', 'SUPPORTED'),
      evidence('LOCATION_RETRIEVAL', 'SUPPORTED'),
    ]);
    expect(status).toBe('UNAVAILABLE');
    expect(finalizeDecision(decision('APPROVED'), true, status, true, bounds).decision).toBe('HUMAN_REVIEW');
  });

  it('never turns provider unavailability into rejection', () => {
    expect(finalizeDecision(decision('REJECTED'), true, 'UNAVAILABLE', true, bounds).decision).toBe('HUMAN_REVIEW');
  });

  it('allows confident rejection when mandatory evidence is available but contradicted', () => {
    expect(finalizeDecision(decision('REJECTED'), true, 'CONTRADICTED', true, bounds).decision).toBe('REJECTED');
  });

  it('routes missing CV, conflicting evidence and low confidence to human review', () => {
    expect(finalizeDecision(decision('APPROVED'), false, 'SUPPORTED', false, bounds).decision).toBe('HUMAN_REVIEW');
    expect(finalizeDecision({ ...decision('REJECTED'), conflicts: ['Network and media disagree'] }, true, 'CONTRADICTED', true, bounds).decision).toBe('HUMAN_REVIEW');
    expect(finalizeDecision(decision('APPROVED', 0.4), false, 'SUPPORTED', true, bounds).decision).toBe('HUMAN_REVIEW');
  });
});
