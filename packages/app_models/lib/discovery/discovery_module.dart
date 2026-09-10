/// A quest as a discovery shelf shows it.
///
/// Deliberately thinner than the full quest model: a card needs enough to
/// decide with and nothing more. The badges arrive already computed by the
/// server, so the client never infers a mechanic from a combination of
/// columns and the two can never disagree about what a quest is.
class DiscoveryQuestCard {
  const DiscoveryQuestCard({
    required this.id,
    required this.title,
    required this.description,
    required this.category,
    required this.difficulty,
    required this.xpReward,
    required this.durationHours,
    required this.badges,
    this.destination,
  });

  final String id;
  final String title;
  final String description;
  final String category;
  final String difficulty;
  final int xpReward;
  final int durationHours;
  final List<String> badges;
  final DiscoveryDestination? destination;

  factory DiscoveryQuestCard.fromJson(Map<String, dynamic> json) {
    final destination = json['destination'];
    return DiscoveryQuestCard(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? '',
      difficulty: json['difficulty'] as String? ?? '',
      xpReward: (json['xpReward'] as num?)?.toInt() ?? 0,
      durationHours: (json['durationHours'] as num?)?.toInt() ?? 0,
      badges: (json['badges'] as List?)?.cast<String>() ?? const [],
      destination: destination is Map<String, dynamic>
          ? DiscoveryDestination.fromJson(destination)
          : null,
    );
  }
}

class DiscoveryDestination {
  const DiscoveryDestination({
    required this.placeName,
    required this.city,
    required this.countryCode,
    required this.countryName,
    required this.requiresVerification,
  });

  final String placeName;
  final String city;
  final String countryCode;
  final String countryName;
  final bool requiresVerification;

  factory DiscoveryDestination.fromJson(Map<String, dynamic> json) =>
      DiscoveryDestination(
        placeName: json['placeName'] as String? ?? '',
        city: json['city'] as String? ?? '',
        countryCode: json['countryCode'] as String? ?? '',
        countryName: json['countryName'] as String? ?? '',
        requiresVerification: json['requiresVerification'] as bool? ?? false,
      );
}

/// One shelf on Home. The server decides which of these exist and in what
/// order; the client renders what it is given and never re-decides.
class DiscoveryModule {
  const DiscoveryModule({
    required this.type,
    required this.title,
    required this.items,
    required this.journeys,
    this.subtitle,
  });

  final String type;
  final String title;
  final String? subtitle;
  final List<DiscoveryQuestCard> items;
  final List<JourneyProgress> journeys;

  factory DiscoveryModule.fromJson(Map<String, dynamic> json) =>
      DiscoveryModule(
        type: json['type'] as String,
        title: json['title'] as String? ?? '',
        subtitle: json['subtitle'] as String?,
        items: (json['items'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(DiscoveryQuestCard.fromJson)
            .toList(),
        journeys: (json['journeys'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(JourneyProgress.fromJson)
            .toList(),
      );
}

class JourneyProgress {
  const JourneyProgress({
    required this.id,
    required this.name,
    required this.description,
    required this.totalQuests,
    required this.completedQuests,
    this.countryName,
  });

  final String id;
  final String name;
  final String description;
  final int totalQuests;
  final int completedQuests;
  final String? countryName;

  factory JourneyProgress.fromJson(Map<String, dynamic> json) =>
      JourneyProgress(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        totalQuests: (json['totalQuests'] as num?)?.toInt() ?? 0,
        completedQuests: (json['completedQuests'] as num?)?.toInt() ?? 0,
        countryName: json['countryName'] as String?,
      );
}
