/// The event store's rules (#81 §28).
///
/// Read the header of migration 0040 first: this table exists only for the
/// signals that have no other source, and everything in it is
/// **client-attested** rather than server-authoritative. That distinction is
/// not a caveat to bury — it decides how the numbers may be presented.

export const analyticsEventTypes = [
  /// A quest card was drawn on screen. The highest-volume event in the
  /// product and the weakest claim in it: the client says it rendered
  /// something.
  'quest_impression',
  /// A quest was opened.
  'quest_detail_view',
  /// BSHEEEL was pressed. Distinct from `saved_quests`, which is the
  /// resulting *state*: state cannot tell you that somebody pressed it,
  /// unpressed it, and pressed it again, and intent over time is the thing
  /// a business is actually asking about.
  'quest_bsheeel',
  'quest_share',
] as const;

export type AnalyticsEventType = (typeof analyticsEventTypes)[number];

export const analyticsSurfaces = [
  'feed',
  'map',
  'home',
  'search',
  'country',
  'quest_detail',
] as const;

export type AnalyticsSurface = (typeof analyticsSurfaces)[number];

/// How far a client's own timestamp may sit from when we received it.
///
/// A device clock can be wrong by years, and a daily chart drawn on a bad
/// clock puts real activity on the wrong day — which is worse than losing
/// it, because it looks like data. Two hours of backdating covers a phone
/// that queued events offline for a while without letting a broken clock
/// invent a week.
export const MAX_EVENT_BACKDATE_MS = 2 * 60 * 60 * 1000;

/// Clock skew forward is never legitimate: nothing has happened in the
/// future. A small tolerance absorbs ordinary drift between the device and
/// the server rather than rejecting an otherwise good event.
export const MAX_EVENT_FUTURE_SKEW_MS = 60 * 1000;

/// Brings a client timestamp into a window we are willing to chart.
///
/// Clamped rather than rejected. An event with a bad clock is still
/// evidence that something happened — the user really did open a quest —
/// and throwing it away loses a real impression to punish a device setting
/// the person does not know is wrong. Both values are stored, so the
/// clamping is visible in the row rather than silently rewriting history.
export function clampOccurredAt(occurredAt: Date, receivedAt: Date): Date {
  const received = receivedAt.getTime();
  const claimed = occurredAt.getTime();
  if (Number.isNaN(claimed)) return receivedAt;
  if (claimed > received + MAX_EVENT_FUTURE_SKEW_MS) return receivedAt;
  if (claimed < received - MAX_EVENT_BACKDATE_MS) {
    return new Date(received - MAX_EVENT_BACKDATE_MS);
  }
  return occurredAt;
}

/// The top of a business's funnel, from this table.
///
/// Every figure here is client-attested. The stages below it — activations,
/// verified visits, completions — come from `user_quests`, `submissions` and
/// `network_evidence`, and are facts the server wrote. `BusinessFunnel`
/// keeps the two halves in separate fields for exactly that reason: a
/// caller cannot accidentally present them as one kind of number.
export interface ExposureCounts {
  readonly impressions: number;
  readonly detailViews: number;
  readonly bsheeels: number;
  readonly shares: number;
  /// Distinct people who saw a quest at these places at all. The
  /// denominator worth reporting, since impressions counts screens and this
  /// counts people.
  readonly reach: number;
}

export interface BusinessFunnel {
  /// Client-attested. Absent entirely — not zero — when no telemetry has
  /// been recorded for the window, because "nobody saw it" and "nothing was
  /// reported" are different claims and only one of them is ours to make.
  readonly exposure: ExposureCounts | null;
  /// Server-authoritative, from the tables that own each fact.
  readonly participation: {
    readonly activations: number;
    readonly completions: number;
    readonly visitors: number;
  };
}

/// What one post caused, downstream (migration 0049).
///
/// The first three are client-attested events raised *from this post's
/// card*. `activations` and `completions` are server facts: a BSHEEEL from
/// the post, followed by that same person taking the quest, followed by
/// an approved submission — joined from the tables that own each step, so
/// the credit can never say more than the ledgers do. Counts of people,
/// never lists of them: the author learns their post led to three
/// completions, not who completed.
export interface PostAttribution {
  readonly submissionId: string;
  readonly detailViews: number;
  readonly viewers: number;
  readonly bsheeels: number;
  readonly shares: number;
  readonly activations: number;
  readonly completions: number;
}

/// A stage-to-stage conversion, or null when the stage above it is empty.
///
/// Null rather than zero for the same reason `completionRate` is: a ratio
/// out of nothing is not zero per cent, and printing 0% invites a business
/// to act on a stage nobody has reached yet.
export function conversion(from: number, to: number): number | null {
  if (from <= 0) return null;
  // Clamped: events and the tables they feed into are counted over
  // different windows, so a quest seen last month and completed today can
  // otherwise produce more completions than impressions.
  return Math.min(1, Math.round((to / from) * 1000) / 1000);
}
