/// Where a milestone sits in a multi-step quest.
///
/// Server-decided, never inferred here: a step opens only on *approved*
/// proof, and approval is something only the backend has seen. Guessing
/// would draw an unlockable milestone that refuses when tapped.
enum MilestoneState { complete, inReview, current, locked }

MilestoneState _stateFrom(String raw) => switch (raw) {
      'COMPLETE' => MilestoneState.complete,
      'IN_REVIEW' => MilestoneState.inReview,
      'CURRENT' => MilestoneState.current,
      _ => MilestoneState.locked,
    };

class JourneyMilestone {
  const JourneyMilestone({
    required this.questId,
    required this.stepOrder,
    required this.state,
    required this.xpReward,
    required this.requiresLocationVerification,
    this.title,
    this.placeName,
    this.countryName,
    this.completedBy,
  });

  final String questId;
  final int stepOrder;
  final MilestoneState state;
  final int xpReward;
  final bool requiresLocationVerification;

  /// Null while a hidden chain's later step is still locked — the mystery is
  /// the point.
  final String? title;
  final String? placeName;
  final String? countryName;

  /// Who cleared it, on a relay. Null on a solo journey.
  final String? completedBy;

  factory JourneyMilestone.fromJson(Map<String, dynamic> json) =>
      JourneyMilestone(
        questId: json['questId'] as String,
        stepOrder: (json['stepOrder'] as num).toInt(),
        state: _stateFrom(json['state'] as String? ?? 'LOCKED'),
        xpReward: (json['xpReward'] as num?)?.toInt() ?? 0,
        requiresLocationVerification:
            json['requiresLocationVerification'] as bool? ?? false,
        title: json['title'] as String?,
        placeName: json['placeName'] as String?,
        countryName: json['countryName'] as String?,
        completedBy: json['completedBy'] as String?,
      );
}

class QuestJourney {
  const QuestJourney({
    required this.chainId,
    required this.name,
    required this.description,
    required this.mode,
    required this.completionRule,
    required this.milestones,
    required this.completedSteps,
    required this.totalSteps,
  });

  final String chainId;
  final String name;
  final String description;

  /// `solo` — one player walks it. `group` — a relay across a group.
  final String mode;

  /// `sequential` — order matters. `all_steps_any_order` — cross-country.
  final String completionRule;

  final List<JourneyMilestone> milestones;
  final int completedSteps;
  final int totalSteps;

  bool get isRelay => mode == 'group';
  bool get orderMatters => completionRule == 'sequential';

  factory QuestJourney.fromJson(Map<String, dynamic> json) => QuestJourney(
        chainId: json['chainId'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        mode: json['mode'] as String? ?? 'solo',
        completionRule: json['completionRule'] as String? ?? 'sequential',
        milestones: (json['milestones'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(JourneyMilestone.fromJson)
            .toList(),
        completedSteps: (json['completedSteps'] as num?)?.toInt() ?? 0,
        totalSteps: (json['totalSteps'] as num?)?.toInt() ?? 0,
      );
}

/// A country the catalogue actually has quests for.
class DiscoveryCountry {
  const DiscoveryCountry({
    required this.code,
    required this.name,
    required this.questCount,
  });

  final String code;
  final String name;
  final int questCount;

  factory DiscoveryCountry.fromJson(Map<String, dynamic> json) =>
      DiscoveryCountry(
        code: json['code'] as String,
        name: json['name'] as String? ?? '',
        questCount: (json['questCount'] as num?)?.toInt() ?? 0,
      );
}
