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
  double get fraction => total == 0 ? 0 : (discovered / total).clamp(0, 1);
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
      this.questCount = 0});
  final String id, countryCode, name, description, city, category;
  final double latitude, longitude;

  /// Geofence radius the network checks presence against, in metres.
  final int radiusM;

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
      questCount: (j['quest_count'] as num?)?.toInt() ?? 0);
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
