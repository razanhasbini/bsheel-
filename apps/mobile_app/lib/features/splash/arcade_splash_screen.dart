// ============================================================================
// ArcadeSplashScreen — Bsheel brand splash (minimal cream variant)
// ============================================================================
//
// Calm cream-bg splash matching the brand wordmark composition: chunky
// "BSHEEL" centered, a yellow organic blob in the top-right, a violet
// rounded shape in the bottom-left, faint grid backdrop. Subtle bob on the
// shapes and a soft breathing scale on the wordmark keep it alive without
// turning into a gamified intro. `onReady` fires once the entry settles.
// ============================================================================

import 'dart:math' as math;
import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

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
  static const _cream = QuestColors.osBg;
  static const _ink = QuestColors.osTextPrimary;
  static const _violet = QuestColors.violet;
  static const _gold = QuestColors.accentYellow;

  // Entry: one-shot fade/slide-in. `_loop` runs forever and drives the
  // gentle bob on the shapes + the breathing scale on the wordmark — both
  // small enough to read as "alive" rather than animated.
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
      duration: const Duration(seconds: 6),
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
    return Scaffold(
      backgroundColor: _cream,
      body: AnimatedBuilder(
        animation: Listenable.merge([_entry, _loop]),
        builder: (context, _) {
          final blobT = _phase(0.0, 0.45, Curves.easeOutCubic);
          final shapeT = _phase(0.05, 0.5, Curves.easeOutCubic);
          final wordT = _phase(0.2, 0.7, Curves.easeOutBack);
          final loaderT = _phase(0.45, 0.75, Curves.easeOut);
          // Continuous motion. Each shape has its own phase + amplitude so
          // they never bob in sync — that's what makes the page feel alive.
          final loopRad = _loop.value * math.pi * 2;
          final blobBob = math.sin(loopRad) * 14;
          final blobDrift = math.cos(loopRad * 0.7) * 8;
          final blobSpin = math.sin(loopRad * 0.5) * 0.07;
          final blobScale = 1 + math.sin(loopRad * 0.7) * 0.025;
          final shapeBob = math.sin(loopRad + math.pi * 0.6) * 12;
          final shapeDrift = math.cos(loopRad * 0.7 + 0.9) * 7;
          final shapeSpin = math.sin(loopRad * 0.5 + 0.4) * 0.06;
          final shapeScale = 1 + math.sin(loopRad * 0.7 + 1.2) * 0.022;
          final wordBreathe = 1 + math.sin(loopRad * 0.5) * 0.012;
          // Loader pill sweeps faster than the bobs (~1s per sweep) so a
          // full pass finishes inside the splash's visible window. Pulse
          // tracks the pill's progress and gives the bar a soft thickness
          // wobble around the leading edge.
          final loaderFill = (_loop.value * 6) % 1.0;
          final loaderPulse = 0.85 + math.sin(loaderFill * math.pi) * 0.15;
          return Stack(
            fit: StackFit.expand,
            children: [
              const _PixelGrid(),
              Positioned(
                top: -90,
                right: -60,
                child: Opacity(
                  opacity: blobT,
                  child: Transform.translate(
                    offset: Offset(blobDrift, (1 - blobT) * -16 + blobBob),
                    child: Transform.rotate(
                      angle: blobSpin,
                      child: Transform.scale(
                        scale: blobScale,
                        child: const _YellowBlob(size: 320),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -90,
                left: -70,
                child: Opacity(
                  opacity: shapeT,
                  child: Transform.translate(
                    offset: Offset(shapeDrift, (1 - shapeT) * 16 + shapeBob),
                    child: Transform.rotate(
                      angle: shapeSpin,
                      child: Transform.scale(
                        scale: shapeScale,
                        child: const _VioletShape(size: 300),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: wordT.clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset: Offset(0, (1 - wordT) * 12),
                        child: Transform.scale(
                          scale: wordBreathe,
                          child: const _Wordmark(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Opacity(
                      opacity: loaderT,
                      child: Transform.translate(
                        offset: Offset(0, (1 - loaderT) * 6),
                        child: _LoadingLine(
                          progress: loaderFill,
                          pulse: loaderPulse,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Background grid ─────────────────────────────────────────────────────────

class _PixelGrid extends StatelessWidget {
  const _PixelGrid();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(painter: _GridPainter(), size: Size.infinite),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = QuestColors.osBorderStrong.withAlpha(13)
      ..strokeWidth = 1;
    const step = 28.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ── Wordmark ────────────────────────────────────────────────────────────────

class _Wordmark extends StatelessWidget {
  const _Wordmark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'BSHEEL',
      style: TextStyle(
        fontFamily: 'Syne',
        fontVariations: [FontVariation('wght', 800)],
        fontWeight: FontWeight.w800,
        fontSize: 44,
        height: 0.95,
        letterSpacing: -1.6,
        color: _ArcadeSplashScreenState._ink,
      ),
    );
  }
}

// ── Decorative shapes (match brand asset composition) ───────────────────────

class _YellowBlob extends StatelessWidget {
  const _YellowBlob({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.18,
      child: CustomPaint(
        size: Size(size, size),
        painter: _BlobPainter(
          fill: _ArcadeSplashScreenState._gold,
          stroke: _ArcadeSplashScreenState._ink,
        ),
      ),
    );
  }
}

class _BlobPainter extends CustomPainter {
  _BlobPainter({required this.fill, required this.stroke});
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Hand-drawn-style oval that's a little wider on top and pinches
    // bottom-left, like the brand handoff. Built from cubic curves so
    // it never looks like a perfect ellipse.
    final path = Path()
      ..moveTo(w * 0.12, h * 0.42)
      ..cubicTo(w * 0.05, h * 0.18, w * 0.45, h * -0.05, w * 0.78, h * 0.10)
      ..cubicTo(w * 1.05, h * 0.30, w * 1.05, h * 0.70, w * 0.78, h * 0.88)
      ..cubicTo(w * 0.50, h * 1.05, w * 0.18, h * 0.92, w * 0.10, h * 0.72)
      ..cubicTo(w * 0.04, h * 0.60, w * 0.16, h * 0.55, w * 0.12, h * 0.42)
      ..close();

    // Ink shadow underneath, offset down-left to match the brand stroke
    // style (the rest of the app uses the same chunky shadow pattern).
    canvas.save();
    canvas.translate(-4, 8);
    canvas.drawPath(path, Paint()..color = stroke);
    canvas.restore();

    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) =>
      old.fill != fill || old.stroke != stroke;
}

class _VioletShape extends StatelessWidget {
  const _VioletShape({required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.08,
      child: CustomPaint(
        size: Size(size, size),
        painter: _SquirclePainter(
          fill: _ArcadeSplashScreenState._violet,
          stroke: _ArcadeSplashScreenState._ink,
        ),
      ),
    );
  }
}

class _SquirclePainter extends CustomPainter {
  _SquirclePainter({required this.fill, required this.stroke});
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Rounded rectangle with one extra-rounded corner top-right, matching
    // the brand asset (squircle pulled toward the wordmark).
    final path = Path()
      ..moveTo(w * 0.05, h * 0.05)
      ..lineTo(w * 0.55, h * 0.05)
      ..cubicTo(w * 0.95, h * 0.05, w * 0.95, h * 0.55, w * 0.95, h * 0.85)
      ..cubicTo(w * 0.95, h * 0.92, w * 0.92, h * 0.95, w * 0.85, h * 0.95)
      ..lineTo(w * 0.18, h * 0.95)
      ..cubicTo(w * 0.10, h * 0.95, w * 0.05, h * 0.90, w * 0.05, h * 0.82)
      ..lineTo(w * 0.05, h * 0.18)
      ..cubicTo(w * 0.05, h * 0.10, w * 0.05, h * 0.05, w * 0.05, h * 0.05)
      ..close();

    canvas.save();
    canvas.translate(-5, 9);
    canvas.drawPath(path, Paint()..color = stroke);
    canvas.restore();

    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = stroke
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SquirclePainter old) =>
      old.fill != fill || old.stroke != stroke;
}

// ── Loader line ─────────────────────────────────────────────────────────────

/// Chunky "scanner" bar under the wordmark. A violet→coral gradient pill
/// sweeps left → right with a soft thickness pulse at its leading edge,
/// then flies out the right side and re-enters from the left.
class _LoadingLine extends StatelessWidget {
  const _LoadingLine({required this.progress, required this.pulse});

  /// Cycles 0 → 1 forever; the pill's leading edge tracks this value.
  final double progress;

  /// Eased value (~0.85 → 1.0) that thickens the pill's middle and dims
  /// it again at the edges of each sweep — gives the bar more life than
  /// a flat-color block.
  final double pulse;

  @override
  Widget build(BuildContext context) {
    const trackWidth = 168.0;
    const trackHeight = 9.0;
    const pillFraction = 0.32;
    const ink = QuestColors.osBorderStrong;
    const violet = QuestColors.violet;
    const gold = QuestColors.accentYellow;
    // Pill enters from `-pillFraction` and exits at `1.0` so the leading
    // edge slides cleanly off the right and back in from the left.
    final start = (progress * (1 + pillFraction)) - pillFraction;
    final visibleStart = start.clamp(0.0, 1.0);
    final visibleEnd = (start + pillFraction).clamp(0.0, 1.0);
    final fillWidth = (visibleEnd - visibleStart) * trackWidth;
    final leftOffset = visibleStart * trackWidth;

    return SizedBox(
      width: trackWidth,
      height: trackHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Track
          Container(
            decoration: BoxDecoration(
              color: ink.withAlpha(36),
              borderRadius: BorderRadius.circular(trackHeight / 2),
              border: Border.all(color: ink.withAlpha(48), width: 1),
            ),
          ),
          // Sweeping pill — gradient + pulsing alpha at the head.
          if (fillWidth > 0)
            Positioned(
              left: leftOffset,
              top: 0,
              bottom: 0,
              width: fillWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [violet, gold],
                  ),
                  borderRadius: BorderRadius.circular(trackHeight / 2),
                  boxShadow: [
                    BoxShadow(
                      color: violet.withAlpha((110 * pulse).round()),
                      blurRadius: 10 * pulse,
                      spreadRadius: 0.5,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
