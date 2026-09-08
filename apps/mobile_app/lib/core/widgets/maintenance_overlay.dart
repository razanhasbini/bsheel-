import 'dart:math' as math;

import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_config_provider.dart';

/// Wraps a child widget. When `maintenance_mode` is `true` in
/// `app_config`, paints a blocking arcade-pop "under maintenance"
/// panel over it. Theme intentionally mirrors the splash screen
/// (cream bg, sun rays, ink + chunky shadows) so the mode-switch
/// reads as deliberate brand state rather than a crash.
class MaintenanceOverlay extends ConsumerWidget {
  const MaintenanceOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inMaintenance = ref.watch(maintenanceModeProvider);
    final customMessage = ref.watch(maintenanceMessageProvider);
    return Stack(
      children: [
        child,
        if (inMaintenance)
          Positioned.fill(child: _MaintenancePanel(message: customMessage)),
      ],
    );
  }
}

class _MaintenancePanel extends StatelessWidget {
  const _MaintenancePanel({required this.message});

  final String? message;

  static const _cream = QuestColors.osBg;
  static const _ink = QuestColors.osTextPrimary;
  static const _coral = QuestColors.osRed;
  static const _gold = QuestColors.accentYellow;
  static const _violet = QuestColors.violet;
  static const _sky = QuestColors.osCool;
  static const _green = QuestColors.osSuccess;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cream,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Subtle pixel grid — same trick the splash uses for the
          // arcade backdrop.
          const IgnorePointer(child: _PixelGrid()),
          // Static sun-ray wedges (no rotation animation here — this
          // screen should feel calm, not busy).
          Center(
            child: SizedBox(
              width: 600,
              height: 600,
              child: CustomPaint(painter: _RaysPainter()),
            ),
          ),
          // A handful of floating shapes for visual rhythm.
          const _Shape(
              left: 32,
              top: 110,
              size: 38,
              color: _coral,
              radius: 10,
              rot: -18),
          const _Shape(
              right: 38, top: 150, size: 28, color: _gold, radius: 999),
          const _Shape(
              right: 26, top: 260, size: 24, color: _green, radius: 6, rot: 22),
          const _Shape(
              left: 28,
              bottom: 210,
              size: 32,
              color: _sky,
              radius: 10,
              rot: -12),
          const _Shape(
              right: 46, bottom: 280, size: 20, color: _violet, radius: 999),

          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Big chunky icon tile in coral so it reads as
                    // "deliberate state", not "error".
                    Container(
                      width: 108,
                      height: 108,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _coral,
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: _ink, width: 3),
                        boxShadow: const [
                          BoxShadow(color: _ink, offset: Offset(5, 6)),
                        ],
                      ),
                      child: const Icon(
                        Icons.build_rounded,
                        size: 56,
                        color: QuestColors.osTextOnPrimary,
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text(
                      'UNDER MAINTENANCE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Syne',
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        height: 1.05,
                        letterSpacing: 1.4,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message ??
                          'BSHEEEL is getting a quick tune-up.\n'
                              'We\'ll be back in a few minutes.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'DMSans',
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        height: 1.45,
                        color: _ink.withAlpha(190),
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Decorative ribbon / stamp — purely aesthetic.
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: _gold,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _ink, width: 2.5),
                        boxShadow: const [
                          BoxShadow(color: _ink, offset: Offset(2, 3)),
                        ],
                      ),
                      child: const Text(
                        'PLEASE CHECK BACK SOON',
                        style: TextStyle(
                          fontFamily: 'Syne',
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 1.6,
                          color: _ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom stamp matching splash treatment.
          Positioned(
            bottom: 22,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'BSHEEEL · ARCADE QUESTS',
                style: TextStyle(
                  fontFamily: 'DMSans',
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                  letterSpacing: 2.0,
                  color: _ink.withAlpha(140),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PixelGrid extends StatelessWidget {
  const _PixelGrid();

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const RadialGradient(
        center: Alignment.center,
        radius: 0.8,
        colors: [QuestColors.pureBlack, Colors.transparent],
        stops: [0.5, 1.0],
      ).createShader(rect),
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
    const step = 16.0;
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

class _RaysPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = QuestColors.osSurface;
    const count = 20;
    const innerR = 100.0;
    const outerR = 260.0;
    const wedge = (math.pi * 2) / count;
    for (var i = 0; i < count; i++) {
      if (i.isOdd) continue;
      final start = i * wedge;
      final path = Path()
        ..moveTo(center.dx + math.cos(start) * innerR,
            center.dy + math.sin(start) * innerR)
        ..lineTo(center.dx + math.cos(start) * outerR,
            center.dy + math.sin(start) * outerR)
        ..arcToPoint(
          Offset(center.dx + math.cos(start + wedge) * outerR,
              center.dy + math.sin(start + wedge) * outerR),
          radius: const Radius.circular(outerR),
        )
        ..lineTo(center.dx + math.cos(start + wedge) * innerR,
            center.dy + math.sin(start + wedge) * innerR)
        ..arcToPoint(
          Offset(center.dx + math.cos(start) * innerR,
              center.dy + math.sin(start) * innerR),
          radius: const Radius.circular(innerR),
          clockwise: false,
        )
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Shape extends StatelessWidget {
  const _Shape({
    this.left,
    this.right,
    this.top,
    this.bottom,
    required this.size,
    required this.color,
    required this.radius,
    this.rot = 0,
  });

  final double? left, right, top, bottom;
  final double size;
  final Color color;
  final double radius;
  final double rot;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: rot * math.pi / 180,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(radius),
              border: Border.all(
                color: QuestColors.osBorderStrong,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(
                  color: QuestColors.osBorderStrong,
                  offset: Offset(2, 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
