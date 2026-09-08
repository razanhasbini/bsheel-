import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:app_core/app_core.dart' show AppLogger;
import 'bootstrap.dart';
import 'app.dart';

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  // Suppress font loading and auth initialization errors
  FlutterError.onError = (FlutterErrorDetails details) {
    final error = details.exception.toString();
    // Suppress font loading failures
    if (error.contains('google_fonts') ||
        error.contains('Failed to load font') ||
        error.contains('fonts.gstatic.com') ||
        error.contains('Failed to fetch')) {
      AppLogger.info('[Main] Suppressed font loading error: $error');
      return;
    }
    // Suppress session-restore errors from a stale refresh token
    if (error.contains('Session expired') ||
        error.contains('refresh token') ||
        error.contains('auth session missing')) {
      AppLogger.info('[Main] Suppressed session-restore error: $error');
      return;
    }
    FlutterError.presentError(details);
  };

  await bootstrap();
  runApp(
    const ProviderScope(
      child: AdminApp(),
    ),
  );
}
