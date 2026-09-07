import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api_client.dart';

/// Keychain/Keystore-backed persistence for Nest access and refresh tokens.
///
/// A single JSON value prevents readers from observing a half-written token
/// rotation. Separate namespaces let the mobile and admin apps coexist on a
/// development device without sharing credentials.
class SecureApiTokenStore implements ApiTokenStore {
  const SecureApiTokenStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    String namespace = 'bsheel',
  })  : _storage = storage,
        _key = '$namespace.nest.auth.tokens.v1';

  final FlutterSecureStorage _storage;
  final String _key;

  @override
  Future<ApiTokenPair?> read() async {
    final encoded = await _storage.read(key: _key);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final value = jsonDecode(encoded);
      if (value is! Map) throw const FormatException('Token value is not an object');
      return ApiTokenPair.fromJson(Map<String, dynamic>.from(value));
    } on FormatException {
      await clear();
      return null;
    } on TypeError {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(ApiTokenPair tokens) => _storage.write(
        key: _key,
        value: jsonEncode({
          'accessToken': tokens.accessToken,
          'refreshToken': tokens.refreshToken,
          'expiresIn': tokens.expiresIn,
        }),
      );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
