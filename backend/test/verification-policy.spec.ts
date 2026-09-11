import { describe, expect, it } from 'vitest';
import type { NetworkEvidence, VerificationDecision } from '../src/modules/agent/domain/agent.schemas.js';
import {
  finalizeDecision,
  mandatoryEvidenceStatus,
  resolvePolicyBounds,
  type FinalizeDecisionInput,
  type VerificationContract,
} from '../src/modules/agent/domain/verification-policy.js';

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

/// A quest whose photograph can show the task and whose contract grants the
/// agent both authorities. Every test that is not *about* the contract starts
/// here, so a gate firing is never an accident of the fixture.
const permissive: VerificationContract = {
  verifiability: 'content',
  mayAutoApprove: true,
  mayAutoReject: true,
};

const finalize = (overrides: Partial<FinalizeDecisionInput> = {}): VerificationDecision =>
  finalizeDecision({
    modelDecision: decision('APPROVED'),
    isLocationBased: false,
    mandatoryStatus: 'SUPPORTED',
    cvAvailable: true,
    cvRelevance: 0.9,
    cvBlocksApproval: false,
    contract: permissive,
    minRelevance: 0.35,
    bounds,
    ...overrides,
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
    expect(finalize().decision).toBe('APPROVED');
  });

  it('requires all location capabilities for approval', () => {
    const status = mandatoryEvidenceStatus([
      evidence('LOCATION_VERIFICATION', 'SUPPORTED'),
      evidence('LOCATION_RETRIEVAL', 'SUPPORTED'),
    ]);
    expect(status).toBe('UNAVAILABLE');
    expect(finalize({ isLocationBased: true, mandatoryStatus: status }).decision).toBe('HUMAN_REVIEW');
  });

  it('never turns provider unavailability into rejection', () => {
    expect(
      finalize({ modelDecision: decision('REJECTED'), isLocationBased: true, mandatoryStatus: 'UNAVAILABLE' }).decision,
    ).toBe('HUMAN_REVIEW');
  });

  it('allows confident rejection when mandatory evidence is available but contradicted', () => {
    expect(
      finalize({ modelDecision: decision('REJECTED'), isLocationBased: true, mandatoryStatus: 'CONTRADICTED' }).decision,
    ).toBe('REJECTED');
  });

  it('routes missing CV, conflicting evidence and low confidence to human review', () => {
    expect(finalize({ cvAvailable: false }).decision).toBe('HUMAN_REVIEW');
    expect(
      finalize({
        modelDecision: { ...decision('REJECTED'), conflicts: ['Network and media disagree'] },
        isLocationBased: true,
        mandatoryStatus: 'CONTRADICTED',
      }).decision,
    ).toBe('HUMAN_REVIEW');
    expect(finalize({ modelDecision: decision('APPROVED', 0.4) }).decision).toBe('HUMAN_REVIEW');
  });
});

/// The quest's contract (#47, migration 0034) gates the agent's authority.
///
/// `may_auto_reject` is seeded false for every category deliberately: the
/// right to tell a player their proof is fake is earned from a measured
/// precision number, not granted by enabling a feature. Before these gates
/// existed the agent path ignored the contract entirely, which made that
/// seeding decorative — enabling the agent granted it authority over every
/// quest in the catalogue at once.
describe('the quest contract gates the agent, not just the vision cascade', () => {
  it('refuses to reject a quest whose contract does not permit it', () => {
    const result = finalize({
      modelDecision: decision('REJECTED'),
      contract: { ...permissive, mayAutoReject: false },
    });
    expect(result.decision).toBe('HUMAN_REVIEW');
    expect(result.humanReviewReason).toContain('does not permit automated rejection');
  });

  it('refuses to approve a quest whose contract does not permit it', () => {
    const result = finalize({ contract: { ...permissive, mayAutoApprove: false } });
    expect(result.decision).toBe('HUMAN_REVIEW');
    expect(result.humanReviewReason).toContain('does not permit automated approval');
  });

  // The contract is checked before evidence, so a quest with no authority
  // escalates on the contract's own terms rather than reporting a missing
  // signal as the reason. A moderator reading the queue should see why they
  // were asked, and "this quest is never decided automatically" is a
  // different answer from "the provider was down".
  it('names the contract as the reason, not whatever evidence was also missing', () => {
    const result = finalize({
      modelDecision: decision('REJECTED'),
      contract: { ...permissive, mayAutoReject: false },
      cvAvailable: false,
      isLocationBased: true,
      mandatoryStatus: 'UNAVAILABLE',
    });
    expect(result.humanReviewReason).toContain('does not permit automated rejection');
  });

  it('leaves a HUMAN_REVIEW recommendation alone whatever the contract says', () => {
    const result = finalize({
      modelDecision: decision('HUMAN_REVIEW'),
      contract: { verifiability: 'none', mayAutoApprove: false, mayAutoReject: false },
    });
    expect(result.decision).toBe('HUMAN_REVIEW');
  });
});

