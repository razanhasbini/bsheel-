import 'dart:typed_data';

import 'package:app_models/app_models.dart';

import '../api/api_client.dart';
import '../media/api_media_signer.dart';
import '../media/api_media_uploader.dart';
import 'profile_repository.dart';

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(this._client)
      : _media = ApiMediaSigner(_client),
        _uploader = ApiMediaUploader(_client);

  final ApiClient _client;
  final ApiMediaSigner _media;
  final ApiMediaUploader _uploader;

  @override
  Future<StreakModel> getStreak({String? userId}) async {
    // Same endpoint shape as the map's discovery totals: one server figure,
    // read for self or for another profile, so the two can never disagree.
    return StreakModel.fromJson(
      apiObject(await _client.get(
          userId == null ? 'profiles/me/streak' : 'profiles/$userId/streak')),
    );
  }

  @override
  Future<ProfileModel?> getProfile(String userId) async {
    try {
      return _signed(
        ProfileModel.fromJson(
          apiObject(await _client.get('profiles/$userId')),
        ),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<ProfileModel?> getProfileByUsername(String username) async {
    final name = username.trim();
    if (name.isEmpty) return null;
    try {
      return _signed(
        ProfileModel.fromJson(
          apiObject(await _client.get('profiles/by-username/$name')),
        ),
      );
    } on ApiException catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<List<ProfileModel>> listProfiles({int limit = 200}) async {
    final rows = apiObjectList(
      await _client.get('profiles', query: {'limit': limit}),
    );
    return Future.wait(rows.map((row) => _signed(ProfileModel.fromJson(row))));
  }

  @override
  Future<ProfileModel> createProfile(ProfileModel profile) =>
      updateProfile(profile);

  @override
  Future<ProfileModel> updateProfile(ProfileModel profile) async {
    final row = apiObject(
      await _client.patch(
        'profiles/me',
        body: {
          'username': profile.username,
          'displayName': profile.displayName,
          'avatarUrl': _media.storageReference(profile.avatarUrl),
          'bio': profile.bio,
          if (profile.profileCompleted) 'profileCompleted': true,
        },
      ),
    );
    return _signed(ProfileModel.fromJson(row));
  }

  @override
  Future<String> uploadAvatar(
    String userId,
    Uint8List bytes,
    String fileName,
  ) =>
      _uploader.upload(
        kind: 'avatar',
        bytes: bytes,
        fileName: fileName,
        fallbackMediaType: 'image',
      );

  @override
  Future<void> deleteAvatar(String userId, {String? avatarUrl}) async {
    final reference = _media.storageReference(avatarUrl);
    if (reference == null || reference.trim().isEmpty) return;
    await _client.delete('media/objects', body: {'key': reference});
  }

  Future<ProfileModel> _signed(ProfileModel profile) async => profile.copyWith(
        avatarUrl: await _media.signNullable(profile.avatarUrl),
      );
}
