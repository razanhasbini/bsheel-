import { describe, expect, it } from 'vitest';
import { selectCvProvider } from '../src/integrations/computer-vision/computer-vision.module.js';
import {
  toCvEvidence,
  type StoredProofFinding,
} from '../src/integrations/computer-vision/local-cv-evidence.provider.js';
import { validateEnvironment } from '../src/config/environment.js';
import { CvEvidenceSchema } from '../src/modules/agent/domain/agent.schemas.js';
import type { CvEvidenceAnalysisInput, CvEvidenceProvider } from '../src/modules/agent/domain/cv-evidence.port.js';

const ANALYZED_AT = '2026-09-11T09:00:00.000Z';

function input(
  verifiability: CvEvidenceAnalysisInput['task']['verifiability'] = 'content',
): CvEvidenceAnalysisInput {
  return {
    runId: '11111111-1111-4111-8111-111111111111',
    submissionId: '22222222-2222-4222-8222-222222222222',
    media: [],
    requirements: { actions: [], objects: [], landmarks: [] },
    task: {
      title: 'Watch the sunrise',
      description: 'Be up before the sun and watch it come up.',
      category: 'adventure',
      evidenceRubric: 'Expect the place or the moment.',
      verifiability,
    },
    maxKeyFrames: 12,
    idempotencyKey: 'test',
  };
}

function finding(overrides: Partial<NonNullable<StoredProofFinding>> = {}): StoredProofFinding {
  return {
    state: 'complete',
    verdict: 'pass',
    confidence: 0.9,
    relevance: 0.82,
    stage: 'triage',
    model: 'gpt-5.6-luna',
    observations: [
      { kind: 'action', label: 'sunrise over water', present: true, confidence: 0.88 },
      { kind: 'object', label: 'clock or timestamp', present: false, confidence: 0.7 },
    ],
    forensics: null,
    ...overrides,
  };
}

/// Every mapping must satisfy the schema the agent module validates against,
/// so a field added to CvEvidenceSchema cannot silently go unmapped here.
function parsed(evidence: ReturnType<typeof toCvEvidence>) {
  return CvEvidenceSchema.parse(evidence);
}

