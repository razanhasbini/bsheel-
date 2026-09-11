import { describe, expect, it } from 'vitest';
import { parseVerdictPayload, type VerdictPayload } from '../src/modules/submissions/domain/proof-prompt.js';
import {
  applyConfidenceFloor,
  isSupportedImageType,
  type ProofAnalysis,
} from '../src/modules/submissions/domain/proof-verification.types.js';

function analysis(overrides: Partial<ProofAnalysis> = {}): ProofAnalysis {
  return {
    tier: 'deep',
    verdict: 'pass',
    confidence: 0.9,
    relevance: 0.9,
    observations: [],
    rationale: 'The photo shows the described activity.',
    escalationReason: '',
    model: 'claude-opus-5',
    inputTokens: 100,
    outputTokens: 20,
    ...overrides,
  };
}

describe('applyConfidenceFloor', () => {
  it('keeps a confident pass', () => {
    const result = applyConfidenceFloor(analysis({ verdict: 'pass', confidence: 0.9 }), 0.75);
    expect(result.verdict).toBe('pass');
    expect(result.escalationReason).toBe('');
  });

  it('keeps a confident fail', () => {
    const result = applyConfidenceFloor(analysis({ verdict: 'fail', confidence: 0.88 }), 0.75);
    expect(result.verdict).toBe('fail');
  });

  // The floor is the whole safety margin of an advisory verdict: an
  // unconfident decision is exactly the case #47 wants a human to take.
  it('downgrades an unconfident pass to unclear and says why', () => {
    const result = applyConfidenceFloor(analysis({ verdict: 'pass', confidence: 0.4 }), 0.75);
    expect(result.verdict).toBe('unclear');
    expect(result.escalationReason).toContain("Downgraded from 'pass'");
    expect(result.escalationReason).toContain('0.40');
    expect(result.escalationReason).toContain('0.75');
  });

  it('downgrades an unconfident fail, so a weak accusation never stands alone', () => {
    const result = applyConfidenceFloor(analysis({ verdict: 'fail', confidence: 0.2 }), 0.75);
    expect(result.verdict).toBe('unclear');
    expect(result.escalationReason).toContain("Downgraded from 'fail'");
  });

  // A model that will not commit to a number has told us something, and it is
  // not "proceed".
  it('downgrades when no confidence was given at all', () => {
    const result = applyConfidenceFloor(analysis({ verdict: 'pass', confidence: null }), 0.75);
    expect(result.verdict).toBe('unclear');
    expect(result.escalationReason).toContain('no confidence score');
  });

  it('treats confidence exactly at the floor as sufficient', () => {
    const result = applyConfidenceFloor(analysis({ verdict: 'pass', confidence: 0.75 }), 0.75);
    expect(result.verdict).toBe('pass');
  });

  // Preserves the analyzer's own escalation reason rather than overwriting it
  // with a threshold message that would be false.
  it('leaves an already-unclear verdict untouched', () => {
    const original = analysis({
      verdict: 'unclear',
      confidence: 0.1,
      escalationReason: 'The image is too dark to judge.',
    });
    const result = applyConfidenceFloor(original, 0.75);
    expect(result).toEqual(original);
  });

  it('preserves the rationale and token accounting when downgrading', () => {
    const result = applyConfidenceFloor(analysis({ verdict: 'pass', confidence: 0.1 }), 0.75);
    expect(result.rationale).toBe('The photo shows the described activity.');
    expect(result.inputTokens).toBe(100);
    expect(result.outputTokens).toBe(20);
    expect(result.model).toBe('claude-opus-5');
  });

  // A floor of 0 is how an operator says "never downgrade"; it must not still
  // reject a confidence of exactly 0.
  it('honours a zero floor', () => {
    const result = applyConfidenceFloor(analysis({ verdict: 'pass', confidence: 0 }), 0);
    expect(result.verdict).toBe('pass');
  });
});

describe('isSupportedImageType', () => {
  it('accepts the media types the Messages API takes as image input', () => {
    for (const type of ['image/jpeg', 'image/png', 'image/gif', 'image/webp']) {
      expect(isSupportedImageType(type)).toBe(true);
    }
  });

  it('tolerates a charset parameter and odd casing', () => {
    expect(isSupportedImageType('image/JPEG')).toBe(true);
    expect(isSupportedImageType('image/png; charset=binary')).toBe(true);
    expect(isSupportedImageType('  image/webp  ')).toBe(true);
  });

  // Video is the reason the escalation path exists: the API takes images, not
  // video, so a video submission must be routed to a human rather than
  // guessed at. If this ever returns true, frame extraction has to exist.
  it('rejects video', () => {
    for (const type of ['video/mp4', 'video/quicktime', 'video/webm']) {
      expect(isSupportedImageType(type)).toBe(false);
    }
  });

  it('rejects anything else, including formats vision does not accept', () => {
    for (const type of ['image/heic', 'image/svg+xml', 'application/pdf', 'text/plain', '']) {
      expect(isSupportedImageType(type)).toBe(false);
    }
  });
});

