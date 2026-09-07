import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import '../backend/backend_config.dart';
import '../backend/mobile_nest_backend.dart';

/// Fetches the app_config rows visible to the caller, as a
/// `Map<String, String>`.
///
/// Signed-in callers get every row (`authenticated_read_app_config`,
/// migration 0140 C9). Signed-OUT callers get only the pre-auth-safe
/// allow-list from `anon_read_public_app_config` (migration 0149):
/// social_login_enabled, maintenance_mode(+_message) and the
/// update_required_* / rate_prompt_token keys.
///
/// Between 0140 and 0149 anon got NOTHING here — an RLS-denied SELECT is
/// not an error, PostgREST just returns `200 []` — so every flag below
/// silently failed open on the login/signup screens. If you add a new
/// key that must be readable before sign-in, add it to that policy too,
/// and never add a server-side key to it.
final appConfigProvider = FutureProvider<Map<String, String>>((ref) async {
  if (BackendConfig.usesNest) {
    return MobileNestBackend.repositories.publicConfig.getConfig();
  }
  final rows = await Supabase.instance.client
      .from(Tables.appConfig)
      .select('key, value')
      .timeout(const Duration(seconds: 5)) as List<dynamic>;

  return {
    for (final row in rows)
      (row as Map<String, dynamic>)['key'] as String: row['value'] as String,
  };
});

/// Whether social login buttons (Apple/Google) should be shown.
final socialLoginEnabledProvider = Provider<bool>((ref) {
  final config = ref.watch(appConfigProvider).valueOrNull ?? {};
  return config['social_login_enabled'] != 'false';
});

/// Live-watching stream of the entire app_config map. Subscribes to
/// Postgres realtime so that admin-side toggles (maintenance mode in
/// particular) take effect within a couple of seconds without needing
/// a cold start. The first emission comes from a one-shot SELECT so
/// the UI never has to wait for the first realtime event.
final liveAppConfigProvider = StreamProvider<Map<String, String>>((ref) {
  if (BackendConfig.usesNest) {
    return MobileNestBackend.repositories.publicConfig.watch();
  }
  final client = Supabase.instance.client;
  late final StreamController<Map<String, String>> controller;
  final state = <String, String>{};

  Future<void> seed() async {
    try {
      final rows = await client
          .from(Tables.appConfig)
          .select('key, value')
          .timeout(const Duration(seconds: 5)) as List<dynamic>;
      state
        ..clear()
        ..addEntries(rows.map((row) {
          final m = row as Map<String, dynamic>;
          return MapEntry(m['key'] as String, m['value'] as String);
        }));
      if (!controller.isClosed) controller.add(Map.unmodifiable(state));
    } catch (_) {
      // Network drop / DNS / slow seed — emit an empty map so callers move
      // past AsyncLoading instead of hanging the UI behind a `.when()`.
      // The realtime channel will push the real values once they arrive.
      if (!controller.isClosed) controller.add(const <String, String>{});
    }
  }

  final channel = client.channel('public:app_config')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: Tables.appConfig,
      callback: (payload) {
        final newRow = payload.newRecord;
        final oldRow = payload.oldRecord;
        if (payload.eventType == PostgresChangeEvent.delete) {
          final key = oldRow['key'];
          if (key is String) state.remove(key);
        } else {
          final key = newRow['key'];
          final value = newRow['value'];
          if (key is String && value is String) state[key] = value;
        }
        if (!controller.isClosed) controller.add(Map.unmodifiable(state));
      },
    )
    ..subscribe();

  controller = StreamController<Map<String, String>>(
    onListen: seed,
    onCancel: () {
      client.removeChannel(channel);
    },
  );

  ref.onDispose(() {
    controller.close();
  });

  return controller.stream;
});

/// Whether the app should show the full-screen "under maintenance"
/// blocker. Defaults to false — falls back to "off" if the config
/// hasn't loaded yet so we don't accidentally lock people out on
/// network hiccups.
final maintenanceModeProvider = Provider<bool>((ref) {
  final config = ref.watch(liveAppConfigProvider).valueOrNull ?? {};
  return config['maintenance_mode'] == 'true';
});

/// Optional custom message shown on the maintenance screen.
final maintenanceMessageProvider = Provider<String?>((ref) {
  final config = ref.watch(liveAppConfigProvider).valueOrNull ?? {};
  final m = config['maintenance_message']?.trim();
  return (m == null || m.isEmpty) ? null : m;
});
