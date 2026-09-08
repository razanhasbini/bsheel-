import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:app_contracts/app_contracts.dart';
import '../../../../design/bs_widgets.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../quests/data/quest_providers.dart';
import '../../data/collab_providers.dart';

class JoinCollabPage extends ConsumerStatefulWidget {
  final String code;
  const JoinCollabPage({super.key, required this.code});

  @override
  ConsumerState<JoinCollabPage> createState() => _JoinCollabPageState();
}

class _JoinCollabPageState extends ConsumerState<JoinCollabPage> {
  static const Color _inkShadow20 =
      Color(0x331A1330); // Screen-specific colour — not a theme token.
  static const Color _inkShadow15 =
      Color(0x261A1330); // Screen-specific colour — not a theme token.

  bool _joining = false;
  bool _abandoning = false;

  Future<void> _join() async {
    // Guard double-tap + intermediate state. Without this an eager tap
    // during the abandon-confirm dialog or mid-join can fire two RPCs
    // and create a duplicate collab membership.
    if (_joining || _abandoning) return;
    if (guardAccountAction(context, ref)) return;
    final activeQuest = ref.read(activeQuestProvider).valueOrNull;
    // Only an in-progress ('assigned') quest blocks joining a group.
    // 'submitted' quests are pending review and stack alongside the
    // new collab quest (matches the server-side join_collab_group rule).
    if (activeQuest != null && activeQuest.status == UserQuestStatus.assigned) {
      final confirmed = await _showAbandonDialog();
      if (!confirmed || !mounted) return;
      setState(() => _abandoning = true);
      try {
        await ref.read(collabRepositoryProvider).abandonQuest(activeQuest.id);
        ref.read(analyticsProvider).track('collab_quest_abandoned');
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(mapDbError(e, action: 'abandon quest'))),
          );
        }
        setState(() => _abandoning = false);
        return;
      }
      if (mounted) setState(() => _abandoning = false);
    }

    setState(() => _joining = true);
    try {
      final result =
          await ref.read(collabRepositoryProvider).joinGroup(widget.code);
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
          builder: (ctx) => AlertDialog(
            backgroundColor: QuestColors.cardBg(context),
            title: Text('ABANDON CURRENT QUEST?',
                style: QuestTypography.headlineSmall
                    .copyWith(color: QuestColors.text(context))),
            content: Text(
                'You have an active quest. Abandon it to join this group.',
                style: QuestTypography.bodyMedium
                    .copyWith(color: QuestColors.textDim(context))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: Text('CANCEL',
                      style: TextStyle(color: QuestColors.text(context)))),
              TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('ABANDON & JOIN',
                      style: TextStyle(color: QuestColors.successGreen))),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(collabGroupDetailsProvider(widget.code));
    final navyColor = QuestColors.text(context);

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
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 8,
              left: QuestSpacing.screenPadding,
              child: _BackButton(onTap: onBack),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 56),
              child: groupAsync.when(
                loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(QuestSpacing.screenPadding),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 48, color: QuestColors.softRed),
                        const SizedBox(height: QuestSpacing.md),
                        Text('GROUP NOT FOUND',
                            style: QuestTypography.headlineSmall
                                .copyWith(color: navyColor)),
                        const SizedBox(height: QuestSpacing.sm),
                        Text('This group may have expired or is full.',
                            style: QuestTypography.bodyMedium
                                .copyWith(color: navyColor.withAlpha(160)),
                            textAlign: TextAlign.center),
                        const SizedBox(height: QuestSpacing.xl),
                        GestureDetector(
                          onTap: () => context.goNamed(RouteNames.home),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: QuestSpacing.xl,
                                vertical: QuestSpacing.md),
                            decoration: BoxDecoration(
                                color: QuestColors.violet,
                                borderRadius: BorderRadius.circular(20)),
                            child: Text('GO HOME',
                                style: QuestTypography.labelMedium.copyWith(
                                    color: QuestColors.osTextOnPrimary,
                                    letterSpacing: 1.5)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (group) {
                  final isVersus = group.mode == CollabMode.versus;
                  // Versus = competitive red, coop = collaborative green (mirrors
                  // the reels-card collab badge + post detail page).
                  final accentColor =
                      isVersus ? QuestColors.softRed : QuestColors.successGreen;
                  final isBusy = _joining || _abandoning;

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(QuestSpacing.screenPadding),
                    child: Column(
                      children: [
                        const SizedBox(height: QuestSpacing.xl),

                        // Mode badge — chunky pill matching the rest of the app
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: accentColor.withAlpha(28),
                            borderRadius:
                                BorderRadius.circular(QuestSpacing.radiusFull),
                            border: Border.all(color: accentColor, width: 1.5),
                          ),
                          child: Text(
                            isVersus ? 'VERSUS QUEST' : 'COLLAB QUEST',
                            style: QuestTypography.labelMedium.copyWith(
                              color: accentColor,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: QuestSpacing.lg),

                        // Creator avatar with chunky drop shadow
                        Container(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(QuestSpacing.radiusSm),
                            boxShadow: const [
                              BoxShadow(
                                color: _inkShadow20,
                                offset: Offset(2, 3),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: PixelAvatar(
                            username: group.creatorUsername,
                            imageUrl: group.creatorAvatarUrl,
                            size: 72,
                          ),
                        ),
                        const SizedBox(height: QuestSpacing.sm),
                        Text(
                          group.creatorDisplayName,
                          style: QuestTypography.headlineSmall.copyWith(
                            color: navyColor,
                            letterSpacing: 0.4,
                          ),
                        ),
                        Text(
                          'INVITES YOU TO JOIN',
                          style: QuestTypography.labelSmall.copyWith(
                            color: QuestColors.osTextSecondary,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: QuestSpacing.lg),

                        // Quest preview — chunky white card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(QuestSpacing.lg),
                          decoration: BoxDecoration(
                            color: QuestColors.osCard,
                            borderRadius:
                                BorderRadius.circular(QuestSpacing.radiusMd),
                            border: Border.all(
                              color: QuestColors.osBorderStrong,
                              width: 2,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: _inkShadow20,
                                offset: Offset(2, 3),
                                blurRadius: 0,
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              Text(
                                group.questTitle.toUpperCase(),
                                style: QuestTypography.headlineSmall.copyWith(
                                  color: navyColor,
                                  letterSpacing: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: QuestSpacing.sm),
                              Text(
                                group.questDescription,
                                style: QuestTypography.bodyMedium.copyWith(
                                  color: QuestColors.osTextSecondary,
                                  height: 1.5,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: QuestSpacing.md),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: QuestSpacing.sm,
                                runSpacing: QuestSpacing.xs,
                                children: [
                                  _Chip(
                                    label: group.questCategory.toUpperCase(),
                                    color: QuestColors.violet,
                                  ),
                                  _Chip(
                                    label: group.questDifficulty.toUpperCase(),
                                    color: QuestColors.xpGold,
                                  ),
                                  _Chip(
                                    label: '${group.questXpReward} XP',
                                    color: QuestColors.successGreen,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: QuestSpacing.lg),

                        // Members already joined
                        Text(
                          '${group.memberCount}/${group.maxMembers} JOINED',
                          style: QuestTypography.labelSmall.copyWith(
                            color: QuestColors.osTextMuted,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: QuestSpacing.sm),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.center,
                          children: group.members
                              .map((m) => Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(
                                        QuestSpacing.radiusSm,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: _inkShadow15,
                                          offset: Offset(1.5, 2),
                                          blurRadius: 0,
                                        ),
                                      ],
                                    ),
                                    child: PixelAvatar(
                                      username: m.username,
                                      imageUrl: m.avatarUrl,
                                      size: 44,
                                    ),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: QuestSpacing.xl),

                        // Accept button — chunky with hard offset shadow
                        GestureDetector(
                          onTap: isBusy ? null : _join,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                vertical: QuestSpacing.lg),
                            decoration: BoxDecoration(
                              color: isBusy
                                  ? accentColor.withAlpha(140)
                                  : accentColor,
                              borderRadius:
                                  BorderRadius.circular(QuestSpacing.radiusMd),
                              border: Border.all(
                                color: QuestColors.osBorderStrong,
                                width: 2,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: _inkShadow20,
                                  offset: Offset(2, 3),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Text(
                              _abandoning
                                  ? 'ABANDONING QUEST...'
                                  : _joining
                                      ? 'JOINING...'
                                      : 'ACCEPT & JOIN',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: QuestTypography.headlineSmall.copyWith(
                                color: QuestColors.onAccent(accentColor),
                                letterSpacing: 2,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        const SizedBox(height: QuestSpacing.md),
                        GestureDetector(
                          onTap: () => context.goNamed(RouteNames.home),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: QuestSpacing.sm,
                              horizontal: QuestSpacing.lg,
                            ),
                            child: Text(
                              'NOT NOW',
                              style: QuestTypography.labelMedium.copyWith(
                                color: QuestColors.osTextMuted,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
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

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: BsMinTouch(
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: QuestColors.cardBg(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: ink, width: 2),
            boxShadow: [
              BoxShadow(color: ink, offset: const Offset(2, 2), blurRadius: 0),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(Icons.arrow_back_rounded, size: 18, color: ink),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withAlpha(20),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(80))),
      child: Text(label,
          style: QuestTypography.labelSmall
              .copyWith(color: color, fontSize: 10, letterSpacing: 1)),
    );
  }
}
