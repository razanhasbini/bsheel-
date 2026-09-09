import 'package:app_core/app_core.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../../core/router/safe_back.dart';
import '../../../../core/backend/app_backend.dart';
import '../../data/blocked_users_provider.dart';

/// Blocked users — built to the BLOCKED USERS block in
/// `export/panels/panel-04.jpg`: one white card holding a display title, a
/// row per blocked account with a cream UNBLOCK button, and the two-way
/// explanation as body copy at the foot of the card.
class BlockedUsersPage extends ConsumerWidget {
  const BlockedUsersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final blockedAsync = ref.watch(blockedUsersProvider);

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: Row(
                children: [
                  _IconButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => safeBack(context),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FitText(
                      'BLOCKED USERS',
                      minFontSize: 16,
                      style: QuestTypography.osDisplaySmall.copyWith(
                        fontSize: 24,
                        letterSpacing: -0.4,
                        height: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: QuestColors.osPrimary,
                backgroundColor: QuestColors.osCard,
                onRefresh: () async {
                  ref.invalidate(blockedUsersProvider);
                  await ref.read(blockedUsersProvider.future);
                },
                child: blockedAsync.when(
                  loading: () => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    children: const [
                      ArcadeSkeletonList(itemCount: 3, itemHeight: 64),
                    ],
                  ),
                  error: (e, _) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    children: [
                      Text(
                        mapDbError(e, action: 'load blocked users'),
                        textAlign: TextAlign.center,
                        style: QuestTypography.osBodyMedium
                            .copyWith(color: QuestColors.osRedText),
                      ),
                    ],
                  ),
                  data: (users) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: QuestColors.osCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: QuestColors.osTextPrimary,
                            width: 2,
                          ),
                          boxShadow: const [
                            BoxShadow(
                              color: QuestColors.osTextPrimary,
                              offset: Offset(3, 3),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (users.isEmpty)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  18,
                                  16,
                                  10,
                                ),
                                child: Text(
                                  'NO BLOCKED USERS',
                                  style: QuestTypography.osHeadlineLarge
                                      .copyWith(fontSize: 18),
                                ),
                              )
                            else
                              for (var i = 0; i < users.length; i++) ...[
                                if (i > 0)
                                  const Divider(
                                    height: 1,
                                    thickness: 1,
                                    color: QuestColors.osBorder,
                                  ),
                                _BlockedRow(user: users[i]),
                              ],
                            const Divider(
                              height: 1,
                              thickness: 1,
                              color: QuestColors.osBorder,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 14, 16, 16),
                              child: Text(
                                'Blocks cut both directions — their posts and '
                                'comments are hidden from you, and yours from '
                                'them.',
                                style: QuestTypography.osBodyMedium.copyWith(
                                  color: QuestColors.osTextSecondary,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _BlockedRow extends ConsumerStatefulWidget {
  const _BlockedRow({required this.user});
  final BlockedUser user;

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
      ref.invalidate(blockedUsersProvider);
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          _RoundAvatar(url: u.avatarUrl, name: u.username),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              u.username,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osHeadlineLarge.copyWith(
                fontSize: 18,
                color: QuestColors.osTextSecondary,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(width: 8),
          _UnblockButton(busy: _busy, onTap: _unblock),
        ],
      ),
    );
  }
}

class _UnblockButton extends StatelessWidget {
  const _UnblockButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: busy ? null : onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: QuestSpacing.minTouchTarget,
        ),
        child: Center(
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: QuestColors.osSurface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: QuestColors.osTextPrimary, width: 2),
            ),
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: QuestColors.osTextPrimary,
                    ),
                  )
                : Text(
                    'UNBLOCK',
                    style: QuestTypography.osHeadlineSmall.copyWith(
                      fontSize: 13,
                      letterSpacing: 0.6,
                      height: 1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _RoundAvatar extends StatelessWidget {
  const _RoundAvatar({required this.url, required this.name});

  final String? url;
  final String name;

  static const double _size = 40;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      width: _size,
      height: _size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: QuestColors.osSurface,
        shape: BoxShape.circle,
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: QuestTypography.osHeadlineMedium.copyWith(height: 1),
      ),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
      ),
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url!,
          fit: BoxFit.cover,
          width: _size,
          height: _size,
          memCacheWidth: (_size * 2).round(),
          placeholder: (_, __) =>
              const ColoredBox(color: QuestColors.osSurface),
          errorWidget: (_, __, ___) => placeholder,
        ),
      ),
    );
  }
}

/// 44pt square icon button — white ground, `r11`, 2px ink, 3px ink shadow.
class _IconButton extends StatelessWidget {
  const _IconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: QuestSpacing.minTouchTarget,
        height: QuestSpacing.minTouchTarget,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: const [
            BoxShadow(
              color: QuestColors.osTextPrimary,
              offset: Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: QuestColors.osTextPrimary),
      ),
    );
  }
}
