import { describe, expect, it } from 'vitest';
import {
  MAX_EVENT_BACKDATE_MS,
  MAX_EVENT_FUTURE_SKEW_MS,
  analyticsEventTypes,
  clampOccurredAt,
  conversion,
} from '../src/modules/analytics/domain/analytics-events.js';

describe('analytics event rules', () => {
  /// The event store holds only what has no other source. An event type
  /// here that duplicates an authoritative table is the failure mode #81
  /// §28 warns about: two sources for one fact, drifting apart.
  it('records nothing that a table already owns', () => {
    for (const forbidden of [
      'quest_assigned', // user_quests
      'quest_submitted', // submissions
      'quest_approved', // submissions.status
      'verified_visit', // network_evidence
    ]) {
      expect(analyticsEventTypes).not.toContain(forbidden);
    }
  });

  describe('client clocks', () => {
    const received = new Date('2026-09-11T12:00:00.000Z');

    it('keeps a sane timestamp exactly as sent', () => {
      const sent = new Date('2026-09-11T11:45:00.000Z');
      expect(clampOccurredAt(sent, received)).toEqual(sent);
    });

    // Nothing has happened in the future. A little drift is ordinary and
    // absorbed; a clock set ahead is not.
    it('absorbs small forward drift and rejects the rest', () => {
      const slightlyAhead = new Date(received.getTime() + MAX_EVENT_FUTURE_SKEW_MS - 1000);
      expect(clampOccurredAt(slightlyAhead, received)).toEqual(slightlyAhead);

      const nextYear = new Date('2027-01-01T00:00:00.000Z');
      expect(clampOccurredAt(nextYear, received)).toEqual(received);
    });

    /// The case this exists for. A device whose clock is years out would
    /// otherwise put real activity on a day nobody was looking at — which
    /// is worse than losing the event, because it looks like data.
    it('pulls an absurdly old timestamp up to the backdate limit', () => {
      const yearsAgo = new Date('2019-04-02T00:00:00.000Z');
      expect(clampOccurredAt(yearsAgo, received))
        .toEqual(new Date(received.getTime() - MAX_EVENT_BACKDATE_MS));
    });

    // Queued offline for a while is legitimate and must survive intact.
    it('allows genuine offline backdating', () => {
      const anHourAgo = new Date(received.getTime() - 60 * 60 * 1000);
      expect(clampOccurredAt(anHourAgo, received)).toEqual(anHourAgo);
    });

    // Clamped, never dropped: the user really did open the quest, and
    // discarding it punishes them for a setting they do not know is wrong.
    it('falls back to receipt for an unparseable timestamp', () => {
      expect(clampOccurredAt(new Date('not a date'), received)).toEqual(received);
    });
  });

  describe('conversion between stages', () => {
    it('is the ratio when the stage above it has people in it', () => {
      expect(conversion(1000, 320)).toBe(0.32);
    });

    // Null, not zero: a ratio out of nothing is not nought per cent, and
    // 0% invites a business to act on a stage nobody has reached.
    it('is null when the stage above is empty', () => {
      expect(conversion(0, 0)).toBeNull();
      expect(conversion(0, 5)).toBeNull();
    });

    /// Exposure and participation are counted over the same window but the
    /// events and the tables do not line up at its edges — a quest seen
    /// last month and completed today yields more completions than
    /// impressions. Uncapped that prints as 400% and the reader stops
    /// trusting the whole funnel.
    it('never exceeds one when the windows disagree', () => {
      expect(conversion(2, 8)).toBe(1);
    });
  });
});
