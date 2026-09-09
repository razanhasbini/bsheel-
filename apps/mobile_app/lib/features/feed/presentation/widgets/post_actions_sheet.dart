import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:app_core/app_core.dart';

import '../../../../design/bs_widgets.dart';
import '../../../../core/config/deep_link_config.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/backend/app_backend.dart';

/// Bottom sheet for the "..." menu on a Reels card. Surfaces SHARE and
/// REPORT, plus a CANCEL row. Tapping outside dismisses without action.
Future<void> showPostActionsSheet(
  BuildContext context, {
  required WidgetRef ref,
  required String postId,
  required String postUsername,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: false,
    backgroundColor: Colors.transparent,
    barrierColor: QuestColors.pureBlack.withAlpha(120),
    useSafeArea: true,
    useRootNavigator: true,
    builder: (sheetCtx) => _PostActionsSheet(
      ref: ref,
      postId: postId,
      postUsername: postUsername,
    ),
  );
}

class _PostActionsSheet extends StatelessWidget {
  const _PostActionsSheet({
    required this.ref,
    required this.postId,
    required this.postUsername,
  });

  final WidgetRef ref;
  final String postId;
  final String postUsername;

  Future<void> _share(BuildContext context) async {
    Navigator.of(context).maybePop();
    HapticFeedback.selectionClick();
    ref.read(analyticsProvider).postShared(postId);
    await SharePlus.instance.share(
      ShareParams(
        text:
            'Check out this quest by @$postUsername on BSHEEL!\n\n${DeepLinkConfig.postLink(postId)}',
      ),
    );
  }

  Future<void> _report(BuildContext context) async {
    Navigator.of(context).maybePop();
    HapticFeedback.selectionClick();
    final reason = await _askReportReason(context);
    if (reason == null || reason.isEmpty) return;
    try {
      await AppBackend.repositories.account.reportContent(
        type: 'submission',
        id: postId,
        reason: reason,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Report submitted. Thank you.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapDbError(e, action: 'report post'))),
        );
      }
    }
  }

  Future<String?> _askReportReason(BuildContext context) {
    final controller = TextEditingController();
    final ink = QuestColors.text(context);
    return showDialog<String>(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: QuestColors.cardBg(c),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: ink, width: 2),
            boxShadow: [
              BoxShadow(
                color: ink,
                offset: const Offset(0, 5),
                blurRadius: 0,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: QuestColors.softRed,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: ink, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.flag_rounded,
                        color: QuestColors.onAccent(QuestColors.softRed),
                        size: 20),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'REPORT POST',
                    style: QuestTypography.headlineSmall.copyWith(
                      color: ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: QuestColors.bg(c),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ink, width: 1.5),
                ),
                child: TextField(
                  controller: controller,
                  maxLines: 3,
                  minLines: 3,
                  style: QuestTypography.bodyMedium.copyWith(color: ink),
                  cursorColor: QuestColors.softRed,
                  decoration: InputDecoration(
                    hintText: 'Why are you reporting this?',
                    hintStyle: QuestTypography.bodyMedium.copyWith(
                      color: QuestColors.textDim(c),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(c),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: QuestColors.cardBg(c),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ink, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'CANCEL',
                          style: QuestTypography.labelMedium.copyWith(
                            color: ink,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.pop(c, controller.text.trim()),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        constraints:
                            const BoxConstraints(minHeight: kMinTouchTarget),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: QuestColors.softRed,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: ink, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: ink,
                              offset: const Offset(0, 3),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          'REPORT',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: QuestTypography.labelMedium.copyWith(
                            color: QuestColors.onAccent(QuestColors.softRed),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: QuestColors.bg(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(color: ink, offset: const Offset(0, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 6),
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: ink.withAlpha(80),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          _ActionRow(
            icon: Icons.ios_share_rounded,
            label: 'SHARE',
            tint: QuestColors.osPrimary,
            onTap: () => _share(context),
          ),
          Container(height: 1, color: ink.withAlpha(30)),
          _ActionRow(
            icon: Icons.flag_rounded,
            label: 'REPORT',
            tint: QuestColors.softRed,
            onTap: () => _report(context),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tint.withAlpha(40),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: tint.withAlpha(160), width: 1.5),
              ),
              child: Icon(icon, color: tint, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: QuestTypography.labelMedium.copyWith(
                  color: ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: ink.withAlpha(120), size: 18),
          ],
        ),
      ),
    );
  }
}
