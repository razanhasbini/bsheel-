import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Exchanges private R2 object keys or legacy public R2 URLs for short-lived
/// signed worker URLs. If signing fails, callers get the original values back
/// so the UI degrades gracefully while deployments roll forward.
class SignedMediaUrls {
  SignedMediaUrls._();

  static Future<String> signOne(SupabaseClient client, String raw) async {
    if (raw.trim().isEmpty) return raw;
    final signed = await signMany(client, [raw]);
    return signed[raw] ?? raw;
  }

  static Future<String?> signNullable(
    SupabaseClient client,
    String? raw,
  ) async {
    if (raw == null || raw.trim().isEmpty) return raw;
    return signOne(client, raw);
  }

  static Future<String> signJsonOrSingle(
    SupabaseClient client,
    String raw,
  ) async {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return raw;

    if (trimmed.startsWith('[')) {
      try {
        final values = List<String>.from(jsonDecode(trimmed) as List);
        final signed = await signMany(client, values);
        return jsonEncode(values.map((url) => signed[url] ?? url).toList());
      } catch (_) {
        // Fall through and treat as a single string.
      }
    }

    return signOne(client, raw);
  }

  static Future<Map<String, String>> signMany(
    SupabaseClient client,
    Iterable<String> raws,
  ) async {
    final values = raws
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    if (values.isEmpty) return const {};

    final session = client.auth.currentSession;
    if (session == null) return const {};

    final response = await http.post(
      Uri.parse('${WorkerUrls.r2Upload}/sign'),
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'urls': values}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const {};
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final signed = data['urls'];
    if (signed is! Map) return const {};
    return signed.map(
      (key, value) => MapEntry(key.toString(), value.toString()),
    );
  }
}
