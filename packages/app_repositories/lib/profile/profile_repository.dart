import 'dart:typed_data';
import 'package:app_models/app_models.dart';

/// A user's streak, as the server computes it.
class StreakModel {
  final int current;
  final int longest;
  final String? lastDay;

  /// True when the streak is alive but expires at the end of today, which is
  /// the only state the daily reminder is about.
  final bool atRisk;

  const StreakModel({
    required this.current,
    required this.longest,
    required this.lastDay,
    required this.atRisk,
  });

  const StreakModel.zero()
      : current = 0,
        longest = 0,
        lastDay = null,
        atRisk = false;

  factory StreakModel.fromJson(Map<String, dynamic> json) => StreakModel(
        current: (json['current'] as num?)?.toInt() ?? 0,
        longest: (json['longest'] as num?)?.toInt() ?? 0,
        lastDay: json['lastDay'] as String?,
        atRisk: json['atRisk'] as bool? ?? false,
      );
}

abstract class ProfileRepository {
  Future<ProfileModel?> getProfile(String userId);

  /// Streak for [userId], or the caller's own when null (#46).
  ///
  /// Server-derived: consecutive UTC days with an approved submission, keyed
  /// on the day the work was submitted. Never computed on the client from a
  /// paginated history page — that was the mistake #49 calls out for
  /// discovery percentages, and it is the same mistake here.
  Future<StreakModel> getStreak({String? userId});

  /// Exact, case-insensitive username lookup. Returns null when no profile
  /// owns the name. Used by @mention navigation, which must not guess.
  Future<ProfileModel?> getProfileByUsername(String username);
  Future<List<ProfileModel>> listProfiles({int limit});
  Future<ProfileModel> createProfile(ProfileModel profile);
  Future<ProfileModel> updateProfile(ProfileModel profile);

  /// Records the one-time 13+ confirmation for the signed-in account.
  ///
  /// Its own call rather than an [updateProfile] round-trip on purpose:
  /// that projection re-sends the avatar key, which the server re-verifies
  /// against `media_objects` — and an imported account whose avatar predates
  /// that table would be refused, leaving the age prompt impossible to
  /// dismiss. This sends the flag and nothing else.
  Future<void> confirmAge();
  Future<String> uploadAvatar(String userId, Uint8List bytes, String fileName);
  Future<void> deleteAvatar(String userId, {String? avatarUrl});
}
