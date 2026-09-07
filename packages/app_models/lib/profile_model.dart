import 'package:supabase_contracts/supabase_contracts.dart';

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
    this.level = 1,
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
      xp: _toInt(json[ProfileColumns.xp]),
      level: _toInt(json[ProfileColumns.level], defaultValue: 1),
      questsCompleted: _toInt(json[ProfileColumns.questsCompleted]),
      createdAt: DateTime.parse(json[ProfileColumns.createdAt] as String),
      updatedAt: json[ProfileColumns.updatedAt] != null
          ? DateTime.parse(json[ProfileColumns.updatedAt] as String)
          : null,
      profileCompleted: json[ProfileColumns.profileCompleted] as bool? ?? false,
      ageVerified: json[ProfileColumns.ageVerified] as bool? ?? false,
      analyticsConsentAt: json[ProfileColumns.analyticsConsentAt] != null
          ? DateTime.parse(json[ProfileColumns.analyticsConsentAt] as String)
          : null,
    );
  }

  static int _toInt(dynamic value, {int defaultValue = 0}) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? defaultValue;
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
}
