import 'dart:async';
import 'dart:convert';

import '../api/api_client.dart';

/// Public, pre-auth application configuration.
class ApiPublicConfigRepository {
  const ApiPublicConfigRepository(this._client);

  final ApiClient _client;

  /// Queues an account-deletion request from the public, signed-out page.
  ///
  /// Unauthenticated by necessity — the store-compliance page is reachable
  /// without a session. The server records the request for an operator rather
  /// than erasing anything, because an endpoint that acted on an email address
  /// alone would let anyone delete anyone's account.
  ///
  /// Returns nothing and reveals nothing: the response is the same whether or
  /// not the address has an account, so it cannot be used to enumerate users.
  /// Throws [ApiException] on failure, which the caller must surface rather
  /// than swallow — the page used to claim success unconditionally.
  Future<void> requestAccountDeletion({
    required String email,
    String? note,
  }) async {
    await _client.post(
      'public/deletion-requests',
      authenticated: false,
      body: {
        'email': email.trim().toLowerCase(),
        'confirmation': 'DELETE',
        if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      },
    );
  }

  Future<Map<String, String>> getConfig() async {
    final rows = apiObjectList(
      await _client.get('config', authenticated: false),
    );
    return {
      for (final row in rows) row['key'].toString(): _stringValue(row['value']),
    };
  }

  /// Polls the public endpoint for flags that must work before authentication.
  /// Requests never overlap, duplicate maps are suppressed, and a temporary
  /// failure preserves the last known state until the next bounded retry.
  Stream<Map<String, String>> watch({
    Duration interval = const Duration(seconds: 5),
  }) {
    late final StreamController<Map<String, String>> controller;
    Timer? timer;
    var loading = false;
    Map<String, String>? previous;

    Future<void> refresh() async {
      if (loading || controller.isClosed) return;
      loading = true;
      try {
        final next = await getConfig();
        if (!_sameMap(previous, next) && !controller.isClosed) {
          previous = next;
          controller.add(Map.unmodifiable(next));
        }
      } catch (_) {
        if (previous == null && !controller.isClosed) {
          previous = const {};
          controller.add(const {});
        }
      } finally {
        loading = false;
      }
    }

    controller = StreamController<Map<String, String>>(
      onListen: () {
        unawaited(refresh());
        timer = Timer.periodic(interval, (_) => unawaited(refresh()));
      },
      onCancel: () {
        timer?.cancel();
      },
    );
    return controller.stream;
  }
}

String _stringValue(Object? value) {
  if (value is String) return value;
  if (value is num || value is bool) return value.toString();
  return jsonEncode(value);
}

bool _sameMap(Map<String, String>? left, Map<String, String> right) {
  if (left == null || left.length != right.length) return false;
  for (final entry in right.entries) {
    if (left[entry.key] != entry.value) return false;
  }
  return true;
}
