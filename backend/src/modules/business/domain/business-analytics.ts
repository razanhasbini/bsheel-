/// The analytics a business may read about its own places (#50).
///
/// Two rules govern everything here, and they are the reason this file
/// exists rather than the shapes living in the repository.
///
/// **Scope.** Every figure is bounded by `business_places` for the calling
/// business. There is no endpoint that answers a question about a place
/// someone else owns, and no parameter that could widen the scope — the
/// place set comes from the caller's membership, never from the request.
///
/// **Exposure.** Aggregates are counts of people, never a list of them. A
/// business learns that eleven people completed a quest at their address;
/// it does not learn who. The single exception is proof the author
/// themselves published to the feed, which every signed-in user can already
/// scroll past — so surfacing it here adds no exposure, and the predicate
/// for it is exactly the feed's own. Private proof is not a business's to
/// read because a quest happened at their address.

/// A count small enough to identify the people in it.
///
/// "1 visitor from this quest" plus a public feed post at the same place is
/// two facts that together name someone. Buckets below this are reported as
/// present-but-suppressed rather than as a number — and never as zero,
/// which would be a lie a business would act on.
export const MIN_REPORTABLE_COHORT = 5;

export interface BusinessAnalyticsSummary {
  /// Places this business speaks for. Zero is a real answer: a business can
  /// exist before any place has been claimed for it.
  readonly places: number;
  readonly completions: number;
  /// Distinct people with at least one approved submission. Always <=
  /// completions, since one person can complete several quests here.
  readonly visitors: number;
  readonly awaitingReview: number;
  readonly rejected: number;
  /// Saves of these places on the map — interest that has not become a
  /// visit yet, which is the one forward-looking number available.
  readonly saves: number;
  readonly publicProof: number;
  readonly xpAwarded: number;
  readonly firstActivityAt: Date | null;
  readonly lastActivityAt: Date | null;
}

export interface BusinessDailyPoint {
  /// ISO date (UTC). Every day in the window is present, including the ones
  /// with no activity — a chart that silently omits empty days draws a
  /// straight line through a quiet week and reads as steady traffic.
  readonly date: string;
  readonly completions: number;
  readonly visitors: number;
}

export interface BusinessQuestPerformance {
  readonly questId: string;
  readonly title: string;
  readonly category: string;
  readonly difficulty: string;
  readonly xpReward: number;
  readonly placeId: string;
  readonly placeName: string;
  /// How many people started it. The denominator for interest, as distinct
  /// from `completions`, which is the numerator for follow-through.
  readonly starts: number;
  readonly completions: number;
  /// Null rather than zero when nobody has started: a quest nobody has seen
  /// has no completion rate, and 0% would rank it as the worst performer
  /// when it is simply untested.
  readonly completionRate: number | null;
  readonly awaitingReview: number;
  readonly cohortSuppressed: boolean;
}

export interface BusinessPlacePerformance {
  readonly placeId: string;
  readonly name: string;
  readonly city: string;
  readonly countryCode: string;
  readonly isPublished: boolean;
  readonly quests: number;
  readonly starts: number;
  readonly completions: number;
  readonly visitors: number;
  readonly saves: number;
  readonly lastActivityAt: Date | null;
  readonly cohortSuppressed: boolean;
}

/// Proof an author published to the feed, at one of this business's places.
///
/// `mediaUrl` is the object key, exactly as the feed returns it; the client
/// exchanges it through POST /media/sign. That endpoint does not re-check
/// who may see the submission, so the key *is* the access — which is why
/// the query that produces this is the only place allowed to decide, and
/// why it applies the feed's predicate rather than a looser one of its own.
export interface BusinessPublicProof {
  readonly submissionId: string;
  readonly questId: string;
  readonly questTitle: string;
  readonly placeId: string;
  readonly placeName: string;
  readonly username: string;
  readonly displayName: string;
  readonly avatarUrl: string | null;
  readonly mediaUrl: string;
  readonly mediaType: string;
  readonly caption: string | null;
  readonly netScore: number;
  readonly submittedAt: Date;
}

