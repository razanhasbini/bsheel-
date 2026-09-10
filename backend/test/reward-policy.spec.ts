import { describe, expect, it } from 'vitest';
import {
  clampDurationMinutes,
  clampXp,
  deterministicQuestMinutes,
  deterministicXp,
  resolvePolicyBounds,
  type PolicyLimits,
  type RewardShapeInputs,
} from '../src/modules/agent/domain/verification-policy.js';

const limits: PolicyLimits = {
  globalMinDurationMinutes: 240, // 4 hours
  globalMaxDurationMinutes: 20_160, // 2 weeks
  globalMinXp: 5,
  globalMaxXp: 100,
  approveThreshold: 0.85,
  rejectThreshold: 0.85,
};

const bounds = resolvePolicyBounds({ baseXp: 20, defaultDurationHours: 24 }, limits);

function shape(overrides: Partial<RewardShapeInputs> = {}): RewardShapeInputs {
  return {
    distanceMeters: null,
    hasDestination: false,
    category: 'social',
    difficulty: 'easy',
    participantCount: 1,
    ...overrides,
  };
}

const HOUR = 60;

describe('policy bounds', () => {
  it('are absolute, not scaled off the quest admin values', () => {
    const wildlyDifferentQuest = resolvePolicyBounds(
      { baseXp: 5000, defaultDurationHours: 1 },
      limits,
    );
    expect(wildlyDifferentQuest).toEqual(bounds);
    expect(bounds.minDurationMinutes).toBe(4 * HOUR);
    expect(bounds.maxDurationMinutes).toBe(14 * 24 * HOUR);
    expect(bounds.minXp).toBe(5);
    expect(bounds.maxXp).toBe(100);
  });

  it('clamps anything outside the range', () => {
    expect(clampDurationMinutes(1, bounds)).toBe(4 * HOUR);
    expect(clampDurationMinutes(999_999, bounds)).toBe(14 * 24 * HOUR);
    expect(clampXp(0, bounds)).toBe(5);
    expect(clampXp(9999, bounds)).toBe(100);
  });
});

describe('deterministic quest duration', () => {
  it('gives a simple at-home quest the 4-hour floor', () => {
    expect(deterministicQuestMinutes(shape(), bounds)).toBe(4 * HOUR);
  });

  it('gives a learning quest 8 hours even with no travel', () => {
    expect(deterministicQuestMinutes(shape({ category: 'learning' }), bounds)).toBe(8 * HOUR);
  });

  it('gives a quest across the user\'s own city about a day', () => {
    const minutes = deterministicQuestMinutes(
      shape({ hasDestination: true, distanceMeters: 20_000 }),
      bounds,
    );
    expect(minutes).toBe(24 * HOUR);
  });

  it('gives a hard regional trip — a mountain hike — around three days or more', () => {
    const minutes = deterministicQuestMinutes(
      shape({ hasDestination: true, distanceMeters: 120_000, difficulty: 'hard', category: 'adventure' }),
      bounds,
    );
    expect(minutes).toBeGreaterThanOrEqual(72 * HOUR);
  });

  it('never exceeds two weeks, even for the hardest long-distance group quest', () => {
    const minutes = deterministicQuestMinutes(
      shape({
        hasDestination: true,
        distanceMeters: 5_000_000,
        difficulty: 'hard',
        participantCount: 4,
      }),
      bounds,
    );
    expect(minutes).toBe(14 * 24 * HOUR);
  });

  it('gives two users different time for the same quest based on distance', () => {
    const near = deterministicQuestMinutes(shape({ hasDestination: true, distanceMeters: 1_000 }), bounds);
    const far = deterministicQuestMinutes(shape({ hasDestination: true, distanceMeters: 900_000 }), bounds);
    expect(far).toBeGreaterThan(near);
  });
});

describe('deterministic XP', () => {
  it('pays the 5 XP floor for something simple at home', () => {
    expect(deterministicXp(shape(), bounds)).toBe(5);
  });

  it('pays more for a harder quest at the same distance', () => {
    const easy = deterministicXp(shape({ hasDestination: true, distanceMeters: 20_000 }), bounds);
    const hard = deterministicXp(
      shape({ hasDestination: true, distanceMeters: 20_000, difficulty: 'hard' }),
      bounds,
    );
    expect(hard).toBeGreaterThan(easy);
  });

  it('pays near the ceiling when someone genuinely travelled far for a hard quest', () => {
    const xp = deterministicXp(
      shape({ hasDestination: true, distanceMeters: 900_000, difficulty: 'hard' }),
      bounds,
    );
    expect(xp).toBeGreaterThanOrEqual(80);
    expect(xp).toBeLessThanOrEqual(100);
  });

  it('never exceeds 100', () => {
    const xp = deterministicXp(
      shape({
        hasDestination: true,
        distanceMeters: 9_000_000,
        difficulty: 'hard',
        participantCount: 6,
      }),
      bounds,
    );
    expect(xp).toBeLessThanOrEqual(100);
  });

  it('gives two users different XP for the same quest based on distance', () => {
    const near = deterministicXp(shape({ hasDestination: true, distanceMeters: 1_000 }), bounds);
    const far = deterministicXp(shape({ hasDestination: true, distanceMeters: 900_000 }), bounds);
    expect(far).toBeGreaterThan(near);
  });

  it('stays conservative when the distance could not be measured', () => {
    const unknown = deterministicXp(shape({ hasDestination: true, distanceMeters: null }), bounds);
    const far = deterministicXp(shape({ hasDestination: true, distanceMeters: 900_000 }), bounds);
    expect(unknown).toBeLessThan(far);
  });
});
