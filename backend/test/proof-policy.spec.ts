import { describe, expect, it } from 'vitest';
import type { ForensicFinding, ForensicsReport } from '../src/modules/submissions/domain/proof-forensics.js';
import { decide, nextTier, type PolicyInput } from '../src/modules/submissions/domain/proof-policy.js';
import type { ProofAnalysis, ProofTier, ProofVerdict } from '../src/modules/submissions/domain/proof-verification.types.js';

function forensics(findings: ForensicFinding[] = []): ForensicsReport {
  return {
    captureWindow: 'within_window',
    findings,
    blocksAutomatedApproval: findings.some((finding) => finding.weight === 'decisive'),
  };
}

const clean = forensics([
  { code: 'capture_within_window', weight: 'info', detail: 'Capture time is in the window.' },
]);
const decisive = forensics([
  { code: 'capture_predates_assignment', weight: 'decisive', detail: 'Captured before the quest was assigned.' },
]);
const strongDoubt = forensics([
  { code: 'screen_dimensions', weight: 'strong', detail: 'Dimensions match a device screen.' },
]);

function analysis(
  verdict: ProofVerdict,
  confidence: number | null,
  tier: ProofTier = 'reject_review',
): ProofAnalysis {
  return {
    tier,
    verdict,
    confidence,
    rationale: 'Rationale.',
    escalationReason: verdict === 'unclear' ? 'Could not tell.' : '',
    model: 'gpt-5.6-sol',
    inputTokens: 10,
    outputTokens: 5,
  };
}

function input(overrides: Partial<PolicyInput> = {}): PolicyInput {
  return {
    verifiability: 'content',
    mayAutoApprove: true,
    mayAutoReject: true,
    forensics: clean,
    approveMinConfidence: 0.85,
    rejectMinConfidence: 0.95,
    ...overrides,
  };
}

describe('decide — deterministic provenance', () => {
  // The safest possible automated rejection, because it is a measurement
  // rather than an opinion, and it costs nothing.
  it('rejects on a decisive forensic finding without needing any model', () => {
    const outcome = decide(input({ forensics: decisive, analysis: undefined }));
    expect(outcome.decision).toBe('reject');
    expect(outcome.stage).toBe('forensics');
    expect(outcome.reason).toContain('before the quest was assigned');
  });

  it('escalates a decisive finding when the quest forbids automated rejection', () => {
    const outcome = decide(input({ forensics: decisive, mayAutoReject: false }));
    expect(outcome.decision).toBe('escalate');
    expect(outcome.reason).toContain('does not permit automated rejection');
  });

  // Provenance outranks content: a convincing picture does not make a
  // recycled file into proof of this attempt.
  it('lets provenance override even a confident pass', () => {
    const outcome = decide(input({ forensics: decisive, analysis: analysis('pass', 1) }));
    expect(outcome.decision).toBe('reject');
    expect(outcome.stage).toBe('forensics');
  });
});

describe('decide — quests a photograph cannot verify', () => {
  // "Compliment a stranger and mean it". Demanding photographic proof of an
  // unprovable task punishes honest players, so the default is trust.
  it("approves a 'none' quest on clean provenance without consulting content", () => {
    const outcome = decide(input({ verifiability: 'none', analysis: undefined }));
    expect(outcome.decision).toBe('approve');
    expect(outcome.stage).toBe('forensics');
    expect(outcome.reason).toContain('Nothing about a photograph can establish this quest');
  });

  // A screenshot is odd but not disqualifying for a task no photo can show.
  it("approves a 'none' quest despite a merely strong doubt", () => {
    const outcome = decide(input({ verifiability: 'none', forensics: strongDoubt }));
    expect(outcome.decision).toBe('approve');
  });

  it("still rejects a 'none' quest on a decisive provenance failure", () => {
    const outcome = decide(input({ verifiability: 'none', forensics: decisive }));
    expect(outcome.decision).toBe('reject');
  });

  // "Read 20 pages of something difficult". Authenticity is meaningful here
  // even though the reading is invisible, so a strong doubt gets a human.
  it("escalates a 'provenance_only' quest when provenance is doubtful", () => {
    const outcome = decide(input({ verifiability: 'provenance_only', forensics: strongDoubt }));
    expect(outcome.decision).toBe('escalate');
  });

  it("approves a 'provenance_only' quest when the file is clean", () => {
    const outcome = decide(input({ verifiability: 'provenance_only' }));
    expect(outcome.decision).toBe('approve');
    expect(outcome.reason).toContain('not visible in a photograph');
  });

  // The whole point of the contract: content must never decide these, so a
  // model's opinion is not even consulted.
  it('ignores a content verdict entirely on an unverifiable quest', () => {
    const outcome = decide(input({ verifiability: 'none', analysis: analysis('fail', 1) }));
    expect(outcome.decision).toBe('approve');
  });
});

