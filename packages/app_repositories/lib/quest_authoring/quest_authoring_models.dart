/// A quest as the authoring surface describes it: the dimensions that decide
/// where it can appear, rather than the copy a player reads.
///
/// Deliberately not `QuestModel`. That one is the player's view and carries
/// title, description and timer; this one carries the composable properties —
/// hidden, flagship, time-limited, located — which is what an admin is
/// actually managing when they manage a catalogue.
class AuthoredQuest {
  const AuthoredQuest({
    required this.id,
    required this.title,
    required this.category,
    required this.difficulty,
    required this.xpReward,
    required this.isHidden,
    required this.editorialTier,
    required this.unlockRuleCount,
    this.availableUntil,
    this.placeId,
  });

  final String id;
  final String title;
  final String category;
  final String difficulty;
  final int xpReward;
  final bool isHidden;
  final String editorialTier;

  /// How many rules can open it. Zero on a hidden quest means it is
  /// unreachable — the one combination worth spotting in a list.
  final int unlockRuleCount;

  final DateTime? availableUntil;
  final String? placeId;

  bool get isFlagship => editorialTier == 'flagship';
  bool get isLimited => availableUntil != null;
  bool get hasDestination => placeId != null;

  /// A hidden quest nothing can open. Not an error the server can refuse —
  /// an author may add the rule in a second step — but it is content no
  /// player will ever see, so the panel says so.
  bool get isOrphanedHidden => isHidden && unlockRuleCount == 0;

  factory AuthoredQuest.fromJson(Map<String, dynamic> json) => AuthoredQuest(
        id: json['id'] as String,
        title: json['title'] as String? ?? '',
        category: json['category'] as String? ?? '',
        difficulty: json['difficulty'] as String? ?? '',
        xpReward: (json['xpReward'] as num?)?.toInt() ?? 0,
        isHidden: json['isHidden'] as bool? ?? false,
        editorialTier: json['editorialTier'] as String? ?? 'standard',
        unlockRuleCount: (json['unlockRuleCount'] as num?)?.toInt() ?? 0,
        availableUntil: json['availableUntil'] == null
            ? null
            : DateTime.tryParse(json['availableUntil'] as String),
        placeId: json['placeId'] as String?,
      );
}

/// One step of a chain, with how players are actually doing on it.
class ChainStepOverview {
  const ChainStepOverview({
    required this.stepOrder,
    required this.questId,
    required this.title,
    required this.isHidden,
    required this.xpReward,
    required this.requiresVerification,
    required this.assigned,
    required this.submitted,
    required this.approved,
    required this.rejected,
    this.placeName,
  });

  final int stepOrder;
  final String questId;
  final String title;
  final bool isHidden;
  final int xpReward;
  final bool requiresVerification;
  final String? placeName;

  /// Counted per status rather than as a total: "nobody cleared step 3" and
  /// "nobody reached step 3" look identical in a total and mean completely
  /// different things.
  final int assigned;
  final int submitted;
  final int approved;
  final int rejected;

  int get attempts => assigned + submitted + approved + rejected;
}

class ChainOverview {
  const ChainOverview({
    required this.id,
    required this.name,
    required this.mode,
    required this.completionRule,
    required this.isActive,
    required this.steps,
  });

  final String id;
  final String name;

  /// `solo` — one player walks it. `group` — a relay across a collab group.
  final String mode;

  /// `sequential` — order matters. `all_steps_any_order` — cross-country.
  final String completionRule;

  final bool isActive;
  final List<ChainStepOverview> steps;

  bool get isRelay => mode == 'group';
  bool get orderMatters => completionRule == 'sequential';

  factory ChainOverview.fromJson(Map<String, dynamic> json) => ChainOverview(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        mode: json['mode'] as String? ?? 'solo',
        completionRule: json['completionRule'] as String? ?? 'sequential',
        isActive: json['isActive'] as bool? ?? true,
        steps: (json['steps'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map((s) => ChainStepOverview(
                  stepOrder: (s['stepOrder'] as num?)?.toInt() ?? 0,
                  questId: s['questId'] as String? ?? '',
                  title: s['title'] as String? ?? '',
                  isHidden: s['isHidden'] as bool? ?? false,
                  xpReward: (s['xpReward'] as num?)?.toInt() ?? 0,
                  requiresVerification:
                      s['requiresVerification'] as bool? ?? false,
                  placeName: s['placeName'] as String?,
                  assigned: (s['assigned'] as num?)?.toInt() ?? 0,
                  submitted: (s['submitted'] as num?)?.toInt() ?? 0,
                  approved: (s['approved'] as num?)?.toInt() ?? 0,
                  rejected: (s['rejected'] as num?)?.toInt() ?? 0,
                ))
            .toList(),
      );
}

/// What the author fills in. Sent as JSON; the server's DTO is the authority
/// on what combination is legal, and its 400 is the error the panel shows.
class QuestDraft {
  const QuestDraft({
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.xpReward,
    this.durationHours = 4,
    this.isActive = true,
    this.isHidden = false,
    this.editorialTier = 'standard',
    this.isGloballyDiscoverable = true,
    this.availableFrom,
    this.availableUntil,
    this.sponsorName,
    this.placeId,
    this.requiresVerification = true,
    this.unlockRules = const [],
  });

  final String title;
  final String description;
  final String category;
  final String difficulty;
  final int xpReward;
  final int durationHours;
  final bool isActive;
  final bool isHidden;
  final String editorialTier;
  final bool isGloballyDiscoverable;
  final DateTime? availableFrom;
  final DateTime? availableUntil;
  final String? sponsorName;
  final String? placeId;
  final bool requiresVerification;
  final List<Map<String, dynamic>> unlockRules;

  Map<String, dynamic> toJson() => {
        'title': title,
        'description': description,
        'category': category,
        'difficulty': difficulty,
        'xpReward': xpReward,
        'durationHours': durationHours,
        'isActive': isActive,
        'isHidden': isHidden,
        'editorialTier': editorialTier,
        'isGloballyDiscoverable': isGloballyDiscoverable,
        if (availableFrom != null)
          'availableFrom': availableFrom!.toUtc().toIso8601String(),
        if (availableUntil != null)
          'availableUntil': availableUntil!.toUtc().toIso8601String(),
        if (sponsorName != null && sponsorName!.isNotEmpty)
          'sponsorName': sponsorName,
        // Omitted entirely rather than sent as null: the server treats the
        // key's absence as "no destination", and a null placeId inside a
        // present destination object would fail validation.
        if (placeId != null)
          'destination': {
            'placeId': placeId,
            'requiresVerification': requiresVerification,
          },
        if (unlockRules.isNotEmpty) 'unlockRules': unlockRules,
      };
}

/// A whole multi-stage quest. Steps travel together because the server
/// writes them in one transaction — a chain with a missing step is a quest
/// that dead-ends.
class ChainDraft {
  const ChainDraft({
    required this.name,
    required this.steps,
    this.description = '',
    this.mode = 'solo',
    this.completionRule = 'sequential',
    this.collabGroupId,
  });

  final String name;
  final String description;
  final String mode;
  final String completionRule;
  final String? collabGroupId;
  final List<QuestDraft> steps;

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'mode': mode,
        'completionRule': completionRule,
        if (collabGroupId != null) 'collabGroupId': collabGroupId,
        'steps': steps.map((s) => s.toJson()).toList(),
      };
}
