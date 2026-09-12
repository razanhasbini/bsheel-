import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:app_core/app_core.dart';

import 'package:http/http.dart' as http;

import '../../../../core/config/branded_media.dart';
import '../../../../core/config/share_template.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../settings/data/blocked_users_provider.dart';
import '../providers/feed_provider.dart';

/// Bottom sheet for the "..." menu on a Reels card. Surfaces SHARE and
/// REPORT, plus a CANCEL row. Tapping outside dismisses without action.
Future<void> showPostActionsSheet(
  BuildContext context, {
  required WidgetRef ref,
  required String postId,
  required String postUsername,
  String? postUserId,
  String? questTitle,
  String? questCountryName,
  String? caption,
  String? mediaUrl,
  String? mediaType,
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
      postUserId: postUserId,
      questTitle: questTitle,
      questCountryName: questCountryName,
      caption: caption,
      mediaUrl: mediaUrl,
      mediaType: mediaType,
      pageContext: context,
    ),
  );
}

class _PostActionsSheet extends StatelessWidget {
  const _PostActionsSheet({
    required this.ref,
    required this.postId,
    required this.postUsername,
    required this.pageContext,
    this.postUserId,
    this.questTitle,
    this.questCountryName,
    this.caption,
    this.mediaUrl,
    this.mediaType,
  });

  final WidgetRef ref;
  final String postId;
  final String postUsername;
  final String? questTitle;
  final String? questCountryName;
  final String? caption;
  final String? mediaUrl;
  final String? mediaType;
  final String? postUserId;
  final BuildContext pageContext;

  Future<void> _block(BuildContext context) async {
    Navigator.of(context).pop();
    final confirmed = await showDialog<bool>(
        context: pageContext,
        builder: (dialog) => AlertDialog(
                title: Text('BLOCK @$postUsername?'),
                content: const Text(
                    'Their posts will be removed from your feed. You can unblock them in Settings.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('KEEP')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('BLOCK'))
                ]));
    if (confirmed != true || !pageContext.mounted) return;
    try {
      await AppBackend.repositories.account.blockUser(postUserId!);
      if (!pageContext.mounted) return;
      ref.invalidate(feedProvider);
      ref.invalidate(blockedUsersProvider);
      ScaffoldMessenger.of(pageContext)
          .showSnackBar(const SnackBar(content: Text('User blocked.')));
    } catch (_) {
      if (pageContext.mounted) {
        ScaffoldMessenger.of(pageContext).showSnackBar(const SnackBar(
            content: Text('Could not block user. Please try again.')));
      }
    }
  }

