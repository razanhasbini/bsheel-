import { describe, expect, it } from 'vitest';
import { deterministicXp, explainXp } from '../src/modules/agent/domain/verification-policy.js';

// The thresholds play no part in either explanation — they gate a model's
// confidence, not an award — but PolicyBounds is one object, so they are
// supplied rather than the type widened.
const bounds = {
  minXp: 5,
  maxXp: 100,
  minDurationMinutes: 240,
  maxDurationMinutes: 20_160,
  approveThreshold: 0.75,
  rejectThreshold: 0.85,
};

const shape = (overrides: Partial<Parameters<typeof explainXp>[0]> = {}) => ({
  distanceMeters: null,
  hasDestination: true,
  category: 'adventure',
  difficulty: 'easy',
  participantCount: 1,
  ...overrides,
});

/// A breakdown that disagrees with the award is worse than no breakdown —
/// it teaches somebody a wrong rule. These pin the two to each other.
describe('XP breakdown', () => {
  it('always sums to the number it explains', () => {
    const cases = [
      shape(),
      shape({ distanceMeters: 1_200, difficulty: 'hard' }),
      shape({ distanceMeters: 40_000, difficulty: 'medium', participantCount: 3 }),
      shape({ distanceMeters: 900_000, difficulty: 'hard', participantCount: 4 }),
      shape({ hasDestination: false, difficulty: 'easy' }),
    ];
    for (const input of cases) {
      const breakdown = explainXp(input, bounds);
      expect(breakdown.total).toBe(deterministicXp(input, bounds));
      const summed = breakdown.components.reduce((n, c) => n + c.xp, 0);
      expect(summed).toBe(breakdown.subtotal);
      // The total is the subtotal unless the clamp bit.
      expect(breakdown.total).toBe(Math.min(bounds.maxXp, Math.max(bounds.minXp, breakdown.subtotal)));
    }
  });

  it('names the travel band it actually used', () => {
    expect(explainXp(shape({ distanceMeters: 900_000 }), bounds).travelBand).toBe('far');
    expect(explainXp(shape({ distanceMeters: 40_000 }), bounds).travelBand).toBe('city');
    expect(explainXp(shape({ hasDestination: false }), bounds).travelBand).toBe('none');
    // Not measured is its own band, and it is not zero: a quest whose
    // distance nobody recorded is not the same as one done at home.
    expect(explainXp(shape({ distanceMeters: null }), bounds).travelBand).toBe('unknown');
  });

  it('rewards crossing a border more than walking down the street', () => {
    // The product claim the breakdown is there to make visible.
    const near = explainXp(shape({ distanceMeters: 1_000 }), bounds).total;
    const far = explainXp(shape({ distanceMeters: 900_000 }), bounds).total;
    expect(far).toBeGreaterThan(near);
  });

  it('shows the clamp rather than hiding it', () => {
    const breakdown = explainXp(
      shape({ distanceMeters: 900_000, difficulty: 'hard', participantCount: 9 }),
      { ...bounds, maxXp: 20 },
    );
    expect(breakdown.subtotal).toBeGreaterThan(20);
    expect(breakdown.total).toBe(20);
    expect(breakdown.clampedTo.max).toBe(20);
  });
});
