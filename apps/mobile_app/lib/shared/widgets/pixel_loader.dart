import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

/// 8-bit pixel loading spinner — 4 blocks that animate in sequence.
class PixelLoader extends StatefulWidget {
  const PixelLoader({super.key, this.size = 24});
  final double size;

  @override
  State<PixelLoader> createState() => _PixelLoaderState();
}

class _PixelLoaderState extends State<PixelLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = QuestColors.text(context);
    final blockSize = widget.size / 3;
    final gap = blockSize * 0.15;

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        // 4 steps: top-left, top-right, bottom-right, bottom-left
        final step = (_ctrl.value * 4).floor() % 4;

        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _block(blockSize, gap, color, step == 0),
                  SizedBox(height: gap),
                  _block(blockSize, gap, color, step == 3),
                ],
              ),
              SizedBox(width: gap),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _block(blockSize, gap, color, step == 1),
                  SizedBox(height: gap),
                  _block(blockSize, gap, color, step == 2),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _block(double size, double gap, Color color, bool active) {
    return Container(
      width: size,
      height: size,
      color: active ? color : color.withAlpha(40),
    );
  }
}