describe('decide — content-verifiable quests', () => {
  it('approves a confident pass', () => {
    const outcome = decide(input({ analysis: analysis('pass', 0.9, 'triage') }));
    expect(outcome.decision).toBe('approve');
    expect(outcome.stage).toBe('triage');
  });

  it('escalates a pass below the approve bar', () => {
    const outcome = decide(input({ analysis: analysis('pass', 0.5) }));
    expect(outcome.decision).toBe('escalate');
    expect(outcome.reason).toContain('below the bar required to approve');
  });

  it('escalates a pass when the file provenance is doubtful', () => {
    const outcome = decide(input({ analysis: analysis('pass', 0.99), forensics: strongDoubt }));
    expect(outcome.decision).toBe('escalate');
    expect(outcome.reason).toContain("provenance is doubtful");
  });

  it('escalates a pass when the quest forbids automated approval', () => {
    const outcome = decide(input({ analysis: analysis('pass', 0.99), mayAutoApprove: false }));
    expect(outcome.decision).toBe('escalate');
  });

  // THE load-bearing guard on the reject path. A cheap model's "fail" is a
  // reason to look harder, never authority to accuse a player of cheating.
  it('refuses to reject on a cheap tier verdict, however confident', () => {
    for (const tier of ['triage', 'deep'] as const) {
      const outcome = decide(input({ analysis: analysis('fail', 1, tier) }));
      expect(outcome.decision).toBe('escalate');
      expect(outcome.reason).toContain('not sufficient authority to reject');
    }
  });

  it('rejects on a confident top-tier fail', () => {
    const outcome = decide(input({ analysis: analysis('fail', 0.97) }));
    expect(outcome.decision).toBe('reject');
    expect(outcome.stage).toBe('reject_review');
  });

  // The reject bar is deliberately higher than the approve bar: the errors
  // are not equally costly.
  it('escalates a top-tier fail that clears the approve bar but not the reject bar', () => {
    const outcome = decide(input({ analysis: analysis('fail', 0.9) }));
    expect(outcome.decision).toBe('escalate');
    expect(outcome.reason).toContain('below the bar required to reject');
  });

  it('escalates a fail when the quest forbids automated rejection', () => {
    const outcome = decide(input({ analysis: analysis('fail', 0.99), mayAutoReject: false }));
    expect(outcome.decision).toBe('escalate');
    expect(outcome.reason).toContain('does not permit automated rejection');
  });

  it('escalates an unclear verdict with the analyzer’s own reason', () => {
    const outcome = decide(input({ analysis: analysis('unclear', 0.2) }));
    expect(outcome.decision).toBe('escalate');
    expect(outcome.reason).toBe('Could not tell.');
  });

  // A content quest with no analysis means the vision call never happened —
  // an unreadable file, or video. Never a silent approval.
  it('escalates a content quest when no analysis was produced', () => {
    const outcome = decide(input({ analysis: undefined }));
    expect(outcome.decision).toBe('escalate');
    expect(outcome.reason).toContain('requires one');
  });

  it('never rejects on a null confidence', () => {
    const outcome = decide(input({ analysis: analysis('fail', null) }));
    expect(outcome.decision).toBe('escalate');
  });
});

describe('nextTier — the cascade', () => {
  it('starts at the cheapest rung', () => {
    expect(nextTier(null, 0.85)).toBe('triage');
  });

  // The cheap rung earning its keep: a clear pass ends the cascade, so most
  // submissions never touch an expensive model.
  it('stops after a confident cheap pass', () => {
    expect(nextTier('triage', 0.85, analysis('pass', 0.95, 'triage'))).toBeNull();
  });

  // An unconfident cheap pass is not a reason to spend a moderator's
  // attention — a better model is cheaper than a human review.
  it('promotes an unconfident cheap pass to the deep rung', () => {
    expect(nextTier('triage', 0.85, analysis('pass', 0.5, 'triage'))).toBe('deep');
  });

  // Straight to the top: a cheap 'fail' cannot be acted on, and the middle
  // rung cannot act on it either, so paying for it would buy nothing.
  it('sends a cheap fail directly to the reject-review rung', () => {
    expect(nextTier('triage', 0.85, analysis('fail', 0.9, 'triage'))).toBe('reject_review');
  });

  it('promotes an unclear cheap verdict to the deep rung', () => {
    expect(nextTier('triage', 0.85, analysis('unclear', null, 'triage'))).toBe('deep');
  });

  it('escalates a deep fail to reject review, and stops otherwise', () => {
    expect(nextTier('deep', 0.85, analysis('fail', 0.9, 'deep'))).toBe('reject_review');
    expect(nextTier('deep', 0.85, analysis('pass', 0.9, 'deep'))).toBeNull();
    expect(nextTier('deep', 0.85, analysis('unclear', null, 'deep'))).toBeNull();
  });

  it('never continues past the top rung', () => {
    for (const verdict of ['pass', 'fail', 'unclear'] as const) {
      expect(nextTier('reject_review', 0.85, analysis(verdict, 0.9))).toBeNull();
    }
  });
});
