/// Business / destination accounts (#14) and their analytics (#50).
///
/// The shape to hold onto: a business is an ordinary player with extra
/// rights over its own places. `BusinessSummary` is what a *member* sees
/// about their own business; nothing here is public, and nothing here is
/// another business's.

/// Whether the account is in good standing. Distinct from whether it has
/// bought analytics — see [BusinessSummary.analyticsSubscribed].
enum BusinessStatus { active, suspended }

/// What a member may do, scoped to one business. There is no global business
/// role: owning one says nothing about any other.
enum BusinessMemberRole { owner, manager }

BusinessStatus _statusOf(String? raw) =>
    raw == 'suspended' ? BusinessStatus.suspended : BusinessStatus.active;

BusinessMemberRole _roleOf(String? raw) =>
    raw == 'owner' ? BusinessMemberRole.owner : BusinessMemberRole.manager;

/// A place the business speaks for.
class BusinessPlace {
  const BusinessPlace({
    required this.placeId,
    required this.name,
    required this.city,
    required this.countryCode,
    required this.category,
    required this.isPublished,
  });

  final String placeId, name, city, countryCode, category;

  /// An unpublished place is claimed but not yet on the map, so it will show
  /// no activity at all. Worth surfacing rather than leaving an owner to
  /// wonder why a location reports nothing.
  final bool isPublished;

  factory BusinessPlace.fromJson(Map<String, dynamic> j) => BusinessPlace(
      placeId: j['placeId'] as String,
      name: j['name'] as String,
      city: (j['city'] as String?) ?? '',
      countryCode: (j['countryCode'] as String?) ?? '',
      category: (j['category'] as String?) ?? '',
      isPublished: (j['isPublished'] as bool?) ?? false);
}

