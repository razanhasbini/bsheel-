import { describe, expect, it } from 'vitest';

/**
 * CAMARA's four Location Verification answers, and where each must land.
 *
 * This exists because of a real defect the hackathon demo surfaced. The
 * mapping read `matchRate ?? 0`, so a PARTIAL that carried no rate — which
 * is exactly what Nokia's simulator returns — was scored 0% and became
 * CONTRADICTED. That turns "the network was vague" into "the user was not
 * there", which is the single failure mode this whole pipeline exists to
 * prevent: a rejection must rest on a positive statement, never on absent
 * data.
 *
 * The mapping is duplicated here rather than imported because the adapter's
 * copy is wrapped in a live SDK call. If they ever disagree, this test is
 * the specification and the adapter is wrong.
 */
type Outcome = 'SUPPORTED' | 'CONTRADICTED' | 'UNAVAILABLE';

function mapVerification(result: string, matchRate?: number): Outcome {
  if (result === 'TRUE') return 'SUPPORTED';
  if (result === 'FALSE') return 'CONTRADICTED';
  if (result === 'PARTIAL') {
    if (typeof matchRate !== 'number') return 'UNAVAILABLE';
    return matchRate >= 80 ? 'SUPPORTED' : 'CONTRADICTED';
  }
  return 'UNAVAILABLE';
}

describe('CAMARA Location Verification → evidence outcome', () => {
  it('TRUE supports presence', () => {
    expect(mapVerification('TRUE')).toBe('SUPPORTED');
  });

  it('FALSE contradicts presence — the network made a positive statement', () => {
    expect(mapVerification('FALSE')).toBe('CONTRADICTED');
  });

  it('UNKNOWN is not evidence of absence', () => {
    expect(mapVerification('UNKNOWN')).toBe('UNAVAILABLE');
  });

  it('PARTIAL with no matchRate is uncertainty, not a rejection', () => {
    // The regression. Nokia's +99999991003 answers exactly this way.
    expect(mapVerification('PARTIAL')).toBe('UNAVAILABLE');
    expect(mapVerification('PARTIAL', undefined)).toBe('UNAVAILABLE');
  });

  it('PARTIAL with a quantified rate is decided on the rate', () => {
    expect(mapVerification('PARTIAL', 95)).toBe('SUPPORTED');
    expect(mapVerification('PARTIAL', 80)).toBe('SUPPORTED');
    expect(mapVerification('PARTIAL', 79)).toBe('CONTRADICTED');
    // A genuine 0% overlap IS a positive statement, unlike a missing rate.
    expect(mapVerification('PARTIAL', 0)).toBe('CONTRADICTED');
  });

  it('an unrecognised result never rejects', () => {
    // A future API version must not be able to cost a user their quest.
    expect(mapVerification('SOMETHING_NEW')).toBe('UNAVAILABLE');
  });
});
