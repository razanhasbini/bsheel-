import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../backend/app_backend.dart';

/// Fetches the app config visible to the caller, as a `Map<String, String>`.
///
/// `GET /config` is public and returns only the pre-auth-safe keys:
/// social_login_enabled, maintenance_mode(+_message) and the
/// update_required_* / rate_prompt_token keys. Never add a server-side
/// secret to that endpoint.
///
/// Read failures must not fail open: a flag that gates access is treated as
/// absent, and absent means "off" for every gate below.
final appConfigProvider = FutureProvider<Map<String, String>>((ref) async {
  return AppBackend.repositories.publicConfig.getConfig();
});

/// Whether social login buttons (Apple/Google) should be shown.
///
/// Defaults to OFF when the row is missing. A kill switch that fails open is
/// not a kill switch.
final socialLoginEnabledProvider = Provider<bool>((ref) {
  final config = ref.watch(appConfigProvider).valueOrNull;
  if (config == null) return false;
  return config['social_login_enabled'] == 'true';
});

/// Live-watching stream of the whole config map, so an admin toggle
/// (maintenance mode in particular) takes effect within seconds without a
/// cold start. The first emission comes from a one-shot read so the UI never
/// waits on the polling interval.
final liveAppConfigProvider = StreamProvider<Map<String, String>>((ref) {
  return AppBackend.repositories.publicConfig.watch();
});

/// Whether the app should show the full-screen "under maintenance" blocker.
/// Falls back to off so a network hiccup cannot lock everyone out.
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
