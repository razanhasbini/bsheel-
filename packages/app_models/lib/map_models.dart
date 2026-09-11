class MapCountry {
  const MapCountry(
      {required this.code,
      required this.name,
      required this.geometryId,
      required this.total,
      required this.discovered,
      required this.confirmed,
      required this.saved});
  final String code, name, geometryId;
  final int total, discovered, confirmed, saved;

  /// Exploration: approved proof at unique places over published places —
  /// the same arithmetic as `map/progress/me`. Pending proof moves nothing.
  double get fraction => total == 0 ? 0 : (confirmed / total).clamp(0, 1);
  factory MapCountry.fromJson(Map<String, dynamic> j) => MapCountry(
      code: j['code'] as String,
      name: j['name'] as String,
      geometryId: j['geometry_id'] as String,
      total: (j['total'] as num).toInt(),
      discovered: (j['discovered'] as num).toInt(),
      confirmed: (j['confirmed'] as num).toInt(),
      saved: (j['saved'] as num).toInt());
}

/// A published destination as the map shows it to one user.
///
/// A [locked] place is a hidden one this user has not uncovered yet: the
/// server withholds its name and blurs its position to about a kilometre, so
/// the pin marks the area worth exploring without giving the spot away.
/// Uncovering happens by earning an approved quest at any place nearby.
class MapPlace {
  const MapPlace(
      {required this.id,
      required this.countryCode,
      required this.name,
      required this.description,
      required this.city,
      required this.category,
      required this.latitude,
      required this.longitude,
      this.radiusM = 250,
      this.saved = false,
      this.discovered = false,
      this.confirmed = false,
      this.locked = false,
      this.questCount = 0,
      this.coverMediaUrl});
  final String id, countryCode, name, description, city, category;
  final double latitude, longitude;

  /// Geofence radius the network checks presence against, in metres.
  final int radiusM;

  /// The newest approved proof at the place, already signed for display —
  /// the pin's photo snippet. Null while locked or before anyone has been.
  final String? coverMediaUrl;

  /// [discovered] — this user has submitted proof at the place (pending or
  /// approved). [confirmed] — at least one of those was approved, which is
  /// what reveals the hidden places around it.
  final bool saved, discovered, confirmed, locked;
  final int questCount;
  factory MapPlace.fromJson(Map<String, dynamic> j) => MapPlace(
      id: j['id'] as String,
      countryCode: j['country_code'] as String,
      name: j['name'] as String,
      description: j['description'] as String? ?? '',
      city: j['city'] as String? ?? '',
      category: j['category'] as String,
      latitude: (j['latitude'] as num).toDouble(),
      longitude: (j['longitude'] as num).toDouble(),
      radiusM: (j['radius_m'] as num?)?.toInt() ?? 250,
      saved: j['saved'] == true,
      discovered: j['discovered'] == true,
      confirmed: j['confirmed'] == true,
      locked: j['locked'] == true,
      questCount: (j['quest_count'] as num?)?.toInt() ?? 0,
      coverMediaUrl: (j['cover_media_url'] as String?)?.isEmpty == true
          ? null
          : j['cover_media_url'] as String?);
}

/// Per-country exploration, from `GET map/progress/me`. Approved destination
/// quests at unique places over every published place in the country.
class MapCountryProgress {
  const MapCountryProgress(
      {required this.countryCode,
      required this.name,
      required this.geometryId,
      required this.exploredPlaces,
      required this.pendingPlaces,
      required this.totalPlaces,
      required this.percentage});
  final String countryCode, name, geometryId;
  final int exploredPlaces, pendingPlaces, totalPlaces;
  final double percentage;
  factory MapCountryProgress.fromJson(Map<String, dynamic> j) =>
      MapCountryProgress(
          countryCode: j['countryCode'] as String,
          name: j['name'] as String,
          geometryId: j['geometryId'] as String,
          exploredPlaces: (j['exploredPlaces'] as num).toInt(),
          pendingPlaces: (j['pendingPlaces'] as num?)?.toInt() ?? 0,
          totalPlaces: (j['totalPlaces'] as num).toInt(),
          percentage: (j['percentage'] as num).toDouble());
}

/// The one exploration model the map and the profile both display. Nothing
/// here is computed on the client.
class MapProgress {
  const MapProgress(
      {required this.worldExplored,
      required this.worldTotal,
      required this.worldPercentage,
      required this.countries});
  final int worldExplored, worldTotal;
  final double worldPercentage;
  final List<MapCountryProgress> countries;
  factory MapProgress.fromJson(Map<String, dynamic> j) {
    final world = Map<String, dynamic>.from(j['world'] as Map);
    return MapProgress(
        worldExplored: (world['exploredPlaces'] as num).toInt(),
        worldTotal: (world['totalPlaces'] as num).toInt(),
        worldPercentage: (world['percentage'] as num).toDouble(),
        countries: (j['countries'] as List)
            .map((c) => MapCountryProgress.fromJson(
                Map<String, dynamic>.from(c as Map)))
            .toList());
  }
}

