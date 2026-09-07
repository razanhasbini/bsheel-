import 'dart:convert';

import '../api/api_client.dart';

class ApiMediaSigner {
  ApiMediaSigner(this._client);

  final ApiClient _client;
  final Map<String, String> _signedToRaw = {};

  Future<Map<String, String>> signMany(Iterable<String> rawValues) async {
    final values = rawValues
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (values.isEmpty) return const {};
    try {
      final data = apiObject(await _client.post('media/sign', body: {
        'urls': values,
      },),);
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
            values.map((value) => signed[value] ?? value).toList(),);
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