/// Measured provenance keeps its veto over an approval.
///
/// proof-policy.ts treats a decisive forensic finding as absolute and a
/// strong one as a veto on a model's 'pass'. That cascade stops acting once
/// the agent pipeline is the decider, so the veto has to exist here too or it
/// stops existing at all — and every content category is seeded
/// may_auto_approve = true.
describe('provenance veto', () => {
  it('sends an approval of doubtful provenance to a human', () => {
    const result = finalize({ cvBlocksApproval: true });
    expect(result.decision).toBe('HUMAN_REVIEW');
    expect(result.humanReviewReason).toContain('provenance');
  });

  // The whole point: a photograph lifted from the feed genuinely shows the
  // sunrise. The model is right about the content and still must not approve.
  it('overrides a confident, relevant, content-verifiable approval', () => {
    const result = finalize({
      modelDecision: decision('APPROVED', 1),
      cvRelevance: 1,
      cvBlocksApproval: true,
    });
    expect(result.decision).toBe('HUMAN_REVIEW');
  });

  // Authenticity is the entire question for these, so skipping the check
  // exactly there would be perverse.
  it('applies on quests a photograph cannot show, where authenticity is the only question', () => {
    for (const verifiability of ['provenance_only', 'none'] as const) {
      const result = finalize({
        cvBlocksApproval: true,
        cvRelevance: null,
        contract: { ...permissive, verifiability },
      });
      expect(result.decision, verifiability).toBe('HUMAN_REVIEW');
    }
  });

  // A measurement that something is wrong with the file is grounds to ask a
  // human, not to accuse the player — the same asymmetry as unavailable
  // location evidence.
  it('never turns doubtful provenance into a rejection', () => {
    const result = finalize({
      modelDecision: decision('REJECTED'),
      isLocationBased: true,
      mandatoryStatus: 'CONTRADICTED',
      cvBlocksApproval: true,
    });
    expect(result.decision).toBe('REJECTED');
  });

  it('lets a clean file through', () => {
    expect(finalize({ cvBlocksApproval: false }).decision).toBe('APPROVED');
  });
});

/// Media relevance: the signal that makes this more than a check that a file
/// was attached, and the one most likely to be misused.
describe('media relevance', () => {
  it('sends an approval of barely-related media to a human', () => {
    const result = finalize({ cvRelevance: 0.05 });
    expect(result.decision).toBe('HUMAN_REVIEW');
    expect(result.humanReviewReason).toContain('0.05');
    expect(result.humanReviewReason).toContain('relevance');
  });

  it('approves when the media is relevant', () => {
    expect(finalize({ cvRelevance: 0.36 }).decision).toBe('APPROVED');
  });

  it('treats relevance exactly at the floor as sufficient', () => {
    expect(finalize({ cvRelevance: 0.35 }).decision).toBe('APPROVED');
  });

  // The trap this whole design exists to avoid. "Spend an hour with no phone"
  // has no relevant photograph — the phone took it — so a relevance floor
  // applied there would reject precisely the honest players it is meant to
  // protect. Roughly a third of the catalogue is like that.
  it('ignores relevance entirely for a quest no photograph can show', () => {
    for (const verifiability of ['provenance_only', 'none'] as const) {
      const result = finalize({
        cvRelevance: 0.0,
        contract: { ...permissive, verifiability },
      });
      expect(result.decision, verifiability).toBe('APPROVED');
    }
  });

  // Not assessed is not the same as assessed-and-irrelevant, and the
  // difference must not cost anyone an approval.
  it('ignores an unassessed relevance', () => {
    expect(finalize({ cvRelevance: null }).decision).toBe('APPROVED');
  });

  // Low relevance says "this photo has little to do with the quest". It does
  // not say "this player cheated", and only the first claim is supported by
  // the number. So the gate is one-directional: it can stop an approval and
  // can never produce or strengthen a rejection.
  it('never converts low relevance into a rejection', () => {
    const result = finalize({
      modelDecision: decision('REJECTED'),
      isLocationBased: true,
      mandatoryStatus: 'CONTRADICTED',
      cvRelevance: 0.01,
    });
    expect(result.decision).toBe('REJECTED');
    expect(result.humanReviewReason).toBeUndefined();
  });
});