/// Where a business's visitors say they are from (#50's tourism analytics).
///
/// Three numbers rather than one list, because a bare list of countries
/// would be read as "these are my visitors" and be wrong. Only visitors who
/// both declared a country *and* consented to analytics can appear in a
/// bucket, so the buckets nearly always sum to less than the real visitor
/// count — and a business shown "3 visitors: Lebanon 3" when forty people
/// came would make decisions on a tenth of its traffic.
///
/// `undisclosed` is therefore not padding: it is the difference between what
/// is known and what happened, stated plainly so the ratio is visible.
export interface BusinessVisitorOrigins {
  /// Distinct people with an approved submission at these places.
  readonly visitors: number;
  /// Of those, how many declared a country and consented to its use.
  readonly disclosed: number;
  /// The rest. Never inferred, never apportioned across the buckets.
  readonly undisclosed: number;
  readonly countries: readonly BusinessOriginBucket[];
  /// Buckets that existed but were below the reporting threshold, collapsed
  /// into one figure so the total still reconciles.
  readonly suppressedCountries: number;
  readonly suppressedVisitors: number;
}

export interface BusinessOriginBucket {
  /// ISO 3166-1 alpha-2, as the visitor declared it.
  readonly countryCode: string;
  readonly visitors: number;
  /// Share of `disclosed`, not of `visitors` — a percentage of a number the
  /// business can see, rather than of one nobody knows.
  readonly shareOfDisclosed: number;
}

/// Whether a cohort is too small to report as a number.
export const isCohortSuppressed = (people: number): boolean =>
  people > 0 && people < MIN_REPORTABLE_COHORT;

/// Completion rate, or null when there is nothing to divide by.
export function completionRate(starts: number, completions: number): number | null {
  if (starts <= 0) return null;
  // Clamped because a quest can be completed after being started in an
  // earlier window; an uncapped ratio would print 120% follow-through.
  return Math.min(1, Math.round((completions / starts) * 1000) / 1000);
}

/// The longest span the daily series will draw.
///
/// The window is a `generate_series` of one row per day, so an unbounded
/// span builds an arbitrarily large table on the server to answer one
/// chart request. A year and a day covers "the last twelve months" without
/// an off-by-one argument.
export const MAX_DAILY_SPAN_DAYS = 366;

export interface DailyWindow {
  /// Inclusive, `YYYY-MM-DD` in UTC.
  readonly from: string;
  readonly to: string;
}

export type DailyWindowError =
  | 'INVALID_DATE'
  | 'RANGE_REVERSED'
  | 'RANGE_TOO_LONG';

const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

const isRealDate = (value: string): boolean => {
  if (!DATE_ONLY.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  // Round-tripping catches the dates that parse but do not exist —
  // 2026-02-30 becomes March 2nd rather than failing.
  return !Number.isNaN(parsed.getTime())
    && parsed.toISOString().slice(0, 10) === value;
};

const daysBetween = (from: string, to: string): number =>
  Math.round(
    (Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86_400_000,
  ) + 1;

/// Turns a request into the window the chart will draw.
///
/// An explicit `from`/`to` wins over `days`: a caller that sent both meant
/// the range, and silently using the rolling window instead would draw a
/// chart for dates they did not ask about. `days` alone is the rolling
/// window ending today, which is what the preset buttons send.
///
/// Returns an error rather than throwing so the caller decides the status
/// code, and so the reason survives into the message — "reversed" and "too
/// long" have different fixes and a bare 400 has neither.
export function resolveDailyWindow(
  input: { days?: number; from?: string; to?: string },
  today: Date,
): { window: DailyWindow } | { error: DailyWindowError } {
  const stamp = today.toISOString().slice(0, 10);

  if (input.from !== undefined || input.to !== undefined) {
    const from = input.from ?? input.to!;
    const to = input.to ?? input.from!;
    if (!isRealDate(from) || !isRealDate(to)) return { error: 'INVALID_DATE' };
    if (Date.parse(from) > Date.parse(to)) return { error: 'RANGE_REVERSED' };
    if (daysBetween(from, to) > MAX_DAILY_SPAN_DAYS) {
      return { error: 'RANGE_TOO_LONG' };
    }
    return { window: { from, to } };
  }

  const days = Math.min(
    Math.max(input.days ?? 30, 1),
    MAX_DAILY_SPAN_DAYS,
  );
  const from = new Date(Date.parse(`${stamp}T00:00:00Z`) - (days - 1) * 86_400_000)
    .toISOString()
    .slice(0, 10);
  return { window: { from, to: stamp } };
}
