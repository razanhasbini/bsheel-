import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:app_contracts/app_contracts.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../quests/data/quest_providers.dart';
import '../../data/collab_providers.dart';

/// Join a collab — built to the JOIN A COLLAB block in
/// `export/panels/panel-04.jpg`: a violet `r16` panel with white type, the
/// code set in a cream box, and a jade JOIN GROUP with **ink** type.
class JoinCollabPage extends ConsumerStatefulWidget {
  final String code;
  const JoinCollabPage({super.key, required this.code});

  @override
  ConsumerState<JoinCollabPage> createState() => _JoinCollabPageState();
}

class _JoinCollabPageState extends ConsumerState<JoinCollabPage> {
  bool _joining = false;

  Future<void> _join() async {
    // Guard double-tap + intermediate state. Without this an eager tap
    // during the abandon-confirm dialog or mid-join can fire two RPCs
    // and create a duplicate collab membership.
    if (_joining) return;
    if (guardAccountAction(context, ref)) return;
    final activeQuest = ref.read(activeQuestProvider).valueOrNull;
    // Only an in-progress ('assigned') quest blocks joining a group.
    // 'submitted' quests are pending review and stack alongside the
    // new collab quest (matches the server-side join_collab_group rule).
    // The confirmation is still ours to ask, but the abandon is no longer
    // ours to perform. Doing it here as its own request meant a join that
    // then failed — full group, block, expired code, dropped connection —
    // had already destroyed the quest, leaving the user in no group with
    // nothing to roll. The intent goes with the join instead, and the
    // server swaps them inside one transaction or does neither.
    var swapActiveQuest = false;
    if (activeQuest != null && activeQuest.status == UserQuestStatus.assigned) {
      final confirmed = await _showAbandonDialog();
      if (!confirmed || !mounted) return;
      swapActiveQuest = true;
    }

    setState(() => _joining = true);
    try {
      final result = await ref
          .read(collabRepositoryProvider)
          .joinGroup(widget.code, abandonActiveQuest: swapActiveQuest);
      if (swapActiveQuest) {
        ref.read(analyticsProvider).track('collab_quest_abandoned');
      }
      ref.read(analyticsProvider).track('collab_group_joined', {
        'code': widget.code,
        'quest_id': result['quest_id'],
        'mode': result['mode'],
      });
      ref.invalidate(activeQuestProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Joined the group quest!')));
        context.goNamed(RouteNames.collab);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mapDbError(e, action: 'join collab group'))),
        );
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<bool> _showAbandonDialog() async {
    return await showDialog<bool>(
          context: context,
          barrierColor:
              QuestColors.pureBlack.withAlpha(QuestColors.alphaOverlay),
          builder: (ctx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(24),
            child: ArcadeCard(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('ABANDON CURRENT QUEST?',
                      style: QuestTypography.osHeadlineLarge
                          .copyWith(color: QuestColors.osRedText)),
                  const SizedBox(height: 8),
                  Text(
                    'You have an active quest. Abandon it to join this group.',
                    style: QuestTypography.osBodyMedium
                        .copyWith(color: QuestColors.osTextSecondary),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: ArcadeButton(
                          label: 'Cancel',
                          size: ArcadeButtonSize.small,
                          variant: ArcadeButtonVariant.ghost,
                          onTap: () => Navigator.of(ctx).pop(false),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ArcadeButton(
                          label: 'Abandon & join',
                          size: ArcadeButtonSize.small,
                          variant: ArcadeButtonVariant.positive,
                          onTap: () => Navigator.of(ctx).pop(true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(collabGroupDetailsProvider(widget.code));

    // Deep-link cold-start protection: this page is the App Store landing
    // route for `/join/:code` shares, so there's no implicit Navigator
    // stack to fall back on. Hand the user a back button that pops if
    // possible and otherwise lands them on /home.
    void onBack() {
      if (context.canPop()) {
        context.pop();
      } else {
        context.goNamed(RouteNames.home);
      }
    }

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            Row(
              children: [
                _IconButton(icon: Icons.arrow_back_rounded, onTap: onBack),
              ],
            ),
            const SizedBox(height: 16),
            groupAsync.when(
              loading: () => const ArcadeSkeleton(height: 260, radius: 16),
              error: (e, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _DashedPanel(
                    label: 'EMPTY STATE',
                    title: 'GROUP NOT FOUND',
                    body: 'This group may have expired or is full.',
                  ),
                  const SizedBox(height: 16),
                  ArcadeButton(
                    label: 'Go home',
                    onTap: () => context.goNamed(RouteNames.home),
                  ),
                ],
              ),
              data: (group) {
                final isBusy = _joining;
                final isVersus = group.mode == CollabMode.versus;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _InvitePanel(
                      creator: group.creatorUsername.isNotEmpty
                          ? group.creatorUsername
                          : group.creatorDisplayName,
                      groupTitle: group.questTitle,
                      code: group.code,
                      buttonLabel: _joining ? 'JOINING…' : 'JOIN GROUP',
                      onJoin: isBusy ? null : _join,
                    ),
                    const SizedBox(height: 16),
                    _QuestPreviewCard(
                      title: group.questTitle,
                      description: group.questDescription,
                      category: group.questCategory,
                      xpReward: group.questXpReward,
                      isVersus: isVersus,
                      joined: group.memberCount,
                      capacity: group.maxMembers,
                    ),
                    const SizedBox(height: 14),
                    Center(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => context.goNamed(RouteNames.home),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Text(
                            'NOT NOW',
                            style: QuestTypography.osLabelMedium.copyWith(
                              color: QuestColors.osTextSecondary,
                              letterSpacing: 1.6,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Invite panel ──────────────────────────────────────────────────────────

class _InvitePanel extends StatelessWidget {
  const _InvitePanel({
    required this.creator,
    required this.groupTitle,
    required this.code,
    required this.buttonLabel,
    required this.onJoin,
  });

  final String creator;
  final String groupTitle;
  final String code;
  final String buttonLabel;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: QuestColors.osPrimary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        boxShadow: const [
          BoxShadow(
            color: QuestColors.osTextPrimary,
            offset: Offset(4, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FitText(
            'JOIN A COLLAB',
            minFontSize: 16,
            style: QuestTypography.displaySmall.copyWith(
              fontSize: 24,
              // White on violet is the correct pair and must stay.
              color: QuestColors.onAccent(QuestColors.osPrimary),
              height: 1,
            ),
          ),
          const SizedBox(height: 10),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '$creator invited you to '),
                TextSpan(
                  text: groupTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: '.'),
              ],
            ),
            style: QuestTypography.bodyMedium.copyWith(
              color: QuestColors.pureWhite,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: QuestColors.osBg,
              borderRadius: BorderRadius.circular(QuestSpacing.radiusPanel),
              border: Border.all(color: QuestColors.osTextPrimary, width: 2),
            ),
            child: FitText(
              code.toUpperCase(),
              minFontSize: 12,
              textAlign: TextAlign.center,
              style: QuestTypography.osDisplaySmall.copyWith(
                fontSize: 20,
                letterSpacing: 8,
                height: 1,
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Jade with ink type — `onAccent(jade)` returns ink.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onJoin,
            child: Container(
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: QuestColors.osSuccess,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: QuestColors.osTextPrimary, width: 2),
              ),
              child: FitText(
                buttonLabel,
                minFontSize: 12,
                textAlign: TextAlign.center,
                style: QuestTypography.osDisplaySmall.copyWith(
                  fontSize: 20,
                  color: QuestColors.onAccent(QuestColors.osSuccess),
                  letterSpacing: 0.4,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quest preview ─────────────────────────────────────────────────────────

class _QuestPreviewCard extends StatelessWidget {
  const _QuestPreviewCard({
    required this.title,
    required this.description,
    required this.category,
    required this.xpReward,
    required this.isVersus,
    required this.joined,
    required this.capacity,
  });

  final String title;
  final String description;
  final String category;
  final int xpReward;
  final bool isVersus;
  final int joined;
  final int capacity;

  @override
  Widget build(BuildContext context) {
    final tint = QuestColors.category(category);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        boxShadow: [
          // Category shadow, as on the feed card.
          BoxShadow(color: tint, offset: const Offset(3, 3), blurRadius: 0),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ArcadeCategoryTag(label: category, tint: tint),
              ArcadeCategoryTag(
                label: '+$xpReward XP',
                tint: QuestColors.osAccent,
              ),
              ArcadeCategoryTag(
                label: isVersus ? 'VERSUS' : 'WITH',
                tint: isVersus ? QuestColors.osRed : QuestColors.osSuccess,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osDisplaySmall
                .copyWith(fontSize: 20, height: 1.1),
          ),
          if (description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osBodyMedium
                  .copyWith(color: QuestColors.osTextSecondary),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '$joined / $capacity JOINED',
            style: QuestTypography.osLabelSmall.copyWith(letterSpacing: 1.4),
          ),
        ],
      ),
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

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
          borderRadius: BorderRadius.circular(QuestSpacing.radiusButton),
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

class _DashedPanel extends StatelessWidget {
  const _DashedPanel({
    required this.label,
    required this.title,
    required this.body,
  });

  final String label;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorderPainter(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: QuestTypography.osLabelSmall
                  .copyWith(color: QuestColors.osTextMuted),
            ),
            const SizedBox(height: 10),
            Text(
              title.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.osDisplaySmall.copyWith(
                color: QuestColors.osTextSecondary,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: QuestTypography.osBodyMedium
                  .copyWith(color: QuestColors.osTextSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = QuestColors.osTextMuted
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(1, 1, size.width - 2, size.height - 2),
      const Radius.circular(16),
    );
    for (final metric in (Path()..addRRect(rect)).computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + 6).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + 5;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) => false;
}
