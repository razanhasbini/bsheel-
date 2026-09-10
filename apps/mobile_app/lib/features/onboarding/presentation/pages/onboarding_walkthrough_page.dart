import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/analytics_consent_controller.dart';
import '../../../../core/services/sign_out_service.dart';
import '../../../../core/backend/app_backend.dart';
import '../providers/onboarding_provider.dart';
import '../../../../l10n/app_localizations.dart';

/// Onboarding walkthrough, drawn from `export/mobile/01-onboarding-1.jpg` and
/// `export/mobile/02-onboarding-4.jpg`.
///
/// Two layouts, not one:
///
/// * **Steps 1-3 — cream.** Four segment bars top-left (active violet, 2px ink
///   outline), a plain SKIP label top-right, a 4:3 striped illustration panel
///   at r18 with a **gold** 6px shadow, a Syne 800/40 title and a mono
///   subtitle, then a full-width violet NEXT button.
/// * **Step 4 — ink panel.** No illustration, no SKIP. Borderless segment
///   bars (active gold), a Syne 800/48 white title, a lavender subtitle, and a
///   gold LET'S GO button outlined in **cream** with no shadow.
///
/// Subtitles are sentence case. The .arb copy is still four lines of caps and
/// the design frame reproduces it verbatim — `mobile-handoff/SPEC.md` calls
/// that out as the one place the design deliberately keeps a known-wrong
/// string "so you can see the cost". [_sentenceCase] fixes it at the point of
/// display for every locale; the real fix is in `app_en.arb` / `app_lb.arb`.
///
/// Business logic — terms acceptance, the analytics consent prompt, the
/// decline/sign-out escape hatch, `acceptTerms()` and routing — is unchanged.
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
            style: QuestTypography.osHeadlineSmall.copyWith(color: ink)),
        content: Text(
          'Anonymous usage analytics help us spot bugs and decide which '
          "features to build. You can change this any time in Settings. "
          'We never sell your data.',
          style: QuestTypography.osBodyMedium.copyWith(color: ink),
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
            style: QuestTypography.osHeadlineSmall
                // Coral used *as* type on cream fails contrast; osRedText is
                // its readable twin.
                .copyWith(color: QuestColors.onCream(QuestColors.osRed))),
        content: Text(
          "You can't use Bsheel without accepting the Terms. "
          'Sign out for now and come back when you\'re ready.',
          style: QuestTypography.osBodyMedium.copyWith(color: ink),
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
            boxShadow: QuestSpacing.shadowMd,
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
                      color: QuestColors.osRed,
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusButton),
                      border: Border.all(color: ink, width: 2),
                    ),
                    child: Icon(Icons.gavel_rounded,
                        color: QuestColors.onAccent(QuestColors.osRed),
                        size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'TERMS OF USE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QuestTypography.osHeadlineSmall.copyWith(
                        color: ink,
                        letterSpacing: 1,
                      ),
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
                        style: QuestTypography.osBodyMedium.copyWith(
                          color: QuestColors.osTextSecondary,
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
                        style: QuestTypography.osBodySmall.copyWith(
                          color: QuestColors.osTextSecondary,
                          height: 1.55,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _DialogLink(
                        label: 'Read full Terms of Use',
                        onTap: () => context.pushNamed(RouteNames.terms),
                      ),
                      const SizedBox(height: 4),
                      _DialogLink(
                        label: 'Read Privacy Policy',
                        onTap: () =>
                            context.pushNamed(RouteNames.privacyPolicy),
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
                      fill: QuestColors.osAccent,
                      // Gold ground: ink, never white.
                      fg: QuestColors.onAccent(QuestColors.osAccent),
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

  /// 0 on the cream steps, 1 on the ink step, and the fraction in between
  /// while the swipe is in flight.
  ///
  /// Without this the ground would flip a whole page early or late and step
  /// 4's white type would spend the swipe invisible on cream.
  double get _inkT {
    var page = _currentPage.toDouble();
    if (_pageController.hasClients) {
      page = _pageController.page ?? page;
    }
    return (page - (_totalPages - 2)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;

    final steps = [
      _StepData(title: l.onboarding1Title, subtitle: l.onboarding1Subtitle),
      _StepData(title: l.onboarding2Title, subtitle: l.onboarding2Subtitle),
      _StepData(title: l.onboarding3Title, subtitle: l.onboarding3Subtitle),
      _StepData(title: l.onboarding4Title, subtitle: l.onboarding4Subtitle),
    ];

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, _) {
        final inkT = _inkT;
        final onInk = inkT >= 0.5;
        final ground = Color.lerp(QuestColors.osBg, _kInkPanel, inkT)!;

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: onInk
              ? SystemUiOverlayStyle.light.copyWith(statusBarColor: ground)
              : SystemUiOverlayStyle.dark.copyWith(statusBarColor: ground),
          child: Scaffold(
            backgroundColor: ground,
            body: SafeArea(
              // The 24 of side padding sits *inside* each page rather than
              // around the PageView: the illustration panel's gold shadow
              // overflows 6 into that gutter, and a PageView clips its
              // viewport, so padding on the outside eats the shadow.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                    child: Row(
                      children: [
                        _ProgressBars(
                          total: _totalPages,
                          current: _currentPage,
                          onInk: onInk,
                        ),
                        const Spacer(),
                        // The frame drops SKIP on the last step — there is
                        // nothing left to skip.
                        if (!onInk)
                          _SkipButton(
                            label: l.skip,
                            onTap: _completing ? null : _onComplete,
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _totalPages,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      itemBuilder: (_, i) => _WalkthroughStep(
                        data: steps[i],
                        isInkStep: i == _totalPages - 1,
                        inkT: inkT,
                      ),
                    ),
                  ),
                  Padding(
                    // 26 of bottom padding in the frame.
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 26),
                    child: onInk
                        ? _InkPanelCta(
                            label: l.letsGo,
                            onTap: _completing ? null : _nextPage,
                          )
                        : ArcadeButton(label: l.next, onTap: _nextPage),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The design's ink-panel ground, `#1A1330` — the same value the light theme
/// uses as ink, so [QuestColors.osTextPrimary] is the token that carries it.
const Color _kInkPanel = QuestColors.osTextPrimary;

// ── Step data + view ─────────────────────────────────────────────────────────

class _StepData {
  const _StepData({required this.title, required this.subtitle});
  final String title;
  final String subtitle;
}

class _WalkthroughStep extends StatelessWidget {
  const _WalkthroughStep({
    required this.data,
    required this.isInkStep,
    required this.inkT,
  });

  final _StepData data;

  /// This step's own layout — the ink step is type only and set larger.
  final bool isInkStep;

  /// How dark the page ground currently is, so type stays legible through
  /// the swipe rather than only at rest.
  final double inkT;

  @override
  Widget build(BuildContext context) {
    final title = Text(
      data.title.toUpperCase(),
      style: QuestTypography.osDisplayLarge.copyWith(
        fontSize: isInkStep ? 48 : 40,
        height: isInkStep ? 0.94 : 0.96,
        // -0.04em at the title's size.
        letterSpacing: isInkStep ? -1.92 : -1.6,
        color: Color.lerp(
          QuestColors.osTextPrimary,
          QuestColors.textPrimary,
          inkT,
        ),
      ),
    );

    final subtitle = Text(
      _sentenceCase(data.subtitle),
      style: QuestTypography.osLabelSmall.copyWith(
        fontSize: 13,
        height: 1.7,
        // 0.04em at 13px.
        letterSpacing: 0.52,
        color: Color.lerp(
          QuestColors.osTextSecondary,
          QuestColors.textSecondary,
          inkT,
        ),
      ),
    );

    // Centred when it fits, scrollable when it does not. A 4:3 panel plus a
    // 40px title plus four subtitle lines does not fit an SE-class screen,
    // and the frame's layout is the 390x844 case.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            // Inside the scroll view, so the panel's gold shadow can spill
            // into the gutter instead of being clipped at the content edge.
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The ink step is type only; the cream steps lead with the
                // panel.
                if (!isInkStep) ...[
                  const _IllustrationPanel(),
                  const SizedBox(height: 22),
                ],
                title,
                SizedBox(height: isInkStep ? 20 : 14),
                subtitle,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ALL CAPS is for labels and headers. The onboarding subtitles are
/// sentences, so they are lower-cased and re-capitalised per sentence at the
/// point of display — the .arb copy for both locales is still shouting.
///
/// Acronyms stay up. Words that begin with a digit (common in Arabizi —
/// `2ABEL`, `3AL`) are left alone rather than having a capital forced into
/// second position.
String _sentenceCase(String input) {
  const keepUpper = {'IRL', 'XP'};

  final lowered = input.split(RegExp(r'(?<=\s)|(?=\s)')).map((token) {
    final bare = token.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
    if (bare.isNotEmpty && keepUpper.contains(bare.toUpperCase())) {
      return token.toUpperCase();
    }
    return token.toLowerCase();
  }).join();

  // Capitalise the first letter of the string and of each new sentence or
  // line. `sentenceStart` survives runs of whitespace and punctuation.
  final out = StringBuffer();
  var sentenceStart = true;
  for (final rune in lowered.runes) {
    final ch = String.fromCharCode(rune);
    if (sentenceStart && RegExp(r'[a-z]').hasMatch(ch)) {
      out.write(ch.toUpperCase());
      sentenceStart = false;
      continue;
    }
    if (RegExp(r'[.!?\n]').hasMatch(ch)) {
      sentenceStart = true;
    } else if (!RegExp(r'\s').hasMatch(ch)) {
      sentenceStart = false;
    }
    out.write(ch);
  }
  return out.toString();
}

// ── Illustration panel ───────────────────────────────────────────────────────

/// The frame's placeholder art: a 4:3 panel at r18 with a 2px ink outline, a
/// **gold** 6px shadow — the one coloured shadow on this screen — and a
/// 135° 10/10 stripe fill in cream over warm surface.
class _IllustrationPanel extends StatelessWidget {
  const _IllustrationPanel();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: QuestSpacing.hardShadow(6, color: QuestColors.osAccent),
        ),
        child: ClipRRect(
          // Inside the 2px stroke.
          borderRadius: BorderRadius.circular(16),
          child: CustomPaint(
            painter: _DiagonalStripes(),
            child: Center(
              child: Text(
                'ONBOARDING ILLUSTRATION',
                textAlign: TextAlign.center,
                style: QuestTypography.osLabelSmall.copyWith(
                  fontSize: 11,
                  // 0.1em at 11px.
                  letterSpacing: 1.1,
                  color: QuestColors.osTextSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DiagonalStripes extends CustomPainter {
  /// `repeating-linear-gradient(135deg, surface 0 10px, cream 10px 20px)`.
  static const _period = 20.0;
  static const _band = 10.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = QuestColors.osBg,
    );

    final stripe = Paint()..color = QuestColors.osSurface;
    // Rotating a quarter turn clockwise turns axis-aligned bands into the
    // "/" run the frame draws; the extent covers the rotated bounds.
    final reach = size.width + size.height;
    canvas.save();
    canvas.rotate(math.pi / 4);
    for (var x = -reach; x < reach; x += _period) {
      canvas.drawRect(Rect.fromLTWH(x, -reach, _band, reach * 2), stripe);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Progress bars ────────────────────────────────────────────────────────────

/// Four segment bars, 6 apart. On cream they are 26x6 inside a 2px ink stroke
/// with a violet active segment; on the ink panel the stroke is gone and the
/// active segment is gold.
class _ProgressBars extends StatelessWidget {
  const _ProgressBars({
    required this.total,
    required this.current,
    required this.onInk,
  });

  final int total;
  final int current;
  final bool onInk;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < total; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            // 26x6 of content; the cream variant adds the 2px stroke around
            // it, exactly as the frame's content-box sizing does.
            width: onInk ? 26 : 30,
            height: onInk ? 6 : 10,
            decoration: BoxDecoration(
              color: i == current
                  ? (onInk ? QuestColors.osAccent : QuestColors.osPrimary)
                  : (onInk ? QuestColors.border : QuestColors.osBg),
              // The frame's literal value for a 6px pip; the role radius
              // scale starts above this size.
              borderRadius: BorderRadius.circular(QuestSpacing.radiusPip),
              border: onInk
                  ? null
                  : Border.all(color: QuestColors.osTextPrimary, width: 2),
            ),
          ),
        ],
      ],
    );
  }
}

// ── SKIP ─────────────────────────────────────────────────────────────────────

/// A bare mono label, as drawn — no chip, no outline. The paint stays small
/// and the hit box is padded out to 44.
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: QuestSpacing.minTouchTarget,
          minWidth: QuestSpacing.minTouchTarget,
        ),
        child: Center(
          child: Text(
            label.toUpperCase(),
            maxLines: 1,
            style: QuestTypography.osLabelSmall.copyWith(
              fontSize: 11,
              // 0.1em at 11px.
              letterSpacing: 1.1,
              color: QuestColors.osTextSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Ink-panel CTA ────────────────────────────────────────────────────────────

/// The last step's button: gold, 56pt, r14, **cream** 2px outline and no
/// shadow. [ArcadeButton] cannot express this — every variant there is
/// ink-outlined with a hard ink shadow, which on an ink ground would be
/// invisible in one direction and a smear in the other.
class _InkPanelCta extends StatefulWidget {
  const _InkPanelCta({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  State<_InkPanelCta> createState() => _InkPanelCtaState();
}

class _InkPanelCtaState extends State<_InkPanelCta> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: enabled
          ? (_) {
              setState(() => _pressed = false);
              HapticFeedback.lightImpact();
              widget.onTap?.call();
            }
          : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 60),
        opacity: _pressed ? 0.86 : 1,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: QuestColors.osAccent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: QuestColors.osBg, width: 2),
          ),
          child: Text(
            widget.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osButtonText.copyWith(
              fontSize: 16,
              // 0.05em at 16px.
              letterSpacing: 0.8,
              // Gold ground: ink, never white.
              color: QuestColors.onAccent(QuestColors.osAccent),
            ),
          ),
        ),
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
              color: QuestColors.osRed,
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: QuestTypography.osBodySmall.copyWith(
                color: QuestColors.osTextSecondary,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogLink extends StatelessWidget {
  const _DialogLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(minHeight: QuestSpacing.minTouchTarget),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: QuestTypography.osBodySmall.copyWith(
              color: QuestColors.osPrimary,
              decoration: TextDecoration.underline,
              decorationColor: QuestColors.osPrimary,
            ),
          ),
        ),
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
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: QuestSpacing.minTouchTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
          border: Border.all(color: ink, width: 2),
          boxShadow: raised ? QuestSpacing.shadowSm : null,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: QuestTypography.osButtonText.copyWith(
            color: fg,
            letterSpacing: 1.2,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
