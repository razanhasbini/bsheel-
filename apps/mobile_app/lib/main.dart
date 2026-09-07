import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import 'bootstrap.dart';
import 'app.dart';
import 'core/backend/backend_config.dart';
import 'core/backend/mobile_nest_overrides.dart';
import 'l10n/locale_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Narrow suppression: only Supabase session-restore noise. Everything else
  // flows through the normal Flutter error presenter so real crashes surface.
  FlutterError.onError = (FlutterErrorDetails details) {
    final error = details.exception.toString();
    if (error.contains('Session expired') ||
        error.contains('refresh token') ||
        error.contains('auth session missing')) {
      AppLogger.info('[Main] Suppressed Supabase init error: $error');
      return;
    }
    FlutterError.presentError(details);
  };

  await bootstrap();
  final savedLocale = await loadSavedLocale();
  runApp(ProviderScope(
    overrides: [
      localeProvider.overrideWith((ref) => savedLocale),
      if (BackendConfig.usesNest) ...mobileNestRepositoryOverrides(),
    ],
    child: const QuestApp(),
  ));

  // Kick off heavy services AFTER the first frame — Firebase, Mixpanel, FCM,
  // notification setup, badge clear. Not awaited so the UI is interactive
  // immediately.
  // ignore: unawaited_futures
  initDeferredServices();
}
