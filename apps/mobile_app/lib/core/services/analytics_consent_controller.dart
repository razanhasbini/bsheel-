import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_core/app_core.dart' show AppLogger;

import '../providers/auth_session_provider.dart';
import '../providers/current_profile_provider.dart';
import 'analytics_service.dart';
import '../backend/backend_config.dart';
import '../backend/mobile_nest_backend.dart';

/// Bridges `profiles.analytics_consent_at` (migration 0142) to
/// `AnalyticsService.setConsent()` so Mixpanel is gated by the user's
/// recorded consent state — not just an in-memory flag.
///
/// Mount this provider once in the app shell (e.g. `BottomNavShell` or
/// `bootstrap.dart`) so the gate stays synced across login / logout /
/// account switch automatically.
final analyticsConsentSyncProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<dynamic>>(
    currentProfileProvider,
    (_, next) {
      final profile = next.valueOrNull;
      // Signed out / profile not loaded → revoke. Prevents the
      // previous user's consent leaking onto the next account on the
      // same device.
      if (profile == null) {
        ref.read(analyticsProvider).setConsent(false);
        return;
      }
      // Migration 0142: null = no consent; non-null timestamp = granted.
      final granted = profile.analyticsConsentAt != null;
      ref.read(analyticsProvider).setConsent(granted);
    },
    fireImmediately: true,
  );
});

/// User-facing toggle for analytics opt-in. Updates the DB row, then
/// the listener above flips the in-memory flag. Surfacable from the
/// onboarding consent prompt OR a settings toggle.
Future<void> setAnalyticsConsent(WidgetRef ref, {required bool granted}) async {
  final user = ref.read(authSessionProvider);
  if (user == null) {
    AppLogger.warning('[Analytics] setConsent called without a session');
    return;
  }
  try {
    if (BackendConfig.usesNest) {
      await MobileNestBackend.repositories.account.setAnalyticsConsent(granted);
      ref.invalidate(currentProfileProvider);
      return;
    }
    await Supabase.instance.client.from(Tables.profiles).update({
      ProfileColumns.analyticsConsentAt:
          granted ? DateTime.now().toUtc().toIso8601String() : null,
    }).eq(ProfileColumns.id, user.id);
    ref.invalidate(currentProfileProvider);
  } catch (e) {
    AppLogger.error('[Analytics] Failed to persist consent', e);
    rethrow;
  }
}
