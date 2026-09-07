import 'dart:io' show Platform;

import 'package:app_core/app_core.dart' show AppLogger;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_info_service.dart';

/// Triggers a native in-app rating prompt where the OS allows, falling
/// back to the platform's store listing when it doesn't.
///
/// iOS path → `SKStoreReviewController` via the `app/rate` MethodChannel
/// (hand-rolled, no third-party plugin per the project's
/// no-supply-chain policy).
///
/// Android path → just launches the Play Store listing; Google's
/// in-app review API requires Play Core which we deliberately do not
/// link in.
class RateAppService {
  RateAppService(this._info);

  final AppInfoService _info;
  static const MethodChannel _channel = MethodChannel('app/rate');

  Future<void> request() async {
    if (Platform.isIOS) {
      // SKStoreReviewController limits the system prompt to ~3
      // appearances per 365 days. Outside that window the call no-ops
      // silently — we don't catch this as an error, we let the OS
      // arbitrate the user experience.
      try {
        await _channel.invokeMethod<dynamic>('requestReview');
        return;
      } catch (e) {
        AppLogger.warning('[Rate] requestReview failed, falling back: $e');
      }
    }
    // Android (or iOS fallback): open the store listing in the browser.
    final url = Uri.parse(_info.storeUrl());
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      AppLogger.warning('[Rate] storeUrl launch failed: $e');
    }
  }
}

final rateAppServiceProvider = Provider<RateAppService>((ref) {
  return RateAppService(ref.watch(appInfoServiceProvider));
});
