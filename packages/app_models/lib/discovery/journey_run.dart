/// Where a checkpoint stands for the person looking at it.
enum StageState { completed, underReview, available, locked }

StageState _stageStateFrom(String raw) => switch (raw) {
      'COMPLETED' => StageState.completed,
      'UNDER_REVIEW' => StageState.underReview,
      'AVAILABLE' => StageState.available,
      _ => StageState.locked,
    };

/// One checkpoint of a journey.
///
/// The nullable content fields are not laziness: the server omits a hidden
/// checkpoint's title, description and coordinates entirely rather than
/// sending them for the client to hide. A null [title] here means the
/// backend decided this viewer may not read it yet, and there is nothing
/// local that can reveal it.
class JourneyStage {
  const JourneyStage({
    required this.stepOrder,
    required this.state,
    required this.requiresLocationVerification,
    required this.isYours,
    this.questId,
    this.xpReward,
    this.title,
    this.description,
    this.placeName,
    this.countryName,
    this.latitude,
    this.longitude,
    this.targetUsername,
  });

  final int stepOrder;
  final StageState state;
  final bool requiresLocationVerification;

  /// True when this viewer is the one who may start it.
  final bool isYours;

  final String? questId;
  final int? xpReward;
  final String? title;
  final String? description;
  final String? placeName;
  final String? countryName;
  final double? latitude;
  final double? longitude;

  /// Whose checkpoint this is, on a relay. Null on a solo journey.
  final String? targetUsername;

  /// Enough to draw it on the map. Absent for a hidden checkpoint, which is
  /// why a route is only ever drawn between two places we were told about.
  bool get hasCoordinates => latitude != null && longitude != null;

  factory JourneyStage.fromJson(Map<String, dynamic> json) => JourneyStage(
        stepOrder: (json['stepOrder'] as num).toInt(),
        state: _stageStateFrom(json['state'] as String? ?? 'LOCKED'),
        requiresLocationVerification:
            json['requiresLocationVerification'] as bool? ?? false,
        isYours: json['isYours'] as bool? ?? false,
        questId: json['questId'] as String?,
        xpReward: (json['xpReward'] as num?)?.toInt(),
        title: json['title'] as String?,
        description: json['description'] as String?,
        placeName: json['placeName'] as String?,
        countryName: json['countryName'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        targetUsername: json['targetUsername'] as String?,
      );
}

/// An unlock this viewer has not been shown yet.
///
/// Server-held, so a checkpoint approved while the app was closed still gets
/// its moment when they come back — and cannot get it twice.
class UnseenUnlock {
  const UnseenUnlock({required this.stepOrder, required this.questId});

  final int stepOrder;
  final String questId;

  factory UnseenUnlock.fromJson(Map<String, dynamic> json) => UnseenUnlock(
        stepOrder: (json['stepOrder'] as num).toInt(),
        questId: json['questId'] as String,
      );
}

/// A journey in progress: the parent that stays active while individual
/// checkpoints come and go.
class JourneyRun {
  const JourneyRun({
    required this.runId,
    required this.chainId,
    required this.title,
    required this.description,
    required this.runKind,
    required this.completionRule,
    required this.status,
    required this.completedSteps,
    required this.totalSteps,
    required this.stages,
    this.nextForViewer,
    this.unseenUnlock,
  });

  final String runId;
  final String chainId;
  final String title;
  final String description;

  /// `solo` — one player walks it. `group` — a relay.
  final String runKind;

  /// `sequential` — order matters. `all_steps_any_order` — several
  /// checkpoints can be open at once, so "next stage" is the wrong words.
  final String completionRule;

  final String status;
  final int completedSteps;
  final int totalSteps;
  final List<JourneyStage> stages;

  /// The checkpoint this viewer can start now, if any. Null when the ball is
  /// in a teammate's court.
  final JourneyStage? nextForViewer;

  final UnseenUnlock? unseenUnlock;

  bool get isRelay => runKind == 'group';
  bool get orderMatters => completionRule == 'sequential';
  bool get isCompleted => status == 'completed';
  bool get canContinue => nextForViewer != null;

  /// True while a checkpoint of this viewer's is waiting on a decision.
  bool get isUnderReview =>
      stages.any((s) => s.isYours && s.state == StageState.underReview) ||
      (!canContinue &&
          !isCompleted &&
          stages.any((s) => s.state == StageState.underReview));

  double get progress => totalSteps == 0 ? 0 : completedSteps / totalSteps;

  /// Checkpoints still to do, for an any-order journey where counting down
  /// reads better than naming a next stage that does not exist.
  int get remaining => totalSteps - completedSteps;

  factory JourneyRun.fromJson(Map<String, dynamic> json) {
    final next = json['nextForViewer'];
    final unseen = json['unseenUnlock'];
    return JourneyRun(
      runId: json['runId'] as String,
      chainId: json['chainId'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      runKind: json['runKind'] as String? ?? 'solo',
      completionRule: json['completionRule'] as String? ?? 'sequential',
      status: json['status'] as String? ?? 'active',
      completedSteps: (json['completedSteps'] as num?)?.toInt() ?? 0,
      totalSteps: (json['totalSteps'] as num?)?.toInt() ?? 0,
      stages: (json['stages'] as List? ?? const [])
          .cast<Map<String, dynamic>>()
          .map(JourneyStage.fromJson)
          .toList(),
      nextForViewer:
          next is Map<String, dynamic> ? JourneyStage.fromJson(next) : null,
      unseenUnlock:
          unseen is Map<String, dynamic> ? UnseenUnlock.fromJson(unseen) : null,
    );
  }
}
