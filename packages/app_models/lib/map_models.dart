import 'dart:math';

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

/// One piece of proof standing at a place, as the place sheet shows it.
///
/// Carries its media so the sheet can draw the picture rather than a play
/// button: this is what a moment tile's "+N more" opens into, and a wall of
/// identical icons answers none of what somebody tapped it to see.
class MapPreview {
  const MapPreview({
    required this.id,
    required this.username,
    this.mediaUrl = '',
    this.mediaType = 'image',
    this.questId = '',
    this.questTitle = '',
  });
  final String id, username;

  /// Signed for display by the repository, like every other media URL.
  final String mediaUrl;

  /// `image` or `video`.
  final String mediaType;

  /// The quest this proof was submitted for — so the sheet can offer it.
  final String questId, questTitle;

  bool get isVideo => mediaType == 'video';

  factory MapPreview.fromJson(Map<String, dynamic> j) => MapPreview(
      id: j['id'] as String,
      username: j['username'] as String,
      mediaUrl: j['media_url'] as String? ?? '',
      mediaType: j['media_type'] as String? ?? 'image',
      questId: j['quest_id'] as String? ?? '',
      questTitle: j['quest_title'] as String? ?? '');
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

/// One piece of proof from the feed, pinned where it happened — the map's
/// moments layer (Snap/Instagram-map shaped).
///
/// Everything here is already public on the feed; the map is a second way
/// to come across it, not a second audience for it.
///
/// [latitude]/[longitude] are the **place's** coordinates, not the
/// photograph's: Bsheel knows which place a quest belonged to, and does not
/// know — or want to publish — where somebody stood. Several moments at one
/// place therefore share a point, which is what [scatterOffset] exists for:
/// the map spreads the tiles deterministically inside [radiusM] so they can
/// be told apart, without either side pretending the spread is data.
class MapMoment {
  const MapMoment({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    required this.submittedAt,
    required this.netScore,
    required this.caption,
    required this.questId,
    required this.questTitle,
    required this.questCategory,
    required this.placeId,
    required this.placeName,
    required this.city,
    required this.countryCode,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    required this.userId,
    required this.username,
    this.avatarUrl,
    this.moreCount = 0,
    this.questCount = 0,
  });

  /// The submission id — also the route parameter for the post itself.
  final String id;

  /// Signed for display by the repository, exactly as the feed signs its
  /// media. Empty when signing failed, which the tile renders as a
  /// placeholder rather than a broken image.
  final String mediaUrl;

  /// `image` or `video`.
  final String mediaType;
  final DateTime submittedAt;
  final int netScore;
  final String caption;
  final String questId, questTitle, questCategory;
  final String placeId, placeName, city, countryCode;
  final double latitude, longitude;
  final int radiusM;
  final String userId, username;

  /// The author's avatar, signed for display like the media. Null when they
  /// have not set one — the tile falls back to their initial.
  final String? avatarUrl;

  /// How much else is standing at this place, drawn as "+N more" under the
  /// tile. The map shows ONE piece of proof per place; this is the rest of
  /// it, counted rather than drawn, so a busy landmark cannot bury the
  /// board. Opening the place is where the full set lives.
  final int moreCount;

  /// Active, non-hidden quests on offer at this place. The tile says there
  /// is something to *do* here, not only something to look at — which is
  /// the whole reason the proof is on the map.
  final int questCount;

  bool get isVideo => mediaType == 'video';

  factory MapMoment.fromJson(Map<String, dynamic> j) => MapMoment(
        id: j['id'] as String,
        mediaUrl: j['media_url'] as String? ?? '',
        mediaType: j['media_type'] as String? ?? 'image',
        submittedAt:
            DateTime.tryParse(j['submitted_at'] as String? ?? '')?.toLocal() ??
                DateTime.now(),
        // bigint, and node-postgres hands bigints back as strings rather
        // than numbers — a plain `as num` cast throws on the real response.
        netScore: switch (j['net_score']) {
          final num value => value.toInt(),
          final String value => int.tryParse(value) ?? 0,
          _ => 0,
        },
        caption: j['caption'] as String? ?? '',
        questId: j['quest_id'] as String,
        questTitle: j['quest_title'] as String? ?? '',
        questCategory: j['quest_category'] as String? ?? '',
        placeId: j['place_id'] as String,
        placeName: j['place_name'] as String? ?? '',
        city: j['city'] as String? ?? '',
        countryCode: j['country_code'] as String? ?? '',
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        radiusM: (j['radius_m'] as num?)?.toInt() ?? 250,
        userId: j['user_id'] as String,
        username: j['username'] as String? ?? '',
        avatarUrl: (j['avatar_url'] as String?)?.isEmpty == true
            ? null
            : j['avatar_url'] as String?,
        moreCount: (j['more_count'] as num?)?.toInt() ?? 0,
        questCount: (j['quest_count'] as num?)?.toInt() ?? 0,
      );

  /// Where to draw this moment's tile, in metres east and north of the
  /// place's own point.
  ///
  /// Deterministic in the submission id, so a tile keeps its spot across
  /// rebuilds, pans and app restarts — a tile that wandered on every frame
  /// would read as live movement, which is the one thing this must never
  /// suggest. Kept inside 70% of the place radius (and never more than 120 m,
  /// so a 10 km geofence does not fling proof across a city) and bounded
  /// below so two moments cannot land on the same pixel.
  ///
  /// The square root on the radius is what spreads them evenly over the
  /// disc; without it they crowd the centre.
  ({double east, double north}) get scatterOffset {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash = (hash ^ unit) * 0x01000193 & 0x7fffffff;
    }
    final angle = (hash % 3600) / 3600 * 2 * pi;
    final spread = (radiusM * 0.7).clamp(20.0, 120.0);
    // 0.35..1.0 of the spread: never on top of the pin, never at the rim.
    // The square root is what spreads them evenly over the disc; without it
    // they crowd the centre.
    final distance = spread * (0.35 + 0.65 * sqrt(((hash >> 12) % 1000) / 1000));
    return (east: distance * cos(angle), north: distance * sin(angle));
  }
}
