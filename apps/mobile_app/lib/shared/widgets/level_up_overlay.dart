import 'dart:math';

import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

/// Full-screen "LEVEL UP!" celebration overlay with pixel-style confetti.
/// Auto-dismisses after 3 seconds or on tap.
class LevelUpOverlay extends StatefulWidget {
  const LevelUpOverlay({
    super.key,
    required this.newLevel,
    required this.onDismiss,
  });

  final int newLevel;
  final VoidCallback onDismiss;

  @override
  State<LevelUpOverlay> createState() => _LevelUpOverlayState();
}

class _LevelUpOverlayState extends State<LevelUpOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Material(
        color: Colors.transparent,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            // Fade in quickly, stay, fade out at end
            final t = _controller.value;
            final opacity = t < 0.1
                ? t / 0.1
                : t > 0.85
                    ? (1.0 - t) / 0.15
                    : 1.0;

            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: QuestColors.pureBlack.withAlpha(200),
                child: Stack(
                  children: [
                    // Pixel confetti
                    CustomPaint(
                      size: MediaQuery.of(context).size,
                      painter: _PixelConfettiPainter(progress: t),
                    ),
                    // Center content
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // "LEVEL UP!" text
                          Text(
                            'LEVEL UP!',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 4,
                              color: QuestColors.xpGold,
                              shadows: [
                                Shadow(
                                  color: QuestColors.xpGold.withAlpha(120),
                                  blurRadius: 24,
                                ),
                                Shadow(
                                  color: QuestColors.xpGold.withAlpha(60),
                                  blurRadius: 48,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: QuestSpacing.md),
                          // Level number
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: QuestSpacing.lg,
                              vertical: QuestSpacing.sm,
                            ),
                            decoration: BoxDecoration(
                              color: QuestColors.darkCard,
                              borderRadius: BorderRadius.circular(
                                QuestSpacing.radiusSm,
                              ),
                              border: Border.all(
                                color: QuestColors.xpGold.withAlpha(100),
                                width: 2,
                              ),
                            ),
                            child: Text(
                              'LEVEL ${widget.newLevel}',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 3,
                                color: QuestColors.xpGold,
                                shadows: [
                                  Shadow(
                                    color: QuestColors.xpGold.withAlpha(80),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: QuestSpacing.lg),
                          Text(
                            'TAP TO CONTINUE',
                            style: QuestTypography.labelSmall.copyWith(
                              color: QuestColors.textMuted,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Paints random colored small squares that rise and fall like confetti.
class _PixelConfettiPainter extends CustomPainter {
  _PixelConfettiPainter({required this.progress});

  final double progress;

  // Pre-generate confetti particles deterministically from a seed
  static final List<_ConfettiParticle> _particles = _generateParticles();

  static List<_ConfettiParticle> _generateParticles() {
    final rng = Random(42);
    const colors = [
      QuestColors.xpGold,
      QuestColors.successGreen,
      QuestColors.violet,
      QuestColors.softRed,
      QuestColors.accentYellow,
      QuestColors.successGreen,
      QuestColors.pureWhite,
    ];
    return List.generate(60, (i) {
      return _ConfettiParticle(
        x: rng.nextDouble(),
        startY: rng.nextDouble() * 0.3 + 0.85, // start near bottom
        endY: rng.nextDouble() * 0.6 - 0.1, // rise to top area
        size: rng.nextDouble() * 6 + 4,
        color: colors[rng.nextInt(colors.length)],
        drift: (rng.nextDouble() - 0.5) * 0.15,
        delay: rng.nextDouble() * 0.3,
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in _particles) {
      // Each particle starts after its delay
      final adjustedProgress = ((progress - p.delay) / (1.0 - p.delay))
          .clamp(0.0, 1.0);
      if (adjustedProgress <= 0) continue;

      final currentY = p.startY + (p.endY - p.startY) * adjustedProgress;
      final currentX = p.x + p.drift * adjustedProgress;

      // Fade out near end
      final alpha = adjustedProgress > 0.7
          ? ((1.0 - adjustedProgress) / 0.3 * 255).round()
          : 255;

      final paint = Paint()..color = p.color.withAlpha(alpha.clamp(0, 255));
      canvas.drawRect(
        Rect.fromLTWH(
          currentX * size.width,
          currentY * size.height,
          p.size,
          p.size,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PixelConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _ConfettiParticle {
  const _ConfettiParticle({
    required this.x,
    required this.startY,
    required this.endY,
    required this.size,
    required this.color,
    required this.drift,
    required this.delay,
  });

  final double x;
  final double startY;
  final double endY;
  final double size;
  final Color color;
  final double drift;
  final double delay;
}
