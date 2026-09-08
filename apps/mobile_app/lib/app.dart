import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart' show AppLogger, QuestTheme;
import 'core/router/app_router.dart';
import 'core/router/route_names.dart';
import 'core/providers/auth_state_provider.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/lifecycle/app_resume_observer.dart';
import 'core/services/analytics_consent_controller.dart';
import 'core/widgets/app_prompts_listener.dart';
import 'core/widgets/maintenance_overlay.dart';
import 'core/widgets/offline_overlay.dart';
import 'l10n/app_localizations.dart';
import 'l10n/locale_provider.dart';

class QuestApp extends ConsumerStatefulWidget {
  const QuestApp({super.key});

  @override
  ConsumerState<QuestApp> createState() => _QuestAppState();
}

class _QuestAppState extends ConsumerState<QuestApp> {
  late final AppResumeObserver _resumeObserver;

  @override
  void initState() {
    super.initState();
    ref.read(authNotifierProvider);
    _resumeObserver = AppResumeObserver(ref)..attach();
  }

  @override
  void dispose() {
    _resumeObserver.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    // Watch locale so the entire app rebuilds when language changes
    final locale = ref.watch(localeProvider);

    ref.listen(passwordRecoveryProvider, (_, isRecovery) {
      if (isRecovery) {
        AppLogger.info(
            '[App] passwordRecovery detected → navigating to reset password');
        router.go(RoutePaths.resetPassword);
      }
    });

    // Migration 0142: keep the AnalyticsService consent flag synced
    // with `profiles.analytics_consent_at` so Mixpanel stays disabled
    // until the user accepts the analytics opt-in (and also revokes
    // when they sign out / when a new user signs in).
    ref.watch(analyticsConsentSyncProvider);

    // Connectivity bounce: if the device drops the network and regains it
    // (wifi flip, lift-off-elevator, airplane mode toggle), trigger the
    // same refresh path the resume observer uses. Without this, Riverpod
    // happily serves the empty/cached values forever once the radio comes
    // back, since nothing tells the providers anything changed.
    ref.listen<AsyncValue<bool>>(connectivityProvider, (prev, next) {
      final wasOffline = prev?.valueOrNull == false;
      final nowOnline = next.valueOrNull == true;
      if (wasOffline && nowOnline) {
        refreshAfterReconnect(ref, 'network back online');
      }
    });

    return MaterialApp.router(
      // Use locale hashCode as key to force full widget tree rebuild on language change
      key: ValueKey(locale.languageCode),
      title: 'Bsheel',
      // Locked to light Arcade Pop — the app does not support dark mode.
      // System dark-mode preference is intentionally ignored.
      theme: QuestTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      // Wrap every screen with two stacked overlays:
      //   1. MaintenanceOverlay (outermost) — admin-toggleable global
      //      lock screen. Wins over the offline panel because admins
      //      explicitly putting the app into maintenance is a more
      //      specific signal than "no network".
      //   2. OfflineOverlay — surfaces a single arcade-pop "you're
      //      offline" panel rather than letting individual pages fail
      //      silently with empty states.
      builder: (context, child) => MaintenanceOverlay(
        child: AppPromptsListener(
          // Wraps the offline + content layers so the admin-triggered
          // rate prompt and force-update overlay both have priority over
          // any in-app screen the user is on.
          child: OfflineOverlay(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
