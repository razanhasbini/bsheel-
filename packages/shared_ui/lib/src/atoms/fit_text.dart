import 'package:flutter/material.dart';

/// Renders [text] on a single line, shrinking the font down to [minFontSize]
/// just enough so the full string fits within the parent's width.
///
/// Behaves like a normal [Text] when the text already fits; only shrinks when
/// it would otherwise overflow. Falls back to ellipsis if even [minFontSize]
/// is not small enough (e.g. unbounded width or extreme strings).
class FitText extends StatelessWidget {
  const FitText(
    this.text, {
    super.key,
    required this.style,
    this.minFontSize = 10,
    this.textAlign,
    this.stepSize = 0.5,
  });

  final String text;
  final TextStyle style;
  final double minFontSize;
  final TextAlign? textAlign;
  final double stepSize;

  @override
  Widget build(BuildContext context) {
    final maxFs = style.fontSize ?? 14;
    return LayoutBuilder(builder: (context, constraints) {
      final maxW = constraints.maxWidth;
      if (!maxW.isFinite || maxW <= 0 || text.isEmpty) {
        return Text(
          text,
          style: style,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          textAlign: textAlign,
        );
      }

      final scaler = MediaQuery.textScalerOf(context);
      double fs = maxFs;
      while (fs > minFontSize) {
        final tp = TextPainter(
          text: TextSpan(text: text, style: style.copyWith(fontSize: fs)),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout(maxWidth: double.infinity);
        if (tp.size.width <= maxW) break;
        fs -= stepSize;
      }
      if (fs < minFontSize) fs = minFontSize;

      return Text(
        text,
        style: style.copyWith(fontSize: fs),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
      );
    });
  }
}
