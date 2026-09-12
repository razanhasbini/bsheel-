import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';

/// The horizontal checkpoint rail — a journey's primary visual language.
///
/// Not a percentage bar. A three-stage journey has three checkpoints, and
/// a bar at 66% says nothing about which of them you cleared, which one you
/// are standing on, or how many remain. Nodes are distributed across the
/// full width at `index / (count - 1)`, so the spacing itself carries the
/// structure.
///
/// [advanceFrom] drives the unlock transition: when set, the rail draws
/// itself as it was at that step and animates forward to the present. The
/// animation explains a change that has already happened on the server — it
/// never decides one, and when it finishes the new state simply stays.
class CheckpointRail extends StatefulWidget {
  const CheckpointRail({
    super.key,
    required this.stages,
    this.advanceFrom,
    this.showNumbers = true,
    this.height = 56,
    this.onFinished,
  });

  final List<JourneyStage> stages;

  /// The completed-count to animate FROM. Null renders the present state
  /// with no movement.
  final int? advanceFrom;

  final bool showNumbers;
  final double height;
  final VoidCallback? onFinished;

  @override
  State<CheckpointRail> createState() => _CheckpointRailState();
}

class _CheckpointRailState extends State<CheckpointRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  /// The three beats of §15: the cleared node confirms, the line runs, the
  /// newly opened node lands and pulses.
  late final Animation<double> _confirm = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.22, curve: Curves.easeOut));
  late final Animation<double> _line = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.22, 0.62, curve: Curves.easeInOutCubic));
  late final Animation<double> _land = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.58, 0.85, curve: Curves.elasticOut));
  late final Animation<double> _pulse = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.78, 1.0, curve: Curves.easeOut));

  bool _reducedMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Somebody who asked the system to stop animating things means it. The
    // state still transitions; it simply arrives rather than travels.
    _reducedMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.advanceFrom != null &&
        !_controller.isAnimating &&
        _controller.value == 0) {
      if (_reducedMotion) {
        _controller.value = 1;
        widget.onFinished?.call();
      } else {
        _controller.forward().then((_) => widget.onFinished?.call());
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _RailPainter(
            stages: widget.stages,
            advanceFrom: widget.advanceFrom,
            confirm: _confirm.value,
            line: _line.value,
            land: _land.value,
            pulse: _pulse.value,
            showNumbers: widget.showNumbers,
            numberColor: QuestColors.textDim(context),
          ),
        ),
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  _RailPainter({
    required this.stages,
    required this.advanceFrom,
    required this.confirm,
    required this.line,
    required this.land,
    required this.pulse,
    required this.showNumbers,
    required this.numberColor,
  });

  final List<JourneyStage> stages;
  final int? advanceFrom;
  final double confirm;
  final double line;
  final double land;
  final double pulse;
  final bool showNumbers;
  final Color numberColor;

  static const _nodeRadius = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (stages.isEmpty) return;
    final y = showNumbers ? size.height * 0.38 : size.height / 2;
    // Margins keep the end nodes on screen at any width, including the
    // 400px phone the whole app has to survive.
    const margin = 20.0;
    final usable = (size.width - margin * 2).clamp(1.0, double.infinity);
    double x(int index) => stages.length == 1
        ? size.width / 2
        : margin + usable * (index / (stages.length - 1));

    // Mid-animation the rail shows the PREVIOUS state and moves forward, so
    // the player watches the change rather than being handed the result.
    final animating = advanceFrom != null && line < 1;
    final effective = <StageState>[
      for (var i = 0; i < stages.length; i++)
        if (animating && advanceFrom != null && i >= advanceFrom!)
          // Everything from the advance point on is drawn as it was.
          (i == advanceFrom! ? StageState.underReview : StageState.locked)
        else
          stages[i].state,
    ];

    _paintConnectors(canvas, x, y, effective);
    for (var i = 0; i < stages.length; i++) {
      _paintNode(canvas, x(i), y, i, effective[i]);
      if (showNumbers) _paintNumber(canvas, x(i), size.height, i);
    }
  }

  void _paintConnectors(Canvas canvas, double Function(int) x, double y,
      List<StageState> states) {
    for (var i = 0; i < stages.length - 1; i++) {
      final from = Offset(x(i) + _nodeRadius, y);
      final to = Offset(x(i + 1) - _nodeRadius, y);
      final walked = states[i] == StageState.completed;
      // The one leg that is growing: out of the checkpoint that just
      // cleared, into the one that just opened.
      final growing = advanceFrom != null && i == advanceFrom! - 1;
      if (!walked && !growing) {
        _dashed(canvas, from, to);
        continue;
      }
      final paint = Paint()
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..color = QuestColors.osSuccess;
      final end = growing ? Offset.lerp(from, to, line)! : to;
      if (growing && line > 0) _dashed(canvas, end, to);
      canvas.drawLine(from, end, paint);
    }
  }

  void _paintNode(
      Canvas canvas, double cx, double y, int index, StageState state) {
    final isNew = advanceFrom != null && index == advanceFrom;
    final justCleared = advanceFrom != null && index == advanceFrom! - 1;

    var radius = _nodeRadius;
    if (isNew) radius *= land.clamp(0.0, 1.4);
    if (justCleared) radius *= 1 + 0.18 * confirm * (1 - confirm) * 4;
    if (radius <= 0) return;

    final tint = switch (state) {
      StageState.completed => QuestColors.osSuccess,
      StageState.underReview => QuestColors.osAccent,
      StageState.inProgress => QuestColors.osPrimary,
      StageState.rejected => QuestColors.osRed,
      StageState.available => QuestColors.osPrimary,
      StageState.locked => QuestColors.osSurface,
    };

    // The ring around the checkpoint that just opened: the eye needs one
    // place to land, and it is always the one you can act on.
    if (isNew && pulse > 0) {
      canvas.drawCircle(
        Offset(cx, y),
        radius + 5 + 14 * pulse,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - pulse).clamp(0.15, 1)
          ..color =
              QuestColors.osPrimary.withAlpha((150 * (1 - pulse)).round()),
      );
    }

    canvas.drawCircle(
        Offset(cx, y), radius + 2, Paint()..color = QuestColors.osTextPrimary);
    canvas.drawCircle(Offset(cx, y), radius, Paint()..color = tint);

    final glyph = switch (state) {
      StageState.completed => Icons.check_rounded,
      StageState.underReview => Icons.hourglass_top_rounded,
      StageState.inProgress => Icons.play_arrow_rounded,
      // Not a cross. The checkpoint was not lost — it is open again and the
      // player can walk back to it, which is what a "go again" glyph says
      // and a cross does not.
      StageState.rejected => Icons.refresh_rounded,
      StageState.available => Icons.play_arrow_rounded,
      StageState.locked => Icons.lock_rounded,
    };
    // The checkmark arrives with the confirm beat rather than being there
    // all along, so "cleared" reads as something that just happened.
    final opacity =
        (state == StageState.completed && index == (advanceFrom ?? -2) - 1)
            ? confirm
            : 1.0;
    _paintIcon(
        canvas,
        Offset(cx, y),
        glyph,
        radius,
        state == StageState.locked
            ? QuestColors.osTextMuted
            : QuestColors.onAccent(tint),
        opacity);
  }

  void _paintIcon(Canvas canvas, Offset at, IconData icon, double radius,
      Color color, double opacity) {
    if (opacity <= 0.02) return;
    final painter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(icon.codePoint),
        style: TextStyle(
          fontSize: radius * 1.1,
          fontFamily: icon.fontFamily,
          package: icon.fontPackage,
          color: color.withAlpha((255 * opacity).round()),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  void _paintNumber(Canvas canvas, double cx, double height, int index) {
    final painter = TextPainter(
      text: TextSpan(
        text: '${index + 1}',
        style: QuestTypography.osLabelSmall
            .copyWith(fontSize: 10, color: numberColor),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
        canvas, Offset(cx - painter.width / 2, height - painter.height - 2));
  }

  void _dashed(Canvas canvas, Offset from, Offset to) {
    final paint = Paint()
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..color = QuestColors.osTextMuted.withAlpha(110);
    const dash = 5.0;
    const gap = 4.0;
    final total = (to - from).distance;
    if (total <= 0) return;
    final step = (to - from) / total;
    for (var t = 0.0; t < total; t += dash + gap) {
      final end = (t + dash) > total ? total : t + dash;
      canvas.drawLine(from + step * t, from + step * end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RailPainter old) =>
      old.confirm != confirm ||
      old.line != line ||
      old.land != land ||
      old.pulse != pulse ||
      old.stages.length != stages.length ||
      old.advanceFrom != advanceFrom;
}