/// What the agent is now expected to decide on its own.
///
/// The gates below used to send these to a human, and the cost of that was
/// not theoretical: a submission the agent was 99% sure was a desktop
/// screenshot, 1% relevant to the quest, sat in a moderator queue carrying
/// the agent's own correct conclusion for a person to reach again by hand.
/// Escalation is now for evidence that genuinely cannot settle the question,
/// not for every question whose answer is unwelcome.
describe('the agent decides what the evidence can settle', () => {
  // The one case where no vision pass is needed to reject: the geofence was
  // live for the whole quest window and the device never entered it. That is
  // a measurement about where the device was, reached without looking at any
  // photograph, so a missing look at the photograph cannot undermine it.
  it('rejects on a contradicted geofence even with no vision pass', () => {
    const result = finalize({
      modelDecision: decision('REJECTED'),
      isLocationBased: true,
      mandatoryStatus: 'CONTRADICTED',
      cvAvailable: false,
      cvRelevance: null,
    });
    expect(result.decision).toBe('REJECTED');
  });

  // The carve-out is exactly that narrow. Without network evidence saying so,
  // a rejection with nobody having looked at the media is still a human's.
  it('keeps the carve-out narrow: no CV and no contradiction is still human review', () => {
    expect(
      finalize({
        modelDecision: decision('REJECTED'),
        isLocationBased: false,
        cvAvailable: false,
        cvRelevance: null,
      }).decision,
    ).toBe('HUMAN_REVIEW');
    // An approval never rides on it either — the carve-out is a measurement
    // that someone was absent, which is not evidence that anyone succeeded.
    expect(
      finalize({ isLocationBased: true, mandatoryStatus: 'CONTRADICTED', cvAvailable: false }).decision,
    ).toBe('HUMAN_REVIEW');
  });

  // A rejection on a content quest is a claim about what the media shows, so
  // it has to rest on the media having been assessed. This is the backstop
  // under the model's instruction to escalate an unassessable image: a
  // confident-sounding rejection can never rest on its unassisted impression.
  it('will not reject a content quest on an unassessed image', () => {
    const result = finalize({ modelDecision: decision('REJECTED'), cvRelevance: null });
    expect(result.decision).toBe('HUMAN_REVIEW');
    expect(result.humanReviewReason).toContain('unassessed image');
  });

  // The submission that started this. Content quest, vision pass ran, the
  // media has essentially nothing to do with the quest, and the agent is
  // sure. Nothing here needs a person.
  it('rejects the screenshot case end to end', () => {
    const result = finalize({
      modelDecision: {
        ...decision('REJECTED', 0.99),
        reasons: ['This is a screenshot of the Bsheel app, not a photograph of a sea gate.'],
      },
      cvRelevance: 0.01,
    });
    expect(result.decision).toBe('REJECTED');
    expect(result.reasons[0]).toContain('screenshot');
  });

  // Rejection authority follows verifiability, because that is the column
  // that says whether the media can answer the question at all. Where it
  // cannot, a low-relevance image is what honest proof looks like.
  it('still refuses to reject where a photograph cannot settle the quest', () => {
    for (const verifiability of ['provenance_only', 'none'] as const) {
      const result = finalize({
        modelDecision: decision('REJECTED'),
        cvRelevance: 0.01,
        contract: { verifiability, mayAutoApprove: true, mayAutoReject: false },
      });
      expect(result.decision, verifiability).toBe('HUMAN_REVIEW');
    }
  });
});
