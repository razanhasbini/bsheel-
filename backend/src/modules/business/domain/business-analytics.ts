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
