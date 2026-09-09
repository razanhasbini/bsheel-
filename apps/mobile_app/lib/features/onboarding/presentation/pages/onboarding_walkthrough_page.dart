import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/analytics_consent_controller.dart';
import '../../../../core/services/sign_out_service.dart';
import '../../../../core/backend/app_backend.dart';
import '../providers/onboarding_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Arcade Pop onboarding walkthrough — chunky gradient tiles, bold type,
/// hard-shadow CTA button. Business logic (terms acceptance, Supabase RPC,
/// provider invalidation, routing) is unchanged.
class OnboardingWalkthroughPage extends ConsumerStatefulWidget {
  const OnboardingWalkthroughPage({super.key});

  @override
  ConsumerState<OnboardingWalkthroughPage> createState() =>
      _OnboardingWalkthroughPageState();
}

class _OnboardingWalkthroughPageState
    extends ConsumerState<OnboardingWalkthroughPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  // Guards both SKIP and LET'S GO so a fast double-tap can't stack
  // multiple terms dialogs on top of each other.
  bool _completing = false;

  static const _totalPages = 4;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _onComplete() async {
    if (_completing) return;
    setState(() => _completing = true);
    try {
      final accepted = await _showTermsDialog();
      if (!accepted) {
        // Decline = the user cannot continue into the app, but they were
        // also stuck on this walkthrough with no exit. Offer a real
        // out: sign out and return to login so they can change their
        // mind another day.
        if (!mounted) return;
        final wantsSignOut = await _showDeclineExitDialog();
        if (wantsSignOut == true && mounted) {
          try {
            await signOutAndCleanup(ref);
          } catch (e) {
            AppLogger.warning('[Onboarding] sign-out after decline failed: $e');
          }
          if (mounted) context.goNamed(RouteNames.login);
        }
        return;
      }

      try {
        await AppBackend.repositories.account.acceptTerms();
      } catch (e) {
        AppLogger.error('[Onboarding] acceptTerms RPC failed', e);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Could not record your acceptance. Please check your connection and try again.')),
          );
        }
        return;
      }

      // Migration 0142: ask for analytics consent IMMEDIATELY after
      // terms accept, before the user lands on home. Default is "no";
      // we only call Mixpanel if they explicitly say yes. The DB write
      // failure is non-fatal — analytics stays disabled either way.
      if (mounted) {
        final wantsAnalytics = await _showAnalyticsConsentDialog();
        if (wantsAnalytics == true) {
          try {
            await setAnalyticsConsent(ref, granted: true);
          } catch (e) {
            AppLogger.warning(
                '[Onboarding] analytics consent write failed: $e');
          }
        }
      }

      await setOnboardingComplete();
      ref.invalidate(onboardingCompleteProvider);
      if (mounted) {
        context.go(RoutePaths.home);
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  Future<bool?> _showAnalyticsConsentDialog() {
    final ink = QuestColors.text(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: QuestColors.cardBg(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: ink, width: 2),
        ),
        title: Text('HELP US IMPROVE?',
            style: QuestTypography.headlineSmall.copyWith(color: ink)),
        content: Text(
          'Anonymous usage analytics help us spot bugs and decide which '
          "features to build. You can change this any time in Settings. "
          'We never sell your data.',
          style: QuestTypography.bodyMedium.copyWith(color: ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('NO THANKS'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('OK, SHARE',
                style: TextStyle(color: QuestColors.osPrimary)),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeclineExitDialog() {
    final ink = QuestColors.text(context);
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: QuestColors.cardBg(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: ink, width: 2),
        ),
        title: Text('TERMS DECLINED',
            style: QuestTypography.headlineSmall
                .copyWith(color: QuestColors.softRed)),
        content: Text(
          "You can't use Bsheel without accepting the Terms. "
          'Sign out for now and come back when you\'re ready.',
          style: QuestTypography.bodyMedium.copyWith(color: ink),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('REVIEW AGAIN'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('SIGN OUT'),
          ),
        ],
      ),
    );
  }

  Future<bool> _showTermsDialog() async {
    final ink = QuestColors.text(context);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          decoration: BoxDecoration(
            color: QuestColors.cardBg(ctx),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: ink, width: 2),
            boxShadow: [
              BoxShadow(
                color: ink,
                offset: const Offset(3, 4),
                blurRadius: 0,
              ),
            ],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: QuestColors.softRed,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ink, width: 2),
                    ),
                    child: Icon(Icons.gavel_rounded,
                        color: QuestColors.onAccent(QuestColors.softRed),
                        size: 20),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'TERMS OF USE',
                    style: QuestTypography.headlineSmall.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'By using Bsheel, you agree to our Terms of Use and Community Guidelines:',
                        style: QuestTypography.bodyMedium.copyWith(
                          color: ink.withAlpha(200),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const _TermsBullet(
                          text: 'No objectionable or harmful content'),
                      const _TermsBullet(text: 'No harassment or bullying'),
                      const _TermsBullet(
                          text: 'No impersonation or misleading content'),
                      const _TermsBullet(
                          text: 'No spam or commercial solicitation'),
                      const _TermsBullet(
                          text: 'Respect others and their privacy'),
                      const SizedBox(height: 10),
                      Text(
                        'Violations result in content removal and account suspension or ban. '
                        'Users can report and block at any time. We review all reports within 24 hours.',
                        style: QuestTypography.bodySmall.copyWith(
                          color: ink.withAlpha(170),
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () => context.pushNamed(RouteNames.terms),
                        child: Text(
                          'Read full Terms of Use',
                          style: QuestTypography.labelSmall.copyWith(
                            color: QuestColors.osPrimary,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () =>
                            context.pushNamed(RouteNames.privacyPolicy),
                        child: Text(
                          'Read Privacy Policy',
                          style: QuestTypography.labelSmall.copyWith(
                            color: QuestColors.osPrimary,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _DialogButton(
                      label: 'DECLINE',
                      fill: QuestColors.cardBg(ctx),
                      fg: ink,
                      onTap: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _DialogButton(
                      label: 'I AGREE',
                      fill: QuestColors.accentYellow,
                      fg: ink,
                      raised: true,
                      onTap: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result == true;
  }

  void _nextPage() {
    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    } else {
      _onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final ink = QuestColors.text(context);
    final isLast = _currentPage == _totalPages - 1;
    // Both CTA grounds are accent fills, so the label/icon colour comes
    // from the helper rather than being chosen by eye.
    final ctaGround = isLast ? QuestColors.softRed : QuestColors.accentYellow;
    final onCta = QuestColors.onAccent(ctaGround);

    final steps = [
      _StepData(
        icon: Icons.videogame_asset_rounded,
        tint: QuestColors.osPrimary,
        title: l.onboarding1Title,
        subtitle: l.onboarding1Subtitle,
      ),
      _StepData(
        icon: Icons.explore_rounded,
        tint: QuestColors.softRed,
        title: l.onboarding2Title,
        subtitle: l.onboarding2Subtitle,
      ),
      _StepData(
        icon: Icons.star_rounded,
        tint: QuestColors.accentYellow,
        title: l.onboarding3Title,
        subtitle: l.onboarding3Subtitle,
      ),
      _StepData(
        icon: Icons.rocket_launch_rounded,
        tint: QuestColors.successGreen,
        title: l.onboarding4Title,
        subtitle: l.onboarding4Subtitle,
      ),
    ];

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // Skip
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: GestureDetector(
                  onTap: _onComplete,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: QuestColors.cardBg(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: ink, width: 1.5),
                    ),
                    child: Text(
                      l.skip.toUpperCase(),
                      style: QuestTypography.labelMedium.copyWith(
                        color: ink,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: _totalPages,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) => _WalkthroughStep(data: steps[i]),
              ),
            ),

            // Dots
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_totalPages, (index) {
                  final active = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeOutCubic,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 28 : 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: active
                          ? QuestColors.softRed
                          : QuestColors.cardBg(context),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: ink, width: 1.5),
                    ),
                  );
                }),
              ),
            ),

            // CTA
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: GestureDetector(
                onTap: _nextPage,
                child: Container(
                  width: double.infinity,
                  height: 58,
                  decoration: BoxDecoration(
                    color: ctaGround,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: ink, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: ink,
                        offset: const Offset(3, 4),
                        blurRadius: 0,
                      ),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            (isLast ? l.letsGo : l.next).toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: QuestTypography.buttonText.copyWith(
                              color: onCta,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          isLast
                              ? Icons.rocket_launch_rounded
                              : Icons.arrow_forward_rounded,
                          color: onCta,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step data + view ─────────────────────────────────────────────────────────

class _StepData {
  const _StepData({
    required this.icon,
    required this.tint,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color tint;
  final String title;
  final String subtitle;
}

class _WalkthroughStep extends StatefulWidget {
  const _WalkthroughStep({required this.data});
  final _StepData data;

  @override
  State<_WalkthroughStep> createState() => _WalkthroughStepState();
}

class _WalkthroughStepState extends State<_WalkthroughStep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 520),
  )..forward();

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Gradient tile with bounce-in
          AnimatedBuilder(
            animation: _ac,
            builder: (_, child) {
              final scale =
                  0.7 + (0.3 * Curves.elasticOut.transform(_ac.value));
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 136,
              height: 136,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: ink, width: 3),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    widget.data.tint,
                    widget.data.tint.withAlpha(184),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(4, 5),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Icon(
                widget.data.icon,
                size: 64,
                color: QuestColors.onAccent(widget.data.tint),
              ),
            ),
          ),
          const SizedBox(height: 40),

          // Title
          Text(
            widget.data.title.toUpperCase(),
            textAlign: TextAlign.center,
            style: QuestTypography.headlineLarge.copyWith(
              color: ink,
              fontSize: 26,
              fontWeight: FontWeight.w800,
              height: 1.15,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),

          // Subtitle
          Text(
            widget.data.subtitle,
            textAlign: TextAlign.center,
            style: QuestTypography.bodyMedium.copyWith(
              color: ink.withAlpha(180),
              fontSize: 15,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Terms dialog bits ────────────────────────────────────────────────────────

class _TermsBullet extends StatelessWidget {
  const _TermsBullet({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 6),
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: QuestColors.softRed,
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: QuestTypography.bodySmall.copyWith(
                color: ink.withAlpha(200),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.fill,
    required this.fg,
    required this.onTap,
    this.raised = false,
  });

  final String label;
  final Color fill;
  final Color fg;
  final VoidCallback onTap;
  final bool raised;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: raised
              ? [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(2, 3),
                    blurRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: QuestTypography.labelMedium.copyWith(
              color: fg,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}
