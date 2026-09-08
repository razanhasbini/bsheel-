import 'dart:typed_data';
import 'package:app_models/app_models.dart';

abstract class ProfileRepository {
  Future<ProfileModel?> getProfile(String userId);

  /// Exact, case-insensitive username lookup. Returns null when no profile
  /// owns the name. Used by @mention navigation, which must not guess.
  Future<ProfileModel?> getProfileByUsername(String username);
  Future<List<ProfileModel>> listProfiles({int limit});
  Future<ProfileModel> createProfile(ProfileModel profile);
  Future<ProfileModel> updateProfile(ProfileModel profile);
  Future<String> uploadAvatar(String userId, Uint8List bytes, String fileName);
  Future<void> deleteAvatar(String userId, {String? avatarUrl});
}
