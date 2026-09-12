import 'dart:convert';

import '../api/api_client.dart';

class ApiMediaSigner {
  ApiMediaSigner(this._client);

  final ApiClient _client;
  final Map<String, String> _signedToRaw = {};

  /// The server's `ArrayMaxSize` on `POST media/sign`. Exceeding it is a 400
  /// for the WHOLE request, not a truncation — and `signMany` answers a
  /// failure with an empty map, so one oversized batch leaves every caller
  /// with unsigned keys and every tile drawing its placeholder. That is what
  /// the map's moments layer hit the moment it drew more tiles: forty
  /// moments carry a media key, an avatar and a poster, which is 120.
  ///
  /// Kept just under the server's 100 so a caller cannot be the thing that
  /// has to know the limit.
  static const int _batchSize = 90;

  Future<Map<String, String>> signMany(Iterable<String> rawValues) async {
    final values = rawValues
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (values.isEmpty) return const {};

    final result = <String, String>{};
    for (var start = 0; start < values.length; start += _batchSize) {
      final end =
          start + _batchSize < values.length ? start + _batchSize : values.length;
      // Each chunk stands alone: one failing batch costs its own keys, not
      // every key in the request. A screen with a hundred images should lose
      // the ones it could not sign, never all of them.
      result.addAll(await _signChunk(values.sublist(start, end)));
    }
    return result;
  }

  Future<Map<String, String>> _signChunk(List<String> values) async {
    try {
      final data = apiObject(
        await _client.post(
          'media/sign',
          body: {
            'urls': values,
          },
        ),
      );
      final urls = data['urls'];
      if (urls is! Map) return const {};
      final result = urls.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
      for (final entry in result.entries) {
        _signedToRaw[entry.value] = entry.key;
      }
      return result;
    } on ApiException {
      return const {};
    }
  }

  Future<String?> signNullable(String? raw) async {
    if (raw == null || raw.trim().isEmpty) return raw;
    final signed = await signMany([raw]);
    return signed[raw] ?? raw;
  }

  Future<String> signJsonOrSingle(String raw) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;
    if (trimmed.startsWith('[')) {
      try {
        final values = List<String>.from(jsonDecode(trimmed) as List);
        final signed = await signMany(values);
        return jsonEncode(
          values.map((value) => signed[value] ?? value).toList(),
        );
      } catch (_) {
        // Treat malformed legacy JSON as one opaque media value.
      }
    }
    final signed = await signMany([raw]);
    return signed[raw] ?? raw;
  }

  String? storageReference(String? value) =>
      value == null ? null : _signedToRaw[value] ?? value;
}