describe('the vision pass, read as CV evidence', () => {
  it('reports a completed pass as AVAILABLE with its relevance and detections', () => {
    const evidence = parsed(toCvEvidence(finding(), input(), ANALYZED_AT));
    expect(evidence.status).toBe('AVAILABLE');
    expect(evidence.relevance).toBe(0.82);
    expect(evidence.modelVersion).toBe('gpt-5.6-luna');
    expect(evidence.detections).toHaveLength(2);
  });

  // An absence the analysis looked for is a finding, and usually the decisive
  // one — "the quest asked for a sunrise and there is none here" is exactly
  // what a decider needs. A detections list that could only express presence
  // would force that to be dropped.
  it('carries absences through as detections, not silence', () => {
    const evidence = parsed(toCvEvidence(finding(), input(), ANALYZED_AT));
    const absent = evidence.detections.find((detection) => detection.label === 'clock or timestamp');
    expect(absent?.present).toBe(false);
    expect(absent?.confidence).toBe(0.7);
    expect(evidence.detections.find((d) => d.label === 'sunrise over water')?.present).toBe(true);
  });

  it('maps every observation kind onto the detection contract', () => {
    const evidence = parsed(
      toCvEvidence(
        finding({
          observations: [
            { kind: 'action', label: 'a', present: true, confidence: 1 },
            { kind: 'object', label: 'b', present: true, confidence: 1 },
            { kind: 'landmark', label: 'c', present: true, confidence: 1 },
            { kind: 'location_cue', label: 'd', present: true, confidence: 1 },
          ],
        }),
        input(),
        ANALYZED_AT,
      ),
    );
    expect(evidence.detections.map((detection) => detection.type)).toEqual([
      'ACTION',
      'OBJECT',
      'LANDMARK',
      'LOCATION_CUE',
    ]);
  });

  // The trap the whole verification contract exists to prevent. A photograph
  // is irrelevant to "spend an hour with no phone" — the phone took it — and
  // handing a decider a 0.0 on the theory that it will remember to ignore it
  // is how an honest player gets rejected. So the number is withheld, and the
  // warning says out loud why.
  it('withholds relevance for a quest no photograph can show', () => {
    for (const verifiability of ['provenance_only', 'none'] as const) {
      const evidence = parsed(toCvEvidence(finding({ relevance: 0.02 }), input(verifiability), ANALYZED_AT));
      expect(evidence.status, verifiability).toBe('AVAILABLE');
      expect(evidence.relevance, verifiability).toBeUndefined();
      expect(evidence.warnings.join(' '), verifiability).toContain(verifiability);
    }
  });

  // These quests complete without a vision call at all, by design. That is a
  // clean run with a provenance-only conclusion, not a missing one — reporting
  // UNAVAILABLE would send a third of the catalogue to a human for a reason
  // that is not true.
  it('still reports AVAILABLE when no vision model ran for an unverifiable quest', () => {
    const evidence = parsed(
      toCvEvidence(
        finding({ relevance: null, observations: [], model: '', stage: 'forensics' }),
        input('none'),
        ANALYZED_AT,
      ),
    );
    expect(evidence.status).toBe('AVAILABLE');
    expect(evidence.modelVersion).toBe('forensics-only');
  });

  // The back door into the very failure this bridge closes. A vision call
  // that was cut short or refused is recorded as state 'complete' with
  // verdict 'unclear' — correct, the cascade did finish and did escalate —
  // but it learned nothing about the photograph. Reported as AVAILABLE, the
  // agent could approve a content-verifiable quest on no media evidence at
  // all, which is "a file was attached, good enough" reached by another
  // route.
  it('is UNAVAILABLE when a completed pass assessed nothing at all', () => {
    const evidence = parsed(
      toCvEvidence(finding({ observations: [], relevance: null }), input(), ANALYZED_AT),
    );
    expect(evidence.status).toBe('UNAVAILABLE');
    expect(evidence.warnings.join(' ')).toContain('without assessing the submitted media');
  });

  // A score with nothing itemised is still a measurement of the media, so it
  // does not trip the guard above.
  it('stays AVAILABLE when relevance was scored but nothing was itemised', () => {
    const evidence = parsed(
      toCvEvidence(finding({ observations: [], relevance: 0.71 }), input(), ANALYZED_AT),
    );
    expect(evidence.status).toBe('AVAILABLE');
    expect(evidence.relevance).toBe(0.71);
  });

  describe('when there is nothing to read', () => {
    it('is UNAVAILABLE with no row', () => {
      const evidence = parsed(toCvEvidence(null, input(), ANALYZED_AT));
      expect(evidence.status).toBe('UNAVAILABLE');
      expect(evidence.detections).toEqual([]);
      expect(evidence.relevance).toBeUndefined();
    });

    it('is UNAVAILABLE while the pass is still queued', () => {
      expect(parsed(toCvEvidence(finding({ state: 'queued' }), input(), ANALYZED_AT)).status).toBe('UNAVAILABLE');
    });

    it('is UNAVAILABLE when the pass was skipped', () => {
      expect(parsed(toCvEvidence(finding({ state: 'skipped' }), input(), ANALYZED_AT)).status).toBe('UNAVAILABLE');
    });

    // FAILED and UNAVAILABLE both reach a human, but they are different
    // operationally — retryable work versus work nobody asked for — and an
    // outage that looks identical to a disabled feature is an outage nobody
    // notices.
    it('distinguishes a failed pass from one that never ran', () => {
      expect(parsed(toCvEvidence(finding({ state: 'failed' }), input(), ANALYZED_AT)).status).toBe('FAILED');
    });

    // The one thing a fail-closed adapter must never do.
    it('never fabricates relevance or detections on any non-complete state', () => {
      for (const state of ['queued', 'failed', 'skipped'] as const) {
        const evidence = parsed(toCvEvidence(finding({ state }), input(), ANALYZED_AT));
        expect(evidence.relevance, state).toBeUndefined();
        expect(evidence.detections, state).toEqual([]);
        expect(evidence.integrity, state).toBeUndefined();
      }
    });
  });

  /// The integrity block is built from measurements, never from a model's
  /// impression of whether an image "looks manipulated" — that is the question
  /// a vision model answers confidently and badly.
  describe('integrity, from measured forensics', () => {
    const report = (findings: { weight: string; detail: string }[]) => ({
      captureWindow: 'within_window',
      blocksAutomatedApproval: false,
      findings,
    });

    it('calls manipulation likely only on a decisive measurement', () => {
      const evidence = parsed(
        toCvEvidence(
          finding({
            forensics: report([
              { weight: 'decisive', detail: 'Byte-identical to another user’s proof.' },
            ]),
          }),
          input(),
          ANALYZED_AT,
        ),
      );
      expect(evidence.integrity?.manipulationLikely).toBe(true);
      expect(evidence.integrity?.confidence).toBe(0.95);
      expect(evidence.integrity?.notes).toHaveLength(1);
    });

    it('reports a strong doubt without calling it manipulation', () => {
      const evidence = parsed(
        toCvEvidence(
          finding({ forensics: report([{ weight: 'strong', detail: 'Dimensions match a device screen.' }]) }),
          input(),
          ANALYZED_AT,
        ),
      );
      expect(evidence.integrity?.manipulationLikely).toBe(false);
      expect(evidence.integrity?.confidence).toBe(0.6);
    });

    // Reassuring findings are recorded on the row for a moderator to read, but
    // forwarding them here would pad the evidence with notes that cannot
    // change a decision.
    it('omits the block entirely when every finding is informational', () => {
      const evidence = parsed(
        toCvEvidence(
          finding({ forensics: report([{ weight: 'info', detail: 'Capture time is in the window.' }]) }),
          input(),
          ANALYZED_AT,
        ),
      );
      expect(evidence.integrity).toBeUndefined();
    });

    it('survives a forensics blob written by an older build', () => {
      for (const blob of [{}, { findings: 'not an array' }, { findings: [null, { weight: 'strong' }] }]) {
        const evidence = parsed(
          toCvEvidence(finding({ forensics: blob as Record<string, unknown> }), input(), ANALYZED_AT),
        );
        expect(evidence.integrity).toBeUndefined();
      }
    });
  });

  // The provider reports what the media shows. It deliberately does not pass
  // on the verdict the cascade reached: handing the decider a second opinion
  // to defer to is not the same as handing it evidence to reason over, and
  // CvEvidenceProvider forbids a provider from approving or rejecting.
  //
  // Asserted as independence rather than by grepping the output for 'fail'
  // and '0.99'. A substring search is both too weak — a mutation that piped
  // the verdict into an integrity note under another name would pass it — and
  // too strong, since 'fail' is a substring of the legitimate word 'failed'.
  // Mapping the same media findings twice with opposite verdicts and
  // requiring the results to be identical is the actual property.
  it('produces identical evidence whatever verdict the cascade reached', () => {
    const media = {
      observations: [{ kind: 'action' as const, label: 'a sunrise', present: true, confidence: 0.8 }],
      relevance: 0.8,
      forensics: {
        captureWindow: 'within_window',
        blocksAutomatedApproval: false,
        findings: [{ weight: 'strong', detail: 'Dimensions match a device screen.' }],
      },
    };
    const cleared = parsed(
      toCvEvidence(finding({ ...media, verdict: 'pass', confidence: 0.1 }), input(), ANALYZED_AT),
    );
    const accused = parsed(
      toCvEvidence(finding({ ...media, verdict: 'fail', confidence: 0.99 }), input(), ANALYZED_AT),
    );
    expect(accused).toEqual(cleared);
    // And the integrity block really was populated, so the equality above is
    // over evidence that exists rather than over two empty objects.
    expect(cleared.integrity?.notes).toHaveLength(1);
  });
});