/// The single post-processing step both providers share.
///
/// It exists so the eval's per-provider accuracy compares judgement rather
/// than two different clamping policies — and, since the shared schema
/// deliberately carries no size or range keywords (see proof-prompt.ts), it is
/// the *only* thing standing between model output and columns with CHECK
/// constraints.
describe('parseVerdictPayload', () => {
  const payload = (overrides: Partial<VerdictPayload> = {}): VerdictPayload => ({
    verdict: 'pass',
    confidence: 0.9,
    relevance: 0.8,
    observations: [],
    rationale: '  The photo shows a sunrise.  ',
    escalation_reason: '',
    ...overrides,
  });
  const usage = { inputTokens: 1, outputTokens: 2 };

  it('keeps well-formed values and trims the prose', () => {
    const result = parseVerdictPayload(payload(), 'deep', 'gpt-5.6-sol', usage);
    expect(result.confidence).toBe(0.9);
    expect(result.relevance).toBe(0.8);
    expect(result.rationale).toBe('The photo shows a sunrise.');
    expect(result.model).toBe('gpt-5.6-sol');
  });

  // numeric(4,3) CHECK (… BETWEEN 0 AND 1) on both columns: an out-of-range
  // number from a model would fail the insert inside a queue worker, which is
  // recorded as an analysis failure and retried forever.
  it('clamps confidence and relevance into 0..1', () => {
    const high = parseVerdictPayload(payload({ confidence: 7, relevance: 1.4 }), 'triage', 'm', usage);
    expect(high.confidence).toBe(1);
    expect(high.relevance).toBe(1);
    const low = parseVerdictPayload(payload({ confidence: -3, relevance: -0.2 }), 'triage', 'm', usage);
    expect(low.confidence).toBe(0);
    expect(low.relevance).toBe(0);
  });

  // A model that will not commit to a number has said something, and the
  // confidence floor treats null as "defer".
  it('reports a non-numeric confidence as null rather than zero', () => {
    const result = parseVerdictPayload(
      payload({ confidence: Number.NaN, relevance: undefined as unknown as number }),
      'triage',
      'm',
      usage,
    );
    expect(result.confidence).toBeNull();
    expect(result.relevance).toBeNull();
  });

  // The cap the schema no longer declares. Keeping it here is the point: the
  // grammar is not relied on to enforce bounds that a column does.
  it('caps the observation list at eight', () => {
    const many = Array.from({ length: 20 }, (_, index) => ({
      kind: 'object',
      label: `thing ${index}`,
      present: true,
      confidence: 0.5,
    }));
    const result = parseVerdictPayload(payload({ observations: many }), 'deep', 'm', usage);
    expect(result.observations).toHaveLength(8);
  });

  it('normalises an unknown observation kind instead of dropping the finding', () => {
    const result = parseVerdictPayload(
      payload({ observations: [{ kind: 'vibe', label: 'a pier', present: true, confidence: 0.5 }] }),
      'deep',
      'm',
      usage,
    );
    expect(result.observations[0].kind).toBe('object');
    expect(result.observations[0].label).toBe('a pier');
  });

  it('drops an observation with no label, since it says nothing', () => {
    const result = parseVerdictPayload(
      payload({
        observations: [
          { kind: 'action', label: '   ', present: true, confidence: 0.9 },
          { kind: 'action', label: 'running', present: false, confidence: 0.9 },
        ],
      }),
      'deep',
      'm',
      usage,
    );
    expect(result.observations).toHaveLength(1);
    expect(result.observations[0].label).toBe('running');
  });

  // `present` is what lets an absence be reported at all, so anything other
  // than an explicit true must not read as "seen".
  it('treats a missing or non-boolean present as not seen', () => {
    const result = parseVerdictPayload(
      payload({ observations: [{ kind: 'action', label: 'a sunrise', confidence: 0.9 } as never] }),
      'deep',
      'm',
      usage,
    );
    expect(result.observations[0].present).toBe(false);
  });

  it('bounds the prose to its column widths', () => {
    const result = parseVerdictPayload(
      payload({ rationale: 'r'.repeat(5000), escalation_reason: 'e'.repeat(900) }),
      'deep',
      'm',
      usage,
    );
    expect(result.rationale).toHaveLength(4000);
    expect(result.escalationReason).toHaveLength(500);
  });

  it('survives observations that are not an array at all', () => {
    const result = parseVerdictPayload(
      payload({ observations: 'nope' as never }),
      'deep',
      'm',
      usage,
    );
    expect(result.observations).toEqual([]);
  });
});
