import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../design/bs_widgets.dart';
import '../../../../core/router/safe_back.dart';
import '../../../../core/backend/app_backend.dart';

/// UX-003: in-app surface to review and undo blocks.
/// The block dialog in feed_post_details promised a Settings page that
/// didn't exist. This page lists everyone the user has blocked plus an
/// UNBLOCK action per row.
final _blockedUsersProvider = FutureProvider.autoDispose<
    List<
        ({
          String userId,
          String username,
          String displayName,
          String? avatarUrl
        })>>(
  (ref) async {
    final users = await AppBackend.repositories.account.blockedUsers();
    return users
        .map((user) => (
              userId: user.id,
              username: user.username,
              displayName: user.displayName,
              avatarUrl: user.avatarUrl,
            ))
        .toList(growable: false);
  },
);

class BlockedUsersPage extends ConsumerWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = QuestColors.text(context);
    final blockedAsync = ref.watch(_blockedUsersProvider);

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                QuestSpacing.screenPadding,
                QuestSpacing.md,
                QuestSpacing.screenPadding,
                0,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => safeBack(context),
                    behavior: HitTestBehavior.opaque,
                    child: BsMinTouch(
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: QuestColors.cardBg(context),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: ink, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: ink,
                              offset: const Offset(2, 2),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: Icon(Icons.arrow_back_rounded,
                            size: 18, color: ink),
                      ),
                    ),
                  ),
                  const SizedBox(width: QuestSpacing.md),
                  Flexible(
                    child: Text(
                      'BLOCKED USERS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QuestTypography.headlineLarge.copyWith(
                        color: ink,
                        fontSize: 20,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: QuestSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: QuestSpacing.screenPadding),
              child: Text(
                'People you\'ve blocked won\'t see your posts and you won\'t see theirs. Tap UNBLOCK to undo.',
                style: QuestTypography.bodySmall
                    .copyWith(color: QuestColors.textDim(context)),
              ),
            ),
            const SizedBox(height: QuestSpacing.md),
            Expanded(
              child: blockedAsync.when(
                loading: () => const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(QuestSpacing.lg),
                    child: Text(
                      mapDbError(e, action: 'load blocked users'),
                      textAlign: TextAlign.center,
                      style: QuestTypography.bodyMedium
                          .copyWith(color: QuestColors.osRed),
                    ),
                  ),
                ),
                data: (users) {
                  if (users.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(QuestSpacing.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shield_moon_outlined,
                                size: 48, color: QuestColors.textMuted),
                            const SizedBox(height: QuestSpacing.md),
                            Text('NO BLOCKED USERS',
                                style: QuestTypography.headlineSmall
                                    .copyWith(color: ink)),
                            const SizedBox(height: QuestSpacing.sm),
                            Text(
                              'You haven\'t blocked anyone. Block from a post\'s … menu if you need to.',
                              textAlign: TextAlign.center,
                              style: QuestTypography.bodyMedium.copyWith(
                                color: QuestColors.textDim(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    color: QuestColors.osPrimary,
                    onRefresh: () async =>
                        ref.invalidate(_blockedUsersProvider),
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: QuestSpacing.screenPadding,
                        vertical: QuestSpacing.sm,
                      ),
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: users.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: QuestSpacing.sm),
                      itemBuilder: (_, i) =>
                          _BlockedRow(user: users[i], ink: ink),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedRow extends ConsumerStatefulWidget {
  const _BlockedRow({required this.user, required this.ink});
  final ({
    String userId,
    String username,
    String displayName,
    String? avatarUrl
  }) user;
  final Color ink;

  @override
  ConsumerState<_BlockedRow> createState() => _BlockedRowState();
}

class _BlockedRowState extends ConsumerState<_BlockedRow> {
  bool _busy = false;

  Future<void> _unblock() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppBackend.repositories.account.unblockUser(widget.user.userId);
      ref.invalidate(_blockedUsersProvider);
    } catch (e) {
      if (!mounted) return;
      messenger
        ..clearSnackBars()
        ..showSnackBar(
            SnackBar(content: Text(mapDbError(e, action: 'unblock'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final name = u.displayName.isNotEmpty ? u.displayName : u.username;
    return Container(
      padding: const EdgeInsets.all(QuestSpacing.sm),
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
        border: Border.all(color: widget.ink, width: 1.6),
      ),
      child: Row(
        children: [
          PixelAvatar(
            imageUrl: u.avatarUrl,
            username: u.username,
            size: 36,
          ),
          const SizedBox(width: QuestSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.labelMedium
                      .copyWith(color: widget.ink, fontSize: 13),
                ),
                Text(
                  '@${u.username}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.bodySmall.copyWith(
                    color: QuestColors.textDim(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _busy ? null : _unblock,
            child: Container(
              constraints: const BoxConstraints(
                  minWidth: kMinTouchTarget, minHeight: kMinTouchTarget),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color:
                    _busy ? QuestColors.cardBg(context) : QuestColors.osPrimary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: widget.ink, width: 1.5),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      'UNBLOCK',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: QuestColors.osTextOnPrimary,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
