import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kOnboardingCompleteKey = 'onboarding_complete';

/// Provider that checks whether the user has completed the onboarding
/// walkthrough. Returns `true` if complete, `false` otherwise.
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingCompleteKey) ?? false;
});

/// Marks the onboarding walkthrough as complete in SharedPreferences.
Future<void> setOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingCompleteKey, true);
}

/// Clears the onboarding flag — call on sign-out so the next account
/// that logs in sees the walkthrough again.
Future<void> clearOnboardingComplete() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kOnboardingCompleteKey);
}
