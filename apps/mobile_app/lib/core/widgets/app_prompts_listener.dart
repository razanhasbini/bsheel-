import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/app_config_provider.dart';
import '../providers/auth_session_provider.dart';
import '../services/app_info_service.dart';
import '../services/rate_app_service.dart';

// Keys consumed from `app_config`:
//   rate_prompt_token       — any string. When it differs from the
//                              locally-stored "last shown" token we
//                              show the rate dialog once at app open.
//   update_required_min_build — integer. If the user's CFBundleVersion
//                              is below this, the update overlay shows.
//   update_required_message — optional custom string for the overlay.
//   update_required_force   — "true" makes the overlay non-dismissable.

const _kRateLastTokenPrefKey = 'rate_prompt_last_token_v1';

/// Mount under MaterialApp's builder to gate the entire app behind the
/// update overlay (when required) and surface the rate prompt at the
/// appropriate moment. Pure wrapper — passes [child] through unchanged
/// when neither is in play.
class AppPromptsListener extends ConsumerStatefulWidget {
  const AppPromptsListener({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppPromptsListener> createState() => _AppPromptsListenerState();
}

class _AppPromptsListenerState extends ConsumerState<AppPromptsListener> {
  bool _rateShownThisSession = false;
  int? _currentBuild;

  @override
  void initState() {
    super.initState();
    // Async fetch the build number once so we can synchronously decide
    // whether to gate the UI on each rebuild.
    ref.read(appInfoServiceProvider).buildNumber().then((b) {
      if (mounted) setState(() => _currentBuild = b);
    });
  }

  Future<void> _maybeShowRatePrompt(String? configToken) async {
    if (_rateShownThisSession) return;
    if (configToken == null || configToken.isEmpty) return;
    // Only prompt signed-in users — anon visitors shouldn't see it.
    if (ref.read(authSessionProvider) == null) return;

    final prefs = await SharedPreferences.getInstance();
    final lastShown = prefs.getString(_kRateLastTokenPrefKey);
    if (lastShown == configToken) return; // already prompted for this push

    _rateShownThisSession = true;
    await prefs.setString(_kRateLastTokenPrefKey, configToken);

    // Give the UI one frame to settle so the dialog doesn't fight the
    // splash → home transition.
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    await _showRateDialog();
  }

  Future<void> _showRateDialog() async {
    final ink = QuestColors.text(context);
    await showDialog<void>(
      context: context,
      barrierColor: QuestColors.pureBlack.withAlpha(140),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 18),
          decoration: BoxDecoration(
            color: QuestColors.bg(ctx),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ink, width: 2),
            boxShadow: [
              BoxShadow(color: ink, offset: const Offset(4, 4), blurRadius: 0),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Five-star row in gold with chunky ink outline.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < 5; i++)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(Icons.star_rounded,
                          size: 34, color: QuestColors.accentYellow),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                "LOVING BSHEEL?",
                textAlign: TextAlign.center,
                style: QuestTypography.displayLarge.copyWith(
                  color: ink,
                  fontSize: 22,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "A quick rating helps more players find quests. It only takes a second.",
                textAlign: TextAlign.center,
                style: QuestTypography.bodyMedium.copyWith(
                  color: ink.withAlpha(170),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                  flex: 1,
                  child: _DialogButton(
                    label: 'NOT NOW',
                    bg: QuestColors.bg(ctx),
                    fg: ink,
                    onTap: () => Navigator.of(ctx).pop(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _DialogButton(
                    label: 'RATE BSHEEL',
                    bg: QuestColors.osPrimary,
                    fg: QuestColors.osTextOnPrimary,
                    onTap: () {
                      HapticFeedback.mediumImpact();
                      Navigator.of(ctx).pop();
                      ref.read(rateAppServiceProvider).request();
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowUpdateOverlay(Map<String, String> config) {
    final minBuildStr = config['update_required_min_build'];
    if (minBuildStr == null || minBuildStr.isEmpty) return false;
    final minBuild = int.tryParse(minBuildStr);
    if (minBuild == null) return false;
    final cur = _currentBuild;
    if (cur == null) return false; // unknown until native channel returns
    return cur < minBuild;
  }

  @override
  Widget build(BuildContext context) {
    // Side-effect: rate prompt fires whenever the config token changes.
    ref.listen<AsyncValue<Map<String, String>>>(liveAppConfigProvider,
        (prev, next) {
      final token = next.valueOrNull?['rate_prompt_token'];
      _maybeShowRatePrompt(token);
    });

    final config = ref.watch(liveAppConfigProvider).valueOrNull ?? const {};
    if (_shouldShowUpdateOverlay(config)) {
      return _UpdateRequiredOverlay(
        message: config['update_required_message'],
        force: config['update_required_force']?.toLowerCase() == 'true',
        onUpdate: () {
          final url = Uri.parse(ref.read(appInfoServiceProvider).storeUrl());
          launchUrl(url, mode: LaunchMode.externalApplication);
        },
      );
    }

    return widget.child;
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Update-required full-screen overlay
// ─────────────────────────────────────────────────────────────────────────

class _UpdateRequiredOverlay extends StatelessWidget {
  const _UpdateRequiredOverlay({
    required this.onUpdate,
    required this.force,
    this.message,
  });

  final VoidCallback onUpdate;
  final bool force;
  final String? message;

  @override
  Widget build(BuildContext context) {
    // Independent of the existing MaterialApp — we render a Material
    // wrapper so Dialog / Theme look right even when this displaces the
    // app's own router.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: QuestColors.osBg,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [QuestColors.osPrimary, QuestColors.softRed],
                    ),
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: QuestColors.osTextPrimary, width: 2),
                    boxShadow: const [
                      BoxShadow(
                          color: QuestColors.osTextPrimary,
                          offset: Offset(4, 4),
                          blurRadius: 0),
                    ],
                  ),
                  child: const Icon(Icons.system_update_alt_rounded,
                      color: QuestColors.osTextOnPrimary, size: 50),
                ),
                const SizedBox(height: 28),
                Text(
                  'TIME TO UPDATE',
                  textAlign: TextAlign.center,
                  style: QuestTypography.displayLarge.copyWith(
                    color: QuestColors.osTextPrimary,
                    fontSize: 30,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  message?.isNotEmpty == true
                      ? message!
                      : "We've shipped new quests and fixes. Update to keep playing.",
                  textAlign: TextAlign.center,
                  style: QuestTypography.bodyMedium.copyWith(
                    color: QuestColors.osTextPrimary.withAlpha(180),
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
                const Spacer(flex: 3),
                _DialogButton(
                  label: 'UPDATE NOW',
                  bg: QuestColors.osPrimary,
                  fg: QuestColors.osTextOnPrimary,
                  onTap: onUpdate,
                  fullWidth: true,
                ),
                if (!force) ...[
                  const SizedBox(height: 10),
                  Text(
                    "You can keep using the app for now, but new features may not work right.",
                    textAlign: TextAlign.center,
                    style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.osTextPrimary.withAlpha(120),
                      fontSize: 11,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Shared dialog button — chunky Arcade-Pop with ink shadow
// ─────────────────────────────────────────────────────────────────────────

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.bg,
    required this.fg,
    required this.onTap,
    this.fullWidth = false,
  });

  final String label;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;
  final bool fullWidth;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: fullWidth ? double.infinity : null,
        height: 48,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(3, 3), blurRadius: 0),
          ],
        ),
        child: Text(
          label,
          style: QuestTypography.labelLarge.copyWith(
            color: fg,
            fontSize: 13,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
