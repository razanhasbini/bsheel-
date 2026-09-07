import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Shared empty / error / loading widgets so every feature page renders
/// the three flavours of "nothing to show" identically. Replaces the
/// fragmented "TAP TO RETRY" treatments + tiny dim-text errors that
/// were inconsistent across home, feed, comments, notifications, etc.
/// (UX-105 / UX-106).

/// Empty state — friendly placeholder + optional CTA. Use when a list
/// is intentionally empty (no comments yet, no followers, etc.).
class BsheelEmptyState extends StatelessWidget {
  const BsheelEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    this.actionLabel,
  });

  final String title;
  final String? message;
  final IconData icon;
  final VoidCallback? action;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(QuestSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: QuestColors.textMuted),
            const SizedBox(height: QuestSpacing.md),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              style: QuestTypography.headlineSmall.copyWith(color: ink),
            ),
            if (message != null) ...[
              const SizedBox(height: QuestSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: QuestTypography.bodyMedium.copyWith(
                  color: QuestColors.textDim(context),
                ),
              ),
            ],
            if (action != null && actionLabel != null) ...[
              const SizedBox(height: QuestSpacing.lg),
              GestureDetector(
                onTap: action,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: QuestColors.osPrimary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: ink, width: 1.5),
                  ),
                  child: Text(
                    actionLabel!.toUpperCase(),
                    style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.osTextOnPrimary,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Error state — pre-mapped friendly message + retry button. Pass the
/// raw error and it routes through `mapDbError` so callers don't have
/// to remember.
class BsheelErrorState extends StatelessWidget {
  const BsheelErrorState({
    super.key,
    required this.error,
    required this.onRetry,
    this.action = 'load',
  });

  final Object error;
  final VoidCallback onRetry;

  /// Verb for the catch-all message ("Failed to {action}.").
  final String action;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(QuestSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: QuestColors.softRed),
            const SizedBox(height: QuestSpacing.md),
            Text(
              mapDbError(error, action: action),
              textAlign: TextAlign.center,
              style: QuestTypography.bodyMedium
                  .copyWith(color: ink, height: 1.4),
            ),
            const SizedBox(height: QuestSpacing.lg),
            GestureDetector(
              onTap: onRetry,
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: QuestColors.accentYellow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ink, width: 1.8),
                  boxShadow: [
                    BoxShadow(
                      color: ink,
                      offset: const Offset(2, 3),
                      blurRadius: 0,
                    ),
                  ],
                ),
                child: Text(
                  'TAP TO RETRY',
                  style: QuestTypography.labelSmall.copyWith(
                    color: QuestColors.accentYellowInk,
                    letterSpacing: 1.4,
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

/// Tiny inline loading state — circular progress in the brand color.
/// Use as the `loading:` branch of every `AsyncValue.when(...)`.
class BsheelLoading extends StatelessWidget {
  const BsheelLoading({super.key, this.size = 28});
  final double size;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: size,
        height: size,
        child: const CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor:
              AlwaysStoppedAnimation<Color>(QuestColors.osPrimary),
        ),
      ),
    );
  }
}

/// Single canonical confirm dialog. UX-209 / UX-210.
///
/// `destructive: true` flips the confirm button to coral red and prefixes
/// the action with the destructive verb so the row reads as e.g.
/// "DELETE PERMANENTLY". Returns true if the user confirmed.
Future<bool> showBsheelConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'CONFIRM',
  String cancelLabel = 'CANCEL',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      final ink = QuestColors.text(ctx);
      return AlertDialog(
        backgroundColor: QuestColors.cardBg(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: ink, width: 2),
        ),
        title: Text(
          title.toUpperCase(),
          style: QuestTypography.headlineSmall.copyWith(
            color: destructive ? QuestColors.softRed : ink,
            letterSpacing: 0.8,
          ),
        ),
        content: Text(
          message,
          style: QuestTypography.bodyMedium.copyWith(
            color: ink,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              cancelLabel.toUpperCase(),
              style: QuestTypography.labelSmall
                  .copyWith(color: QuestColors.textDim(ctx)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel.toUpperCase(),
              style: QuestTypography.labelSmall.copyWith(
                color: destructive
                    ? QuestColors.softRed
                    : QuestColors.osPrimary,
              ),
            ),
          ),
        ],
      );
    },
  );
  return result == true;
}
