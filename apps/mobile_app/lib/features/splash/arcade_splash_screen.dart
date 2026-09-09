// ============================================================================
// ArcadeSplashScreen — the design's splash frame (export/mobile/15-splash.jpg)
// ============================================================================
//
// An ink panel, centred, with four things stacked on it and nothing else:
//
//   96x96 gold squircle, r24, 2px CREAM outline, "B" in Syne 800/44
//   BSHEEL          Syne 800 / 42 / -0.04em, cream
//   ONE QUEST · LIMITED TIME   mono 10 / 700 / 0.16em, lavender
//   three 10px dots — gold, violet, ink-border — 24 below the tagline
//
// The frame draws no status bar and no decorative shapes; the earlier cream
// variant (yellow blob, violet squircle, pixel grid, sweeping loader bar) was
// not in the design at all and has been removed.
//
// `onReady` still fires exactly once, from `_entry`'s status listener, when
// the entry animation completes. `app_router.dart` depends on it to leave the
// splash — it is the only way off this screen.
// ============================================================================

import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ArcadeSplashScreen extends StatefulWidget {
  /// Called once the splash entry animation completes.
  final VoidCallback? onReady;

  /// Total duration before [onReady] fires.
  final Duration duration;

  const ArcadeSplashScreen({
    super.key,
    this.onReady,
    this.duration = const Duration(milliseconds: 2400),
  });

  @override
  State<ArcadeSplashScreen> createState() => _ArcadeSplashScreenState();
}

class _ArcadeSplashScreenState extends State<ArcadeSplashScreen>
    with TickerProviderStateMixin {
  /// The splash ground. The design paints `#1A1330` here — the same value the
  /// rest of the app uses as ink — so the token that carries it exactly is
  /// [QuestColors.osTextPrimary]. This is one of the "ink panels" the palette
  /// documents: a dark surface inside the light theme, where white/cream type
  /// is the correct choice.
  static const _inkPanel = QuestColors.osTextPrimary;

  /// Entry: one-shot fade/rise. `_loop` drives a small sequential bob on the
  /// three dots so the screen reads as loading rather than frozen; it never
  /// changes their colours, which are fixed by the frame.
  late final AnimationController _entry;
  late final AnimationController _loop;
  bool _onReadyFired = false;

  @override
  void initState() {
    super.initState();
    _entry = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
    _loop = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _entry.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_onReadyFired) {
        _onReadyFired = true;
        widget.onReady?.call();
      }
    });
  }

  @override
  void dispose() {
    _entry.dispose();
    _loop.dispose();
    super.dispose();
  }

  double _phase(double start, double end, Curve curve) {
    final raw = ((_entry.value - start) / (end - start)).clamp(0.0, 1.0);
    return curve.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    // A dark ground needs light status-bar glyphs; the default light theme
    // asks for dark ones, which are invisible here.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: _inkPanel,
        systemNavigationBarColor: _inkPanel,
      ),
      child: Scaffold(
        backgroundColor: _inkPanel,
        body: AnimatedBuilder(
          animation: Listenable.merge([_entry, _loop]),
          builder: (context, _) {
            final markT = _phase(0.0, 0.4, Curves.easeOutCubic);
            final wordT = _phase(0.12, 0.52, Curves.easeOutCubic);
            final taglineT = _phase(0.24, 0.62, Curves.easeOut);
            final dotsT = _phase(0.36, 0.7, Curves.easeOut);

            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Rise(t: markT, distance: 14, child: const _BrandMark()),
                  // The frame's column gap is 18 between all four children,
                  // and the dot row carries an extra 24 of top margin.
                  const SizedBox(height: 18),
                  _Rise(t: wordT, distance: 12, child: const _Wordmark()),
                  const SizedBox(height: 18),
                  _Rise(t: taglineT, distance: 8, child: const _Tagline()),
                  const SizedBox(height: 42),
                  Opacity(
                    opacity: dotsT,
                    child: _LoadingDots(phase: _loop.value),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Fades a child in while lifting it [distance] logical pixels into place.
class _Rise extends StatelessWidget {
  const _Rise({required this.t, required this.distance, required this.child});

  final double t;
  final double distance;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: t.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, (1 - t) * distance),
        child: child,
      ),
    );
  }
}

// ── Brand mark ──────────────────────────────────────────────────────────────

/// 96x96 gold squircle at r24 with a 2px cream outline and a Syne 800 "B".
///
/// The outline is cream, not ink: on an ink ground an ink border would be
/// invisible, which is why this is the one place in the app whose 2px stroke
/// is not [QuestColors.osTextPrimary].
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      // 96 of content inside the 2px stroke.
      width: 100,
      height: 100,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: QuestColors.osAccent,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: QuestColors.osBg, width: 2),
      ),
      child: Text(
        'B',
        style: QuestTypography.osDisplayLarge.copyWith(
          fontSize: 44,
          height: 1,
          letterSpacing: 0,
          // Gold ground: ink, never white.
          color: QuestColors.onAccent(QuestColors.osAccent),
        ),
      ),
    );
  }
}

// ── Wordmark ────────────────────────────────────────────────────────────────

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return Text(
      'BSHEEL',
      maxLines: 1,
      style: QuestTypography.osDisplayLarge.copyWith(
        fontSize: 42,
        height: 1,
        // -0.04em at 42px.
        letterSpacing: -1.68,
        color: QuestColors.osBg,
      ),
    );
  }
}

class _Tagline extends StatelessWidget {
  const _Tagline();

  @override
  Widget build(BuildContext context) {
    return Text(
      'ONE QUEST · LIMITED TIME',
      maxLines: 1,
      style: QuestTypography.osLabelSmall.copyWith(
        fontSize: 10,
        // 0.16em at 10px.
        letterSpacing: 1.6,
        height: 1.4,
        color: QuestColors.textSecondary,
      ),
    );
  }
}

// ── Loading dots ────────────────────────────────────────────────────────────

/// Three 10px dots, 6 apart: gold, violet, ink-border. Colours are fixed by
/// the frame; only a 3px sequential bob moves.
class _LoadingDots extends StatelessWidget {
  const _LoadingDots({required this.phase});

  /// 0..1, cycling.
  final double phase;

  static const _colors = [
    QuestColors.osAccent,
    QuestColors.osPrimary,
    QuestColors.border,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < _colors.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Transform.translate(
            offset: Offset(0, _bob(i)),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _colors[i],
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// A short hop that passes along the row, one dot at a time.
  double _bob(int index) {
    const window = 0.34;
    final start = index * window * 0.9;
    final local = ((phase - start) / window).clamp(0.0, 1.0);
    return -math.sin(local * math.pi) * 3;
  }
}