  /// Saves the proof with the Bsheel template baked into it.
  ///
  /// A link carries the template as text, but a photo in somebody's camera
  /// roll arrives with nothing attached — no quest, no place, no Bsheel. The
  /// band is drawn into the image so a reposted photo still says where it
  /// came from.
  ///
  /// Video gets the same band, burned in on the worker rather than here:
  /// re-encoding is a transcoding dependency and a long wait on a phone, and
  /// the worker already has ffmpeg. The app asks for the render, waits up to
  /// ninety seconds, and saves the plain clip (saying so) if it is not ready
  /// — the share text carries the template either way.
  Future<void> _save(BuildContext context) async {
    Navigator.of(context).maybePop();
    final page = pageContext;
    HapticFeedback.selectionClick();
    final url = mediaUrl;
    if (url == null || url.isEmpty) return;

    if (!page.mounted) return;
    _tell(page, 'Preparing…');
    try {
      final isVideo = (mediaType ?? '').toLowerCase().contains('video');

      // Videos are branded on the worker (ffmpeg burns the same band photos
      // get on the phone). Ask, wait, and fall back to the plain clip — with
      // a word about it — if the render is not ready in time. The original
      // is always there; the band is the upgrade.
      var downloadUrl = url;
      if (isVideo) {
        _tell(page, 'Adding the Bsheel band to the video…');
        try {
          final export =
              await AppBackend.repositories.mediaExports.awaitBranded(postId);
          if (export.isReady) {
            downloadUrl = export.downloadUrl!;
          } else if (page.mounted) {
            _tell(page,
                'The branded version is still rendering — saving the plain video.');
          }
        } catch (_) {
          // The export endpoint being down must not cost the user the save.
        }
      }

      final response = await http.get(Uri.parse(downloadUrl));
      if (response.statusCode != 200) throw Exception('download failed');

      Uint8List bytes = response.bodyBytes;
      var extension = isVideo ? 'mp4' : 'jpg';
      if (!isVideo) {
        final branded = await BrandedMedia.brand(
          bytes,
          questTitle: questTitle ?? '',
          country: questCountryName,
          caption: caption,
          username: postUsername,
        );
        // A photo we could not decode is still the photo they asked for, so
        // it saves unbranded rather than failing.
        if (branded != null) {
          bytes = branded;
          extension = 'png';
        }
      }

      // Handed over as bytes, never through a temp file.
      //
      // This is what was broken: the save wrote to getTemporaryDirectory()
      // and wrapped a dart:io File, and neither of those exists on the web
      // build. Every SAVE in a browser threw before it reached the share
      // sheet and landed in the catch below as "Could not save that",
      // which described the symptom and hid the cause. XFile.fromData needs
      // no filesystem and behaves the same on every platform.
      final name =
          'bsheel_${postId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '')}.$extension';
      final mimeType = isVideo ? 'video/mp4' : 'image/png';

      // The system sheet is what offers "Save to Photos" / "Save to Files",
      // and on the web it becomes a download. Going through it avoids a
      // gallery plugin and the photo-library permission that comes with one.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: mimeType, name: name)],
          // The web implementation reads the filename from here, not from
          // the XFile — without it the download arrives as "file" with no
          // extension and the browser will not open it.
          fileNameOverrides: [name],
          text: ShareTemplate.quest(
            postId: postId,
            questTitle: questTitle ?? '',
            country: questCountryName,
            caption: caption,
            username: postUsername,
          ),
        ),
      );
    } catch (_) {
      if (page.mounted) _tell(page, 'Could not save that. Please try again.');
    }
  }

  void _tell(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share(BuildContext context) async {
    Navigator.of(context).maybePop();
    context = pageContext;
    HapticFeedback.selectionClick();
    ref.read(analyticsProvider).postShared(postId);
    await SharePlus.instance.share(
      ShareParams(
        text: ShareTemplate.quest(
          postId: postId,
          questTitle: questTitle ?? '',
          country: questCountryName,
          caption: caption,
          username: postUsername,
        ),
      ),
    );
  }

  Future<void> _report(BuildContext context) async {
    Navigator.of(context).maybePop();
    context = pageContext;
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
                      color: QuestColors.osRed,
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusButton),
                      border: Border.all(color: ink, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.flag_rounded,
                        color: QuestColors.onAccent(QuestColors.osRed),
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
                  border: Border.all(color: ink, width: 2),
                ),
                child: TextField(
                  controller: controller,
                  maxLines: 3,
                  minLines: 3,
                  style: QuestTypography.bodyMedium.copyWith(color: ink),
                  cursorColor: QuestColors.osRed,
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
                        constraints: const BoxConstraints(
                          minHeight: QuestSpacing.minTouchTarget,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: QuestColors.osRed,
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
                            color: QuestColors.onAccent(QuestColors.osRed),
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
                borderRadius: BorderRadius.circular(QuestSpacing.radiusPip),
              ),
            ),
          ),
          _ActionRow(
            icon: Icons.ios_share_rounded,
            label: 'SHARE',
            tint: QuestColors.osPrimary,
            onTap: () => _share(context),
          ),
          if ((mediaUrl ?? '').isNotEmpty) ...[
            Container(height: 1, color: ink.withAlpha(30)),
            _ActionRow(
              icon: Icons.download_rounded,
              label: 'SAVE',
              tint: QuestColors.osPrimary,
              onTap: () => _save(context),
            ),
          ],
          Container(height: 1, color: ink.withAlpha(30)),
          _ActionRow(
            icon: Icons.flag_rounded,
            label: 'REPORT',
            tint: QuestColors.osRed,
            onTap: () => _report(context),
          ),
          if (postUserId != null &&
              postUserId!.isNotEmpty &&
              ref.read(authSessionProvider)?.id != postUserId)
            _ActionRow(
                icon: Icons.block,
                label: 'BLOCK @$postUsername',
                tint: QuestColors.osRed,
                onTap: () => _block(context)),
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
                borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
                border: Border.all(color: tint.withAlpha(160), width: 2),
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
