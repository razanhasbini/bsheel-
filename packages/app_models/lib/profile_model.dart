import 'package:supabase_contracts/supabase_contracts.dart';

import 'src/json_coercions.dart';

class ProfileModel {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final int xp;
  final int level;
  final int questsCompleted;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool profileCompleted;

  /// Migration 0142: signup self-attestation that the user is 13+.
  final bool ageVerified;

  /// Migration 0142: timestamp the user accepted analytics opt-in.
  /// NULL = no consent yet — keep Mixpanel disabled until non-null.
  final DateTime? analyticsConsentAt;

  const ProfileModel({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    this.xp = 0,
    this.level = defaultLevel,
    this.questsCompleted = 0,
    required this.createdAt,
    this.updatedAt,
    this.profileCompleted = false,
    this.ageVerified = false,
    this.analyticsConsentAt,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json[ProfileColumns.id] as String,
      username: json[ProfileColumns.username] as String,
      displayName: json[ProfileColumns.displayName] as String,
      avatarUrl: json[ProfileColumns.avatarUrl] as String?,
      bio: json[ProfileColumns.bio] as String?,
      xp: coerceInt(json[ProfileColumns.xp]),
      level: coerceInt(json[ProfileColumns.level], defaultValue: defaultLevel),
      questsCompleted: coerceInt(json[ProfileColumns.questsCompleted]),
      createdAt: coerceTimestamp(json[ProfileColumns.createdAt]),
      updatedAt: coerceNullableTimestamp(json[ProfileColumns.updatedAt]),
      profileCompleted: coerceBool(
        json[ProfileColumns.profileCompleted],
        ifMissing: false,
      ),
      ageVerified: coerceBool(
        json[ProfileColumns.ageVerified],
        ifMissing: false,
      ),
      analyticsConsentAt: coerceNullableTimestamp(
        json[ProfileColumns.analyticsConsentAt],
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ProfileColumns.id: id,
      ProfileColumns.username: username,
      ProfileColumns.displayName: displayName,
      ProfileColumns.avatarUrl: avatarUrl,
      ProfileColumns.bio: bio,
      ProfileColumns.xp: xp,
      ProfileColumns.level: level,
      ProfileColumns.questsCompleted: questsCompleted,
      ProfileColumns.createdAt: createdAt.toIso8601String(),
      ProfileColumns.updatedAt: updatedAt?.toIso8601String(),
      ProfileColumns.profileCompleted: profileCompleted,
      ProfileColumns.ageVerified: ageVerified,
      ProfileColumns.analyticsConsentAt: analyticsConsentAt?.toIso8601String(),
    };
  }

  static const _sentinel = Object();

  ProfileModel copyWith({
    String? id,
    String? username,
    String? displayName,
    Object? avatarUrl = _sentinel,
    Object? bio = _sentinel,
    int? xp,
    int? level,
    int? questsCompleted,
    DateTime? createdAt,
    Object? updatedAt = _sentinel,
    bool? profileCompleted,
    bool? ageVerified,
    Object? analyticsConsentAt = _sentinel,
  }) {
    return ProfileModel(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl == _sentinel ? this.avatarUrl : avatarUrl as String?,
      bio: bio == _sentinel ? this.bio : bio as String?,
      xp: xp ?? this.xp,
      level: level ?? this.level,
      questsCompleted: questsCompleted ?? this.questsCompleted,
      createdAt: createdAt ?? this.createdAt,
      updatedAt:
          updatedAt == _sentinel ? this.updatedAt : updatedAt as DateTime?,
      profileCompleted: profileCompleted ?? this.profileCompleted,
      ageVerified: ageVerified ?? this.ageVerified,
      analyticsConsentAt: analyticsConsentAt == _sentinel
          ? this.analyticsConsentAt
          : analyticsConsentAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ProfileModel &&
        other.id == id &&
        other.username == username &&
        other.displayName == displayName &&
        other.avatarUrl == avatarUrl &&
        other.bio == bio &&
        other.xp == xp &&
        other.level == level &&
        other.questsCompleted == questsCompleted &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.profileCompleted == profileCompleted &&
        other.ageVerified == ageVerified &&
        other.analyticsConsentAt == analyticsConsentAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        username,
        displayName,
        avatarUrl,
        bio,
        xp,
        level,
        questsCompleted,
        createdAt,
        updatedAt,
        profileCompleted,
        ageVerified,
        analyticsConsentAt,
      );
}
