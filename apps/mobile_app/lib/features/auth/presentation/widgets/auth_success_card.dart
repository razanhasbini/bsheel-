import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';

/// Green success card shared by the forgot-password ("email sent") and
/// reset-password ("password updated") flows: an ink-bordered check
/// circle next to an ALL-CAPS title and a short body message.
class AuthSuccessCard extends StatelessWidget {
  const AuthSuccessCard({
    super.key,
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return ArcadeCard(
      backgroundColor:
          QuestColors.osSuccess.withAlpha(QuestColors.alphaWhisper),
      borderColor: QuestColors.osSuccess,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: QuestColors.osSuccess,
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 2),
            ),
            child: Icon(
              Icons.check_rounded,
              color: QuestColors.onAccent(QuestColors.osSuccess),
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: QuestTypography.labelMedium.copyWith(
                    color: ink,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: QuestTypography.bodySmall.copyWith(
                    color: ink.withAlpha(QuestColors.alphaInkMuted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
