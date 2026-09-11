import { describe, expect, it } from 'vitest';
import {
  MAX_DAILY_SPAN_DAYS,
  MIN_REPORTABLE_COHORT,
  completionRate,
  isCohortSuppressed,
  resolveDailyWindow,
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

  /// Turning a request into the window the chart draws.
  describe('the daily window', () => {
    // A fixed "today" so these assert arithmetic rather than the clock.
    const today = new Date('2026-09-11T13:45:00.000Z');

    const windowOf = (input: { days?: number; from?: string; to?: string }) => {
      const resolved = resolveDailyWindow(input, today);
      if ('error' in resolved) throw new Error(`unexpected error ${resolved.error}`);
      return resolved.window;
    };

    const errorOf = (input: { days?: number; from?: string; to?: string }) => {
      const resolved = resolveDailyWindow(input, today);
      return 'error' in resolved ? resolved.error : null;
    };

    it('defaults to the last thirty days, ending today', () => {
      expect(windowOf({})).toEqual({ from: '2026-08-13', to: '2026-09-11' });
    });

    // Inclusive on both ends: seven days means today and the six before,
    // not today and the seven before.
    it('counts the rolling window inclusively', () => {
      expect(windowOf({ days: 7 })).toEqual({ from: '2026-09-05', to: '2026-09-11' });
      expect(windowOf({ days: 1 })).toEqual({ from: '2026-09-11', to: '2026-09-11' });
    });

    it('takes an explicit range as given', () => {
      expect(windowOf({ from: '2026-01-01', to: '2026-01-31' }))
        .toEqual({ from: '2026-01-01', to: '2026-01-31' });
    });

    /// A caller who sent both meant the range. Quietly drawing the rolling
    /// window instead would chart dates they never asked about, and the
    /// chart would look right.
    it('lets an explicit range win over a preset', () => {
      expect(windowOf({ days: 7, from: '2026-03-01', to: '2026-03-05' }))
        .toEqual({ from: '2026-03-01', to: '2026-03-05' });
    });

    it('treats one end alone as a single day', () => {
      expect(windowOf({ from: '2026-04-02' }))
        .toEqual({ from: '2026-04-02', to: '2026-04-02' });
      expect(windowOf({ to: '2026-04-02' }))
        .toEqual({ from: '2026-04-02', to: '2026-04-02' });
    });

    it('crosses a month and a year boundary correctly', () => {
      expect(resolveDailyWindow({ days: 3 }, new Date('2026-01-02T00:00:00.000Z')))
        .toEqual({ window: { from: '2025-12-31', to: '2026-01-02' } });
    });

    // A date that parses but does not exist is the one a regex alone lets
    // through: 2026-02-30 becomes March 2nd rather than failing.
    it('rejects a date that does not exist', () => {
      expect(errorOf({ from: '2026-02-30', to: '2026-03-01' })).toBe('INVALID_DATE');
      expect(errorOf({ from: '2026-13-01', to: '2026-13-02' })).toBe('INVALID_DATE');
      expect(errorOf({ from: 'yesterday', to: 'today' })).toBe('INVALID_DATE');
    });

    // Each reason is distinct because each has a different fix.
    it('separates a reversed range from one that is too long', () => {
      expect(errorOf({ from: '2026-05-10', to: '2026-05-01' })).toBe('RANGE_REVERSED');
      expect(errorOf({ from: '2020-01-01', to: '2026-01-01' })).toBe('RANGE_TOO_LONG');
    });

    it('accepts a span of exactly the maximum', () => {
      const to = '2026-09-11';
      const from = new Date(Date.parse(`${to}T00:00:00Z`)
        - (MAX_DAILY_SPAN_DAYS - 1) * 86_400_000).toISOString().slice(0, 10);
      expect(windowOf({ from, to })).toEqual({ from, to });
      // One more day is one too many.
      const tooFar = new Date(Date.parse(`${from}T00:00:00Z`) - 86_400_000)
        .toISOString().slice(0, 10);
      expect(errorOf({ from: tooFar, to })).toBe('RANGE_TOO_LONG');
    });

    // Clamped rather than rejected: `days` is a preset the client sends, so
    // a silly value is a bug in the caller and answering with the biggest
    // legal window beats a 400 nobody sees.
    it('clamps an out-of-range preset instead of failing', () => {
      expect(windowOf({ days: 100_000 }).from)
        .toBe(new Date(Date.parse('2026-09-11T00:00:00Z')
          - (MAX_DAILY_SPAN_DAYS - 1) * 86_400_000).toISOString().slice(0, 10));
      expect(windowOf({ days: 0 })).toEqual({ from: '2026-09-11', to: '2026-09-11' });
    });
  });
});