/// A quest as the country discovery view shows it: enough to draw a snippet
/// and open the real quest, never the quest's secret content.
class MapQuestSnippet {
  const MapQuestSnippet(
      {required this.id,
      required this.title,
      required this.category,
      required this.difficulty,
      required this.xp,
      required this.hours,
      required this.requiresVerification,
      required this.placeId,
      required this.placeName,
      required this.city,
      required this.latitude,
      required this.longitude,
      required this.completions,
      required this.saves,
      required this.completed,
      required this.saved,
      this.coverMediaUrl});
  final String id, title, category, difficulty, placeId, placeName, city;
  final int xp, hours, completions, saves;
  final bool requiresVerification, completed, saved;
  final double latitude, longitude;
  final String? coverMediaUrl;
  factory MapQuestSnippet.fromJson(Map<String, dynamic> j) => MapQuestSnippet(
      id: j['id'] as String,
      title: j['title'] as String,
      category: j['category'] as String,
      difficulty: j['difficulty'] as String? ?? '',
      xp: (j['xp_reward'] as num).toInt(),
      hours: (j['duration_hours'] as num).toInt(),
      requiresVerification: j['requires_verification'] == true,
      placeId: j['place_id'] as String,
      placeName: j['place_name'] as String,
      city: j['city'] as String? ?? '',
      latitude: (j['latitude'] as num).toDouble(),
      longitude: (j['longitude'] as num).toDouble(),
      completions: (j['completions'] as num?)?.toInt() ?? 0,
      saves: (j['saves'] as num?)?.toInt() ?? 0,
      completed: j['completed'] == true,
      saved: j['saved'] == true,
      coverMediaUrl: (j['cover_media_url'] as String?)?.isEmpty == true
          ? null
          : j['cover_media_url'] as String?);
}

/// A journey through a country — "Discover Lebanon" — and how far along it
/// the player is.
class MapCollectionProgress {
  const MapCollectionProgress(
      {required this.id,
      required this.name,
      required this.description,
      required this.total,
      required this.completed});
  final String id, name, description;
  final int total, completed;
  factory MapCollectionProgress.fromJson(Map<String, dynamic> j) =>
      MapCollectionProgress(
          id: j['id'] as String,
          name: j['name'] as String,
          description: j['description'] as String? ?? '',
          total: (j['total'] as num).toInt(),
          completed: (j['completed'] as num).toInt());
}

/// `GET map/countries/{code}/discover` — a country as seen from anywhere.
class MapCountryDiscovery {
  const MapCountryDiscovery(
      {required this.code,
      required this.name,
      required this.exploredPlaces,
      required this.totalPlaces,
      required this.percentage,
      required this.trending,
      required this.discovery,
      required this.hiddenCount,
      required this.collections});
  final String code, name;
  final int exploredPlaces, totalPlaces, hiddenCount;
  final double percentage;
  final List<MapQuestSnippet> trending, discovery;
  final List<MapCollectionProgress> collections;
  factory MapCountryDiscovery.fromJson(Map<String, dynamic> j) {
    final country = Map<String, dynamic>.from(j['country'] as Map);
    List<MapQuestSnippet> snippets(String key) => (j[key] as List)
        .map((q) =>
            MapQuestSnippet.fromJson(Map<String, dynamic>.from(q as Map)))
        .toList();
    return MapCountryDiscovery(
        code: country['code'] as String,
        name: country['name'] as String,
        exploredPlaces: (country['exploredPlaces'] as num).toInt(),
        totalPlaces: (country['totalPlaces'] as num).toInt(),
        percentage: (country['percentage'] as num).toDouble(),
        trending: snippets('trending'),
        discovery: snippets('discovery'),
        hiddenCount: (j['hiddenCount'] as num?)?.toInt() ?? 0,
        collections: (j['collections'] as List)
            .map((c) => MapCollectionProgress.fromJson(
                Map<String, dynamic>.from(c as Map)))
            .toList());
  }
}

class MapQuest {
  const MapQuest(
      {required this.id,
      required this.title,
      required this.category,
      required this.xp,
      required this.hours,
      required this.unlocked,
      this.requiresVerification = false});
  final String id, title, category;
  final int xp, hours;

  /// Whether the quest can be started. Always true for a visible place since
  /// presence is judged when the proof is submitted, not before.
  final bool unlocked;

  /// Whether the network will be asked to confirm the player was at the
  /// place when their proof comes in.
  final bool requiresVerification;
  factory MapQuest.fromJson(Map<String, dynamic> j) => MapQuest(
      id: j['id'] as String,
      title: j['title'] as String,
      category: j['category'] as String,
      xp: (j['xp_reward'] as num).toInt(),
      hours: (j['duration_hours'] as num).toInt(),
      unlocked: j['unlocked'] == true,
      requiresVerification: j['requires_verification'] == true);
}

class MapPreview {
  const MapPreview({required this.id, required this.username});
  final String id, username;
  factory MapPreview.fromJson(Map<String, dynamic> j) =>
      MapPreview(id: j['id'] as String, username: j['username'] as String);
}

class MapPlaceDetail {
  const MapPlaceDetail(
      {required this.place, required this.quests, required this.previews});
  final MapPlace place;
  final List<MapQuest> quests;
  final List<MapPreview> previews;
  factory MapPlaceDetail.fromJson(Map<String, dynamic> j) => MapPlaceDetail(
      place: MapPlace.fromJson(j),
      quests: (j['quests'] as List)
          .map((q) => MapQuest.fromJson(Map<String, dynamic>.from(q as Map)))
          .toList(),
      previews: (j['previews'] as List)
          .map((p) => MapPreview.fromJson(Map<String, dynamic>.from(p as Map)))
          .toList());
}