function unavailableFor(provider: string) {
  return {
    status: 'UNAVAILABLE' as const,
    provider,
    modelVersion: 'none',
    analyzedAt: ANALYZED_AT,
    detections: [],
    keyFrames: [],
    warnings: [],
  };
}

/// Which provider a deployment gets, asserted rather than assumed.
///
/// This was the whole bug: `CV_PROVIDER` shipped defaulting to 'none', so
/// every deployment ran the fail-closed adapter and every submission went to
/// a human. Nothing was broken enough to notice — no error, no failed job,
/// just an agent that could not see.
describe('CV provider selection', () => {
  // Distinguishable only by identity, which is all the selector decides.
  const fake = (name: string): CvEvidenceProvider => ({
    analyze: async () => unavailableFor(name),
  });
  const providers = { none: fake('none'), http: fake('http'), local: fake('local') };

  it('picks each provider by name', () => {
    expect(selectCvProvider('none', providers)).toBe(providers.none);
    expect(selectCvProvider('http', providers)).toBe(providers.http);
    expect(selectCvProvider('local', providers)).toBe(providers.local);
  });

  it('falls back to the fail-closed provider for anything unrecognised', () => {
    expect(selectCvProvider('mystery' as never, providers)).toBe(providers.none);
  });

  // The default is the reason this PR exists. If it ever goes back to 'none',
  // the agent is blind again on every deployment that has not opted in.
  it('defaults to the in-process provider', () => {
    expect(validateEnvironment({ NODE_ENV: 'test' }).CV_PROVIDER).toBe('local');
  });
});
