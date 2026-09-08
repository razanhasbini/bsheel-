import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

class PixelAvatar extends StatelessWidget {
  const PixelAvatar({
    super.key,
    this.imageUrl,
    this.username = '?',
    this.size = 44,
    this.borderColor,
  });

  final String? imageUrl;
  final String username;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBorder =
        isDark ? cs.onSurface.withAlpha(51) : QuestColors.osTextPrimary;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
        border: Border.all(
          color: borderColor ?? defaultBorder,
          width: 2,
        ),
        color: cs.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl != null
          ? Image.network(
              imageUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(context),
            )
          : _fallback(context),
    );
  }

  Widget _fallback(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: QuestTypography.headlineSmall.copyWith(
          color: isDark
              ? Theme.of(context).colorScheme.primary
              : QuestColors.osTextPrimary,
          fontSize: size * 0.35,
        ),
      ),
    );
  }
}
