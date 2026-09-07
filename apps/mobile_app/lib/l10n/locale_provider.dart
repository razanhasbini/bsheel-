import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _localeKey = 'app_locale';

/// Holds the current app locale.
///
/// Defaults to English ('en'); the saved choice is loaded in main() and
/// injected via a ProviderScope override so the selection survives app
/// restarts. Always change the locale through [setLocale] — writing the
/// state directly would skip persistence.
final localeProvider = StateProvider<Locale>((ref) => const Locale('en'));

/// Read the persisted locale (falls back to English).
Future<Locale> loadSavedLocale() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(_localeKey);
  return code == 'lb' ? const Locale('lb') : const Locale('en');
}

/// Update the in-memory locale AND persist it for the next launch.
Future<void> setLocale(WidgetRef ref, Locale locale) async {
  ref.read(localeProvider.notifier).state = locale;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_localeKey, locale.languageCode);
}