/// A business as one of its own members sees it.
class BusinessSummary {
  const BusinessSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    required this.membershipRole,
    required this.analyticsSubscribed,
    this.description = '',
    this.logoUrl,
    this.websiteUrl,
    this.places = const [],
  });

  final String id, name, slug, description;
  final String? logoUrl, websiteUrl;
  final BusinessStatus status;
  final BusinessMemberRole membershipRole;

  /// Whether analytics was bought. Separate from [status] deliberately: a
  /// business in good standing may simply not be subscribed, and the UI has
  /// to tell those two apart to say anything useful.
  final bool analyticsSubscribed;
  final List<BusinessPlace> places;

  bool get isOwner => membershipRole == BusinessMemberRole.owner;
  bool get isSuspended => status == BusinessStatus.suspended;

  /// The dashboard is reachable only when the account is in good standing
  /// *and* subscribed — the same two conditions the API enforces. Mirrored
  /// here so the client can explain the refusal instead of showing an empty
  /// screen, never to decide it.
  bool get canOpenDashboard => !isSuspended && analyticsSubscribed;

  factory BusinessSummary.fromJson(Map<String, dynamic> j) => BusinessSummary(
      id: j['id'] as String,
      name: j['name'] as String,
      slug: (j['slug'] as String?) ?? '',
      description: (j['description'] as String?) ?? '',
      logoUrl: j['logoUrl'] as String?,
      websiteUrl: j['websiteUrl'] as String?,
      status: _statusOf(j['status'] as String?),
      membershipRole: _roleOf(j['membershipRole'] as String?),
      analyticsSubscribed: j['analyticsSubscribedAt'] != null,
      places: ((j['places'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BusinessPlace.fromJson)
          .toList());
}

/// A member of a business, as the team list shows them.
class BusinessMember {
  const BusinessMember({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.role,
  });

  final String userId, username, displayName;
  final BusinessMemberRole role;

  factory BusinessMember.fromJson(Map<String, dynamic> j) => BusinessMember(
      userId: j['userId'] as String,
      username: j['username'] as String,
      displayName: (j['displayName'] as String?) ?? j['username'] as String,
      role: _roleOf(j['role'] as String?));
}

/// The dashboard's headline figures.
class BusinessAnalyticsSummary {
  const BusinessAnalyticsSummary({
    required this.places,
    required this.completions,
    required this.visitors,
    required this.awaitingReview,
    required this.rejected,
    required this.saves,
    required this.publicProof,
    required this.xpAwarded,
    required this.minReportableCohort,
    this.firstActivityAt,
    this.lastActivityAt,
  });

  final int places, completions, visitors, awaitingReview, rejected;
  final int saves, publicProof, xpAwarded;

  /// The threshold the server suppressed small cohorts at. Carried in the
  /// response so the UI states the same number the server enforced rather
  /// than hard-coding one that could drift from it.
  final int minReportableCohort;
  final DateTime? firstActivityAt, lastActivityAt;

  /// True before anything has ever happened at these places. Distinguishes
  /// "nothing yet" from "zero this period", which read very differently to
  /// someone who just claimed a location.
  bool get hasActivity => firstActivityAt != null;

  factory BusinessAnalyticsSummary.fromJson(Map<String, dynamic> j) =>
      BusinessAnalyticsSummary(
          places: (j['places'] as num).toInt(),
          completions: (j['completions'] as num).toInt(),
          visitors: (j['visitors'] as num).toInt(),
          awaitingReview: (j['awaitingReview'] as num).toInt(),
          rejected: (j['rejected'] as num).toInt(),
          saves: (j['saves'] as num).toInt(),
          publicProof: (j['publicProof'] as num).toInt(),
          xpAwarded: (j['xpAwarded'] as num).toInt(),
          minReportableCohort: (j['minReportableCohort'] as num?)?.toInt() ?? 5,
          firstActivityAt: _dateOrNull(j['firstActivityAt']),
          lastActivityAt: _dateOrNull(j['lastActivityAt']));
}

DateTime? _dateOrNull(Object? raw) =>
    raw is String && raw.isNotEmpty ? DateTime.tryParse(raw)?.toLocal() : null;

/// The completion series, plus the window the server actually drew.
///
/// The window travels with the points so the chart labels the dates the
/// server used rather than recomputing them — a client that derived "today"
/// itself would disagree by a day for anyone west of UTC.
class BusinessDailySeries {
  const BusinessDailySeries({
    required this.from,
    required this.to,
    required this.points,
  });

  final String from, to;
  final List<BusinessDailyPoint> points;

  int get totalCompletions =>
      points.fold(0, (sum, point) => sum + point.completions);

  factory BusinessDailySeries.fromJson(Map<String, dynamic> j) {
    final window = ((j['window'] as Map?) ?? const {}).cast<String, dynamic>();
    return BusinessDailySeries(
      from: (window['from'] as String?) ?? '',
      to: (window['to'] as String?) ?? '',
      points: ((j['points'] as List?) ?? const [])
          .cast<Map<String, dynamic>>()
          .map(BusinessDailyPoint.fromJson)
          .toList(),
    );
  }
}

/// One day of the completion series. Every day in the window is present,
/// including the empty ones — a chart that omits quiet days draws a straight
/// line through them and reads as steady traffic.
class BusinessDailyPoint {
  const BusinessDailyPoint(
      {required this.date, required this.completions, required this.visitors});

  final String date;
  final int completions, visitors;

  factory BusinessDailyPoint.fromJson(Map<String, dynamic> j) =>
      BusinessDailyPoint(
          date: j['date'] as String,
          completions: (j['completions'] as num).toInt(),
          visitors: (j['visitors'] as num).toInt());
}

/// How one quest at the business performs.
class BusinessQuestPerformance {
  const BusinessQuestPerformance({
    required this.questId,
    required this.title,
    required this.placeName,
    required this.starts,
    required this.completions,
    required this.awaitingReview,
    required this.cohortSuppressed,
    this.category = '',
    this.difficulty = '',
    this.xpReward = 0,
    this.completionRate,
  });

  final String questId, title, placeName, category, difficulty;
  final int starts, completions, awaitingReview, xpReward;

  /// Null when nobody has started, never zero: 0% would rank an untested
  /// quest as the worst performer and read as advice to change something
  /// nobody has tried.
  final double? completionRate;

  /// The visitor count behind this row was too small to report without
  /// identifying the people in it.
  final bool cohortSuppressed;

  factory BusinessQuestPerformance.fromJson(Map<String, dynamic> j) =>
      BusinessQuestPerformance(
          questId: j['questId'] as String,
          title: j['title'] as String,
          placeName: (j['placeName'] as String?) ?? '',
          category: (j['category'] as String?) ?? '',
          difficulty: (j['difficulty'] as String?) ?? '',
          xpReward: (j['xpReward'] as num?)?.toInt() ?? 0,
          starts: (j['starts'] as num).toInt(),
          completions: (j['completions'] as num).toInt(),
          completionRate: (j['completionRate'] as num?)?.toDouble(),
          awaitingReview: (j['awaitingReview'] as num?)?.toInt() ?? 0,
          cohortSuppressed: (j['cohortSuppressed'] as bool?) ?? false);
}

/// How one claimed place performs.
class BusinessPlacePerformance {
  const BusinessPlacePerformance({
    required this.placeId,
    required this.name,
    required this.quests,
    required this.starts,
    required this.completions,
    required this.visitors,
    required this.saves,
    required this.isPublished,
    required this.cohortSuppressed,
    this.city = '',
    this.countryCode = '',
    this.lastActivityAt,
  });

  final String placeId, name, city, countryCode;
  final int quests, starts, completions, visitors, saves;
  final bool isPublished, cohortSuppressed;
  final DateTime? lastActivityAt;

  factory BusinessPlacePerformance.fromJson(Map<String, dynamic> j) =>
      BusinessPlacePerformance(
          placeId: j['placeId'] as String,
          name: j['name'] as String,
          city: (j['city'] as String?) ?? '',
          countryCode: (j['countryCode'] as String?) ?? '',
          quests: (j['quests'] as num).toInt(),
          starts: (j['starts'] as num).toInt(),
          completions: (j['completions'] as num).toInt(),
          visitors: (j['visitors'] as num).toInt(),
          saves: (j['saves'] as num).toInt(),
          isPublished: (j['isPublished'] as bool?) ?? false,
          cohortSuppressed: (j['cohortSuppressed'] as bool?) ?? false,
          lastActivityAt: _dateOrNull(j['lastActivityAt']));
}

/// The funnel (#81 §8), in two halves that are deliberately not merged.
///
/// [exposure] is **client-attested** — a phone reported that it drew a quest
/// card, and nothing server-side can confirm it. [participation] is what the
/// server wrote while doing the work. A screen that draws them as one
/// uniform funnel invites a business to read impressions as solidly as
/// completions, which is why they arrive separately and carry
/// [exposureIsClientReported].
///
/// [exposure] is null when no telemetry was reported at all. That is not
/// zero: "nothing was reported" is a statement about Bsheel, "nobody saw it"
/// is a statement about the business.
class BusinessFunnel {
  const BusinessFunnel({
    required this.from,
    required this.to,
    required this.participation,
    this.exposure,
    this.impressionToView,
    this.viewToBsheeel,
    this.bsheeelToActivation,
    this.activationToCompletion,
    this.exposureIsClientReported = true,
  });

  final String from, to;
  final BusinessExposure? exposure;
  final BusinessParticipation participation;

  /// Null wherever the stage above is empty or unreported — never zero,
  /// which would invite acting on a stage nobody has reached.
  final double? impressionToView, viewToBsheeel;
  final double? bsheeelToActivation, activationToCompletion;

  final bool exposureIsClientReported;

  bool get hasExposure => exposure != null;

  factory BusinessFunnel.fromJson(Map<String, dynamic> j) {
    final window = ((j['window'] as Map?) ?? const {}).cast<String, dynamic>();
    final conversion =
        ((j['conversion'] as Map?) ?? const {}).cast<String, dynamic>();
    final attestation =
        ((j['attestation'] as Map?) ?? const {}).cast<String, dynamic>();
    final exposure = j['exposure'] as Map?;
    return BusinessFunnel(
      from: (window['from'] as String?) ?? '',
      to: (window['to'] as String?) ?? '',
      exposure: exposure == null
          ? null
          : BusinessExposure.fromJson(exposure.cast<String, dynamic>()),
      participation: BusinessParticipation.fromJson(
          ((j['participation'] as Map?) ?? const {}).cast<String, dynamic>()),
      impressionToView: (conversion['impressionToView'] as num?)?.toDouble(),
      viewToBsheeel: (conversion['viewToBsheeel'] as num?)?.toDouble(),
      bsheeelToActivation:
          (conversion['bsheeelToActivation'] as num?)?.toDouble(),
      activationToCompletion:
          (conversion['activationToCompletion'] as num?)?.toDouble(),
      // Defaults to the cautious reading if the server ever stops saying.
      exposureIsClientReported:
          (attestation['exposure'] as String?) != 'server_authoritative',
    );
  }
}

class BusinessExposure {
  const BusinessExposure({
    required this.impressions,
    required this.detailViews,
    required this.bsheeels,
    required this.shares,
    required this.reach,
  });

  final int impressions, detailViews, bsheeels, shares;

  /// People, not screens. Impressions counts times a card was drawn.
  final int reach;

  factory BusinessExposure.fromJson(Map<String, dynamic> j) => BusinessExposure(
      impressions: (j['impressions'] as num?)?.toInt() ?? 0,
      detailViews: (j['detailViews'] as num?)?.toInt() ?? 0,
      bsheeels: (j['bsheeels'] as num?)?.toInt() ?? 0,
      shares: (j['shares'] as num?)?.toInt() ?? 0,
      reach: (j['reach'] as num?)?.toInt() ?? 0);
}

class BusinessParticipation {
  const BusinessParticipation({
    required this.activations,
    required this.completions,
    required this.visitors,
  });

  final int activations, completions, visitors;

  factory BusinessParticipation.fromJson(Map<String, dynamic> j) =>
      BusinessParticipation(
          activations: (j['activations'] as num?)?.toInt() ?? 0,
          completions: (j['completions'] as num?)?.toInt() ?? 0,
          visitors: (j['visitors'] as num?)?.toInt() ?? 0);
}

/// Where visitors said they were from.
///
/// The three counts are the point. Only visitors who declared a country
/// *and* consented can appear in a bucket, so [countries] nearly always
/// accounts for fewer people than [visitors] — and a business shown
/// "Lebanon 100%" over five disclosed visitors when forty came would be
/// reading an eighth of its traffic as all of it. [undisclosed] is the
/// difference, stated rather than hidden.
class BusinessVisitorOrigins {
  const BusinessVisitorOrigins({
    required this.visitors,
    required this.disclosed,
    required this.undisclosed,
    required this.countries,
    required this.suppressedCountries,
    required this.suppressedVisitors,
  });

  final int visitors, disclosed, undisclosed;
  final List<BusinessOriginBucket> countries;

  /// Countries that were present but too small to name, collapsed so the
  /// figures still reconcile against [disclosed].
  final int suppressedCountries, suppressedVisitors;

  /// Nothing to show yet — nobody has both declared a country and consented.
  /// A distinct state from "no visitors", and the UI must say which.
  bool get nothingDisclosed => disclosed == 0;

  factory BusinessVisitorOrigins.fromJson(Map<String, dynamic> j) =>
      BusinessVisitorOrigins(
          visitors: (j['visitors'] as num).toInt(),
          disclosed: (j['disclosed'] as num).toInt(),
          undisclosed: (j['undisclosed'] as num).toInt(),
          countries: ((j['countries'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()
              .map(BusinessOriginBucket.fromJson)
              .toList(),
          suppressedCountries: (j['suppressedCountries'] as num?)?.toInt() ?? 0,
          suppressedVisitors: (j['suppressedVisitors'] as num?)?.toInt() ?? 0);
}

class BusinessOriginBucket {
  const BusinessOriginBucket(
      {required this.countryCode,
      required this.visitors,
      required this.shareOfDisclosed});

  final String countryCode;
  final int visitors;

  /// Share of the disclosed population, not of all visitors — a percentage
  /// of a number the business can actually see.
  final double shareOfDisclosed;

  factory BusinessOriginBucket.fromJson(Map<String, dynamic> j) =>
      BusinessOriginBucket(
          countryCode: j['countryCode'] as String,
          visitors: (j['visitors'] as num).toInt(),
          shareOfDisclosed: (j['shareOfDisclosed'] as num).toDouble());
}

/// Proof an author published to the feed, at one of the business's places.
///
/// Everything here is already visible to any signed-in user on the feed —
/// that is the only reason a business may see it. [mediaUrl] arrives signed.
class BusinessPublicProof {
  const BusinessPublicProof({
    required this.submissionId,
    required this.questTitle,
    required this.placeName,
    required this.username,
    required this.displayName,
    required this.mediaUrl,
    required this.mediaType,
    required this.submittedAt,
    this.caption,
    this.avatarUrl,
    this.netScore = 0,
  });

  final String submissionId, questTitle, placeName, username, displayName;
  final String mediaUrl, mediaType;
  final String? caption, avatarUrl;
  final int netScore;
  final DateTime submittedAt;

  bool get isVideo => mediaType == 'video';

  factory BusinessPublicProof.fromJson(Map<String, dynamic> j) =>
      BusinessPublicProof(
          submissionId: j['submissionId'] as String,
          questTitle: (j['questTitle'] as String?) ?? '',
          placeName: (j['placeName'] as String?) ?? '',
          username: (j['username'] as String?) ?? '',
          displayName: (j['displayName'] as String?) ?? '',
          mediaUrl: (j['mediaUrl'] as String?) ?? '',
          mediaType: (j['mediaType'] as String?) ?? 'image',
          caption: j['caption'] as String?,
          avatarUrl: j['avatarUrl'] as String?,
          netScore: (j['netScore'] as num?)?.toInt() ?? 0,
          submittedAt: _dateOrNull(j['submittedAt']) ??
              DateTime.fromMillisecondsSinceEpoch(0));
}

/// One page of published proof, with the cursor for the next.
class BusinessProofPage {
  const BusinessProofPage({required this.items, this.nextCursor});

  final List<BusinessPublicProof> items;

  /// Null when this is the last page. Keyset, so a submission arriving
  /// mid-scroll cannot shift a boundary and duplicate or skip a row.
  final BusinessProofCursor? nextCursor;

  factory BusinessProofPage.fromJson(Map<String, dynamic> j) =>
      BusinessProofPage(
          items: ((j['items'] as List?) ?? const [])
              .cast<Map<String, dynamic>>()
              .map(BusinessPublicProof.fromJson)
              .toList(),
          nextCursor: j['nextCursor'] == null
              ? null
              : BusinessProofCursor.fromJson(
                  (j['nextCursor'] as Map).cast<String, dynamic>()));
}

class BusinessProofCursor {
  const BusinessProofCursor(
      {required this.beforeSubmittedAt, required this.beforeId});

  final String beforeSubmittedAt, beforeId;

  factory BusinessProofCursor.fromJson(Map<String, dynamic> j) =>
      BusinessProofCursor(
          beforeSubmittedAt: j['beforeSubmittedAt'] as String,
          beforeId: j['beforeId'] as String);
}
