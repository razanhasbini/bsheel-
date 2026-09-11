import { describe, expect, it } from 'vitest';
import {
  MIN_REPORTABLE_COHORT,
  completionRate,
  isCohortSuppressed,
} from '../src/modules/business/domain/business-analytics.js';

describe('business analytics rules', () => {
  describe('completion rate', () => {
    it('is the fraction of starters who finished', () => {
      expect(completionRate(4, 1)).toBe(0.25);
      expect(completionRate(3, 3)).toBe(1);
    });

    // Zero would rank an untested quest as the worst performer in the list,
    // which reads as a recommendation to change something nobody has tried.
    it('is null when nobody has started, not zero', () => {
      expect(completionRate(0, 0)).toBeNull();
      expect(completionRate(-1, 0)).toBeNull();
    });

    /// A quest started in one window and completed in the next produces
    /// more completions than starts. Uncapped, that prints as 120%
    /// follow-through, which is the kind of number that makes a reader stop
    /// trusting the whole dashboard.
    it('never exceeds one, however the windows line up', () => {
      expect(completionRate(2, 5)).toBe(1);
    });

    it('rounds to three places rather than printing float noise', () => {
      expect(completionRate(3, 1)).toBe(0.333);
      expect(completionRate(7, 2)).toBe(0.286);
    });
  });

  describe('cohort suppression', () => {
    // "1 visitor" plus one public feed post at the same place is two facts
    // that together name somebody.
    it('suppresses a cohort small enough to identify its members', () => {
      for (let people = 1; people < MIN_REPORTABLE_COHORT; people += 1) {
        expect(isCohortSuppressed(people), `${people}`).toBe(true);
      }
    });

    it('reports a cohort at or above the threshold', () => {
      expect(isCohortSuppressed(MIN_REPORTABLE_COHORT)).toBe(false);
      expect(isCohortSuppressed(MIN_REPORTABLE_COHORT + 40)).toBe(false);
    });

    // Zero identifies nobody, and flagging it would tell a business its
    // quiet place might be busy — the opposite of what the flag means.
    it('does not suppress an empty cohort', () => {
      expect(isCohortSuppressed(0)).toBe(false);
    });
  });
});
