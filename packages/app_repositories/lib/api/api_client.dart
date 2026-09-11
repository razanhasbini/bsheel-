import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiTokenPair {
  const ApiTokenPair({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final int expiresIn;

  factory ApiTokenPair.fromJson(Map<String, dynamic> json) => ApiTokenPair(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        expiresIn: (json['expiresIn'] as num).toInt(),
      );
}

abstract class ApiTokenStore {
  Future<ApiTokenPair?> read();
  Future<void> write(ApiTokenPair tokens);
  Future<void> clear();
}

/// Useful for tests. Production apps should use a platform-backed secure store.
class InMemoryApiTokenStore implements ApiTokenStore {
  ApiTokenPair? _tokens;

  @override
  Future<ApiTokenPair?> read() async => _tokens;

  @override
  Future<void> write(ApiTokenPair tokens) async => _tokens = tokens;

  @override
  Future<void> clear() async => _tokens = null;
}

class ApiException implements Exception {
  const ApiException({
    required this.statusCode,
    required this.code,
    required this.message,
    this.requestId,
    this.details,
  });

  final int statusCode;
  final String code;
  final String message;
  final String? requestId;
  final Object? details;

  @override
  String toString() => 'ApiException($statusCode, $code, $message)';
}

/// Versioned REST transport for the Nest backend.
///
/// It understands the API response envelope, applies bounded timeouts, and
/// serializes refresh-token rotation so concurrent 401 responses cannot reuse
/// the same single-use refresh token.
class ApiClient {
  ApiClient({
    required Uri baseUrl,
    required ApiTokenStore tokenStore,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  })  : baseUrl = _normalizeBaseUrl(baseUrl),
        tokenStore = tokenStore,
        _http = httpClient ?? http.Client();

  final Uri baseUrl;
  final ApiTokenStore tokenStore;
  final Duration timeout;

  /// Called once when a refresh fails and the stored session is discarded.
  ///
  /// Without it the tokens vanish and nothing else notices: the router still
  /// believes the user is signed in, so it holds them on a Home screen where
  /// every request 401s and every section renders empty. Being silently
  /// stranded there is worse than being asked to sign in again.
  ///
  /// Assigned after construction rather than passed in, because the thing
  /// that handles it — the auth repository — is built from the same bundle
  /// as this client and cannot exist yet while this is being constructed.
  void Function()? onSessionExpired;
  final http.Client _http;
  Future<bool>? _refreshInFlight;

  Future<Object?> get(
    String path, {
    Map<String, Object?> query = const {},
    bool authenticated = true,
  }) =>
      request('GET', path, query: query, authenticated: authenticated);

  Future<Object?> post(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    bool authenticated = true,
  }) =>
      request(
        'POST',
        path,
        body: body,
        query: query,
        authenticated: authenticated,
      );

  Future<Object?> put(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    bool authenticated = true,
  }) =>
      request(
        'PUT',
        path,
        body: body,
        query: query,
        authenticated: authenticated,
      );

  Future<Object?> patch(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    bool authenticated = true,
  }) =>
      request(
        'PATCH',
        path,
        body: body,
        query: query,
        authenticated: authenticated,
      );

  Future<Object?> delete(
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    bool authenticated = true,
  }) =>
      request(
        'DELETE',
        path,
        body: body,
        query: query,
        authenticated: authenticated,
      );

  Future<Object?> request(
    String method,
    String path, {
    Object? body,
    Map<String, Object?> query = const {},
    bool authenticated = true,
  }) async {
    var response = await _send(
      method,
      path,
      body: body,
      query: query,
      authenticated: authenticated,
    );
    if (authenticated && response.statusCode == 401 && await _refresh()) {
      response = await _send(
        method,
        path,
        body: body,
        query: query,
        authenticated: true,
      );
    }
    return _decode(response);
  }

  Future<void> putBytes(
    Uri uri,
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final response =
          await _http.put(uri, headers: headers, body: bytes).timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          statusCode: response.statusCode,
          code: 'UPLOAD_FAILED',
          message: 'Media upload failed (${response.statusCode}).',
        );
      }
    } on TimeoutException {
      throw const ApiException(
        statusCode: 0,
        code: 'NETWORK_TIMEOUT',
        message: 'The upload timed out. Please try again.',
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: error.message,
      );
    }
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Object? body,
    required Map<String, Object?> query,
    required bool authenticated,
  }) async {
    final uri = _uri(path, query);
    final request = http.Request(method, uri)
      ..headers['accept'] = 'application/json';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    if (authenticated) {
      final tokens = await tokenStore.read();
      if (tokens != null) {
        request.headers['authorization'] = 'Bearer ${tokens.accessToken}';
      }
    }
    try {
      final streamed = await _http.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const ApiException(
        statusCode: 0,
        code: 'NETWORK_TIMEOUT',
        message: 'The request timed out. Please try again.',
      );
    } on http.ClientException catch (error) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: error.message,
      );
    }
  }

  Future<bool> _refresh() {
    final active = _refreshInFlight;
    if (active != null) return active;
    final operation = _performRefresh();
    _refreshInFlight = operation;
    return operation.whenComplete(() => _refreshInFlight = null);
  }

  /// Rotates the current refresh token outside the request retry path.
  ///
  /// Realtime transports use this after a Socket.IO authentication rejection,
  /// where there is no HTTP 401 for [request] to observe. Rotation remains
  /// serialized with normal API retries through the same in-flight future.
  Future<bool> refreshSession() => _refresh();

  Future<bool> _performRefresh() async {
    final current = await tokenStore.read();
    // Nothing to refresh with. The session is already gone, so say so —
    // returning quietly leaves the app holding a dead access token and
    // 401ing every read while it renders whatever it last cached.
    if (current == null) {
      onSessionExpired?.call();
      return false;
    }
    try {
      final response = await _send(
        'POST',
        'auth/refresh',
        body: {'refreshToken': current.refreshToken},
        query: const {},
        authenticated: false,
      );
      final data = _decode(response);
      if (data is! Map) {
        // A 2xx that is not a token pair is a broken contract, not a
        // transient fault, and retrying it forever is worse than stopping.
        await _endSession();
        return false;
      }
      await tokenStore.write(
        ApiTokenPair.fromJson(Map<String, dynamic>.from(data)),
      );
      return true;
    } on ApiException catch (error) {
      // A refused refresh token is dead: revoked, rotated, or its account
      // deleted. Anything else — a 500, a proxy hiccup — is the server
      // having a bad moment, and signing someone out over that loses their
      // place for no reason. Distinguishing the two is the whole point:
      // clearing on every failure logs people out on a flaky connection,
      // and clearing on none is how a dead session survives a refresh and
      // shows stale screens forever.
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _endSession();
      }
      return false;
    } catch (_) {
      // Network-shaped: no response at all. Keep the session; the caller
      // sees the failure and the next attempt may well succeed.
      return false;
    }
  }

  /// Discards the stored session and tells the app, exactly once per failure.
  Future<void> _endSession() async {
    await tokenStore.clear();
    onSessionExpired?.call();
  }

  Object? _decode(http.Response response) {
    Map<String, dynamic>? envelope;
    if (response.bodyBytes.isNotEmpty) {
      try {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is Map) envelope = Map<String, dynamic>.from(decoded);
      } on FormatException {
        throw ApiException(
          statusCode: response.statusCode,
          code: 'INVALID_API_RESPONSE',
          message: 'The server returned an invalid response.',
        );
      }
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return envelope?['data'];
    }
    final error = envelope?['error'];
    final errorMap = error is Map ? Map<String, dynamic>.from(error) : null;
    final meta = envelope?['meta'];
    final metaMap = meta is Map ? Map<String, dynamic>.from(meta) : null;
    throw ApiException(
      statusCode: response.statusCode,
      code: errorMap?['code']?.toString() ?? 'HTTP_${response.statusCode}',
      message: errorMap?['message']?.toString() ?? 'Request failed.',
      requestId: metaMap?['requestId']?.toString(),
      details: errorMap?['details'],
    );
  }

  Uri _uri(String path, Map<String, Object?> query) {
    final cleanPath = path.replaceFirst(RegExp(r'^/+'), '');
    final values = <String, String>{};
    for (final entry in query.entries) {
      if (entry.value != null) values[entry.key] = entry.value.toString();
    }
    return baseUrl.resolve(cleanPath).replace(
          queryParameters: values.isEmpty ? null : values,
        );
  }

  void close() => _http.close();

  static Uri _normalizeBaseUrl(Uri value) {
    final path = value.path.endsWith('/') ? value.path : '${value.path}/';
    return value.replace(path: path, query: null, fragment: null);
  }
}

Map<String, dynamic> apiObject(Object? value) {
  if (value is! Map) {
    throw const ApiException(
      statusCode: 0,
      code: 'INVALID_API_DATA',
      message: 'Expected an object from the API.',
    );
  }
  return Map<String, dynamic>.from(value);
}

List<Map<String, dynamic>> apiObjectList(Object? value) {
  if (value is! List) {
    throw const ApiException(
      statusCode: 0,
      code: 'INVALID_API_DATA',
      message: 'Expected a list from the API.',
    );
  }
  return value
      .map((item) => Map<String, dynamic>.from(item as Map))
      .toList(growable: false);
}
