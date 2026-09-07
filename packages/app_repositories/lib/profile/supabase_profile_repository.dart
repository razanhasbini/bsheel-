import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import '../media/signed_media_urls.dart';
import 'profile_repository.dart';

/// Worker URL for R2 uploads.
const _workerUrl = WorkerUrls.r2Upload;

class SupabaseProfileRepository implements ProfileRepository {
  final SupabaseClient _client;
  SupabaseProfileRepository(this._client);

  // M10 (2026-05-17): whitelist columns. .select() with no args returns
  // every column in `profiles`, including any future PII-bearing field
  // (e.g. `phone_number`, `birthdate`). Listing explicitly is a thin
  // wall that catches a developer-added column from auto-leaking on
  // the leaderboard / profile screens.
  static const _publicProfileColumns =
      'id, username, display_name, avatar_url, bio, xp, level, '
      'quests_completed, profile_completed, created_at, updated_at';

  @override
  Future<List<ProfileModel>> listProfiles({int limit = 200}) async {
    final response = await _client
        .from(Tables.profiles)
        .select(_publicProfileColumns)
        .order(ProfileColumns.xp, ascending: false)
        .limit(limit);

    final profiles = (response as List<dynamic>)
        .map((row) => ProfileModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return Future.wait(profiles.map(_withSignedAvatar));
  }

  @override
  Future<ProfileModel?> getProfile(String userId) async {
    final data = await _client
        .from(Tables.profiles)
        .select(_publicProfileColumns)
        .eq(ProfileColumns.id, userId)
        .maybeSingle();
    if (data == null) return null;
    return _withSignedAvatar(ProfileModel.fromJson(data));
  }

  @override
  Future<ProfileModel> createProfile(ProfileModel profile) async {
    final data = await _client
        .from(Tables.profiles)
        .insert({
          ProfileColumns.id: profile.id,
          ProfileColumns.username: profile.username,
          ProfileColumns.displayName: profile.displayName,
          if (profile.avatarUrl != null)
            ProfileColumns.avatarUrl: profile.avatarUrl,
          if (profile.bio != null) ProfileColumns.bio: profile.bio,
        })
        .select()
        .single();
    return _withSignedAvatar(ProfileModel.fromJson(data));
  }

  @override
  Future<ProfileModel> updateProfile(ProfileModel profile) async {
    final data = await _client
        .from(Tables.profiles)
        .update({
          ProfileColumns.username: profile.username,
          ProfileColumns.displayName: profile.displayName,
          ProfileColumns.avatarUrl: profile.avatarUrl,
          ProfileColumns.bio: profile.bio,
          if (profile.profileCompleted) ProfileColumns.profileCompleted: true,
        })
        .eq(ProfileColumns.id, profile.id)
        .select()
        .single();
    return _withSignedAvatar(ProfileModel.fromJson(data));
  }

  Future<ProfileModel> _withSignedAvatar(ProfileModel profile) async {
    final avatarUrl = await SignedMediaUrls.signNullable(
      _client,
      profile.avatarUrl,
    );
    return profile.copyWith(avatarUrl: avatarUrl);
  }

  @override
  Future<String> uploadAvatar(
    String userId,
    Uint8List bytes,
    String fileName,
  ) async {
    // Derive the type from the BYTES, not the filename.
    //
    // The caller (edit_profile_page) runs ExifStripper.strip() first,
    // which re-encodes JPEG *and PNG* input to JPEG while keeping the
    // picker's original `photo.png` name. Trusting the extension there
    // declared image/png over JPEG bytes, and the R2 worker's magic-byte
    // check rejected the upload with 400 "File content does not match
    // Content-Type header" — i.e. picking a PNG avatar always failed.
    //
    // headerBytes takes priority over the extension in `lookupMimeType`,
    // so this now follows whatever the bytes actually are, and the stored
    // key's extension is derived from that same answer.
    final detected = lookupMimeType(
      fileName,
      headerBytes: bytes.take(32).toList(),
    );
    final contentType =
        WorkerMediaTypes.image.contains(detected) ? detected! : 'image/jpeg';
    final ext = switch (contentType) {
      'image/png' => 'png',
      'image/webp' => 'webp',
      'image/gif' => 'gif',
      _ => 'jpg',
    };

    final uploadPath = 'avatars/$userId/avatar.$ext';
    final session = _client.auth.currentSession;
    if (session == null) {
      throw const StorageException('Missing auth session for upload.');
    }

    final uri = Uri.parse('$_workerUrl/$uploadPath');
    final response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': contentType,
      },
      body: bytes,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StorageException(
        'Avatar upload failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['url'] as String;
  }

  @override
  Future<void> deleteAvatar(String userId, {String? avatarUrl}) async {
    final session = _client.auth.currentSession;
    if (session == null) return;

    // If we have the stored avatar reference, extract the R2 key and make a single
    // DELETE request instead of brute-forcing every possible extension.
    final avatarKey = _mediaKeyFromReference(avatarUrl);
    if (avatarKey != null) {
      final uri = Uri.parse('$_workerUrl/$avatarKey');
      await http.delete(
        uri,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      return;
    }

    // Fallback: if no avatarUrl provided or it doesn't match the worker,
    // delete the most common extension only.
    final uri = Uri.parse('$_workerUrl/avatars/$userId/avatar.jpg');
    await http.delete(
      uri,
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
    );
  }

  String? _mediaKeyFromReference(String? value) {
    final raw = value?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('avatars/')) return raw;

    final parsed = Uri.tryParse(raw);
    if (parsed == null) return null;
    final workerHost = Uri.parse(_workerUrl).host;
    if (parsed.host == workerHost) {
      final path = parsed.path.replaceFirst(RegExp(r'^/+media/+'), '');
      if (path.startsWith('avatars/')) return path;
    }
    return null;
  }
}
