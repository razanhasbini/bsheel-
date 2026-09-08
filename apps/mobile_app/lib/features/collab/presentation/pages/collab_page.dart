import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:app_contracts/app_contracts.dart';

import '../../../../core/config/deep_link_config.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/services/analytics_service.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../quests/data/quest_providers.dart';
import '../../data/collab_providers.dart';

/// Collab page — Arcade Pop.
///
/// Three states:
///   1. No active quest → chunky "GENERATE A QUEST" + "JOIN A QUEST" pills.
///   2. Active quest, no group yet → mode selector (WITH / VERSUS) + "CREATE GROUP".
///   3. Active quest, in a group → group card (mode badge, invite code,
///      member list with status pills, 👑 leader for versus).
class CollabPage extends ConsumerStatefulWidget {
  const CollabPage({super.key});

  @override
  ConsumerState<CollabPage> createState() => _CollabPageState();
}

class _CollabPageState extends ConsumerState<CollabPage> {
  String _selectedMode = CollabMode.with_;
  String? _groupCode;
  String? _groupMode;
  bool _creating = false;

  Color get _withColor => QuestColors.successGreen;
  Color get _versusColor => QuestColors.softRed;

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _createGroup(String userQuestId) async {
    // Guard double-tap: a fast second tap before _creating flips
    // synchronously would otherwise fire a duplicate createGroup RPC,
    // leaving an orphan group on the user's quest.
    if (_creating) return;
    if (guardAccountAction(context, ref)) return;
    setState(() => _creating = true);
    try {
      final result = await ref.read(collabRepositoryProvider).createGroup(
            userQuestId,
            _selectedMode,
          );
      if (!mounted) return;
      setState(() {
        _groupCode = result['code'] as String;
        _groupMode = result['mode'] as String;
      });
      // Invalidate the group status provider so the UI flips from
      // "create group" to "group card" on this device immediately,
      // instead of waiting for a hot-reload / tab switch to re-fetch.
      ref.invalidate(collabGroupStatusProvider(userQuestId));
      ref.read(analyticsProvider).track('collab_group_created', {
        'user_quest_id': userQuestId,
        'mode': _selectedMode,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mapDbError(e, action: 'create collab group')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  void _shareCode() {
    if (_groupCode == null) return;
    if (guardAccountAction(context, ref)) return;
    final link = DeepLinkConfig.collabInviteLink(_groupCode!);
    final modeLabel = _groupMode == CollabMode.versus ? 'VERSUS' : 'COOP';
    SharePlus.instance.share(
      ShareParams(text: 'Join my $modeLabel quest on BSHEEL!\n\n$link'),
    );
    ref
        .read(analyticsProvider)
        .track('collab_invite_shared', {'code': _groupCode});
  }

  void _copyLink(String code) {
    Clipboard.setData(
      ClipboardData(text: DeepLinkConfig.collabInviteLink(code)),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied!')),
    );
  }

  void _showJoinDialog() {
    final codeController = TextEditingController();
    final ink = QuestColors.text(context);
    // StateSetter is used by the dialog's inline error feedback so the
    // user knows when a sub-6-char code was rejected (was previously a
    // silent no-op). Captured outside the showDialog future so the
    // disposal in whenComplete fires AFTER all closures have run.
    String? error;

    showDialog(
      context: context,
      barrierColor: QuestColors.pureBlack.withAlpha(QuestColors.alphaOverlay),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: ArcadeCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ENTER INVITE CODE',
                  style: QuestTypography.headlineSmall.copyWith(
                    color: ink,
                    letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Ask your friend for their 6-character code',
                  style: QuestTypography.bodySmall.copyWith(
                    color: ink.withAlpha(QuestColors.alphaInkMuted),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ArcadeTextField(
                  controller: codeController,
                  hint: 'ABC123',
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 6,
                  autocorrect: false,
                  onChanged: (_) {
                    if (error != null) setLocal(() => error = null);
                  },
                ),
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(error!,
                      style: QuestTypography.bodySmall
                          .copyWith(color: QuestColors.softRed)),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ArcadeButton(
                        label: 'Cancel',
                        variant: ArcadeButtonVariant.ghost,
                        size: ArcadeButtonSize.small,
                        onTap: () => Navigator.of(ctx).pop(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ArcadeButton(
                        label: 'Join',
                        icon: Icons.login_rounded,
                        variant: ArcadeButtonVariant.secondary,
                        size: ArcadeButtonSize.small,
                        onTap: () {
                          // Normalize to uppercase + strip whitespace so
                          // pasting "abc 123" or "abc123 " still resolves.
                          final code = codeController.text
                              .trim()
                              .replaceAll(RegExp(r'\s+'), '')
                              .toUpperCase();
                          if (code.length != 6) {
                            setLocal(() => error =
                                'Code must be 6 characters (got ${code.length}).');
                            return;
                          }
                          Navigator.of(ctx).pop();
                          context.pushNamed(
                            RouteNames.joinCollab,
                            pathParameters: {'code': code},
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    ).whenComplete(codeController.dispose);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activeQuestAsync = ref.watch(activeQuestProvider);
    final activeQuest = activeQuestAsync.valueOrNull;

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(),
            Expanded(
              child: activeQuest == null
                  ? _NoQuestState(onJoin: _showJoinDialog)
                  : _buildCollabContent(activeQuest),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollabContent(UserQuestModel activeQuest) {
    final groupAsync = ref.watch(collabGroupStatusProvider(activeQuest.id));
    return groupAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, __) => ArcadeErrorState(
        title: "Couldn't load group",
        subtitle: 'Check your connection and try again.',
        onRetry: () =>
            ref.invalidate(collabGroupStatusProvider(activeQuest.id)),
      ),
      data: (group) {
        if (group.isCollab) {
          return _GroupCard(
            activeQuest: activeQuest,
            group: group,
            onCopyLink: _copyLink,
          );
        }
        return _CreateGroupState(
          activeQuest: activeQuest,
          selectedMode: _selectedMode,
          onModeChange: (mode) => setState(() => _selectedMode = mode),
          creating: _creating,
          groupCode: _groupCode,
          groupMode: _groupMode,
          onCreate: () => _createGroup(activeQuest.id),
          onShare: _shareCode,
          onCopy: () {
            if (_groupCode != null) _copyLink(_groupCode!);
          },
          onJoin: _showJoinDialog,
          withColor: _withColor,
          versusColor: _versusColor,
        );
      },
    );
  }
}

// ── Header ──────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        QuestSpacing.screenPadding,
        14,
        QuestSpacing.screenPadding,
        10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            'COLLAB',
            style: QuestTypography.headlineLarge.copyWith(
              color: ink,
              fontSize: 28,
              letterSpacing: 2,
              height: 1,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 48,
            height: 6,
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: QuestColors.softRed,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: ink, width: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ── No-quest state ──────────────────────────────────────────────────────────

class _NoQuestState extends StatelessWidget {
  const _NoQuestState({required this.onJoin});
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(QuestSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [QuestColors.osPrimary, QuestColors.softRed],
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: ink, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(3, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.group_rounded,
                color: QuestColors.osTextOnPrimary,
                size: 48,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'QUEST TOGETHER',
            textAlign: TextAlign.center,
            style: QuestTypography.headlineLarge.copyWith(
              color: ink,
              fontSize: 24,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a quest to invite friends, or join one with a code.',
            textAlign: TextAlign.center,
            style: QuestTypography.bodyMedium.copyWith(
              color: ink.withAlpha(QuestColors.alphaInkMuted),
            ),
          ),
          const SizedBox(height: 28),
          ArcadeButton(
            label: 'Generate a quest',
            icon: Icons.auto_fix_high_rounded,
            variant: ArcadeButtonVariant.secondary,
            size: ArcadeButtonSize.large,
            onTap: () => context.goNamed(RouteNames.home),
          ),
          const SizedBox(height: 12),
          ArcadeButton(
            label: 'Join a quest',
            icon: Icons.login_rounded,
            variant: ArcadeButtonVariant.ghost,
            size: ArcadeButtonSize.large,
            onTap: onJoin,
          ),
        ],
      ),
    );
  }
}

// ── Create-group state ──────────────────────────────────────────────────────

class _CreateGroupState extends StatelessWidget {
  const _CreateGroupState({
    required this.activeQuest,
    required this.selectedMode,
    required this.onModeChange,
    required this.creating,
    required this.groupCode,
    required this.groupMode,
    required this.onCreate,
    required this.onShare,
    required this.onCopy,
    required this.onJoin,
    required this.withColor,
    required this.versusColor,
  });

  final UserQuestModel activeQuest;
  final String selectedMode;
  final ValueChanged<String> onModeChange;
  final bool creating;
  final String? groupCode;
  final String? groupMode;
  final VoidCallback onCreate;
  final VoidCallback onShare;
  final VoidCallback onCopy;
  final VoidCallback onJoin;
  final Color withColor;
  final Color versusColor;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final questTitle = activeQuest.quest?.title ?? 'Your Quest';
    final isVersus = selectedMode == CollabMode.versus;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(QuestSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Quest hero tile
          ArcadeCard(
            backgroundColor: QuestColors.cardBg(context),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ACTIVE QUEST',
                  style: QuestTypography.labelSmall.copyWith(
                    color: ink.withAlpha(QuestColors.alphaInkMuted),
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  questTitle,
                  style: QuestTypography.headlineMedium.copyWith(
                    color: ink,
                    height: 1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Mode selector
          const ArcadeSectionHeader(text: 'Choose mode'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _ModeTile(
                  label: 'WITH',
                  description: 'Complete together',
                  icon: Icons.handshake_rounded,
                  color: withColor,
                  selected: selectedMode == CollabMode.with_,
                  onTap: () => onModeChange(CollabMode.with_),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeTile(
                  label: 'VERSUS',
                  description: 'Compete for best',
                  icon: Icons.local_fire_department_rounded,
                  color: versusColor,
                  selected: selectedMode == CollabMode.versus,
                  onTap: () => onModeChange(CollabMode.versus),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),

          if (groupCode != null) ...[
            _InviteCodeCard(
              code: groupCode!,
              accentColor: (groupMode ?? selectedMode) == CollabMode.versus
                  ? versusColor
                  : withColor,
              onShare: onShare,
              onCopy: onCopy,
            ),
          ] else ...[
            ArcadeButton(
              label: creating ? 'Creating…' : 'Create group',
              icon: creating
                  ? null
                  : (isVersus
                      ? Icons.local_fire_department_rounded
                      : Icons.group_add_rounded),
              isLoading: creating,
              size: ArcadeButtonSize.large,
              variant: isVersus
                  ? ArcadeButtonVariant.danger
                  : ArcadeButtonVariant.primary,
              onTap: creating ? null : onCreate,
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'Up to 5 players',
                style: QuestTypography.bodySmall.copyWith(
                  color: ink.withAlpha(QuestColors.alphaInkMuted),
                ),
              ),
            ),
          ],

          const SizedBox(height: 22),

          // OR divider
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 2,
                  color: ink.withAlpha(QuestColors.alphaWhisper),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR',
                  style: QuestTypography.labelSmall.copyWith(
                    color: ink.withAlpha(QuestColors.alphaInkMuted),
                    letterSpacing: 2,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 2,
                  color: ink.withAlpha(QuestColors.alphaWhisper),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ArcadeButton(
            label: 'Join a quest with code',
            icon: Icons.login_rounded,
            variant: ArcadeButtonVariant.ghost,
            size: ArcadeButtonSize.medium,
            onTap: onJoin,
          ),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? color : QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: ink, width: 2),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(3, 4),
                    blurRadius: 0,
                  ),
                ]
              : [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(2, 3),
                    blurRadius: 0,
                  ),
                ],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 34,
              color: selected ? QuestColors.osTextOnPrimary : color,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: QuestTypography.headlineSmall.copyWith(
                color: selected ? QuestColors.osTextOnPrimary : ink,
                letterSpacing: 1.6,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              description,
              textAlign: TextAlign.center,
              style: QuestTypography.bodySmall.copyWith(
                color: (selected ? QuestColors.osTextOnPrimary : ink)
                    .withAlpha(QuestColors.alphaInkMuted),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteCodeCard extends StatelessWidget {
  const _InviteCodeCard({
    required this.code,
    required this.accentColor,
    required this.onShare,
    required this.onCopy,
  });

  final String code;
  final Color accentColor;
  final VoidCallback onShare;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return ArcadeCard(
      backgroundColor: QuestColors.cardBg(context),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(
            'INVITE CODE',
            style: QuestTypography.labelSmall.copyWith(
              color: ink.withAlpha(QuestColors.alphaInkMuted),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: onCopy,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: accentColor.withAlpha(QuestColors.alphaWhisper),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accentColor, width: 2),
              ),
              child: Text(
                code,
                style: QuestTypography.displaySmall.copyWith(
                  color: accentColor,
                  letterSpacing: 8,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          ArcadeButton(
            label: 'Share invite',
            icon: Icons.share_rounded,
            variant: ArcadeButtonVariant.secondary,
            onTap: onShare,
          ),
        ],
      ),
    );
  }
}

// ── Active group card ───────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.activeQuest,
    required this.group,
    required this.onCopyLink,
  });

  final UserQuestModel activeQuest;
  final CollabGroupStatusModel group;
  final ValueChanged<String> onCopyLink;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final questTitle = activeQuest.quest?.title ?? 'QUEST';
    final isVersus = group.mode == CollabMode.versus;
    final accentColor =
        isVersus ? QuestColors.softRed : QuestColors.successGreen;

    int maxVotes = 0;
    int leadersCount = 0;
    if (isVersus) {
      for (final m in group.members) {
        if (m.voteCount > maxVotes) maxVotes = m.voteCount;
      }
      // Count how many members share the top vote count so we can
      // suppress the crown when the result is a tie (every tied member
      // would otherwise wear the leader badge, which is confusing).
      if (maxVotes > 0) {
        leadersCount =
            group.members.where((m) => m.voteCount == maxVotes).length;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(QuestSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mode badge + member count row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accentColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: ink, width: 2),
                ),
                child: Text(
                  isVersus ? 'VERSUS' : 'WITH',
                  style: QuestTypography.labelSmall.copyWith(
                    color: QuestColors.osTextOnPrimary,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${group.members.length}/${group.maxMembers ?? 5} MEMBERS',
                style: QuestTypography.labelSmall.copyWith(
                  color: ink.withAlpha(QuestColors.alphaInkMuted),
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Quest title
          ArcadeCard(
            padding: const EdgeInsets.all(16),
            child: Text(
              questTitle,
              textAlign: TextAlign.center,
              style: QuestTypography.headlineMedium.copyWith(
                color: ink,
                height: 1.2,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Invite code (if group still open)
          if (group.status == CollabGroupStatus.open && group.code != null) ...[
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => onCopyLink(group.code!),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: QuestColors.cardBg(context),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: ink, width: 1.5),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.copy_rounded,
                        size: 16,
                        color: ink.withAlpha(QuestColors.alphaInkMuted)),
                    const SizedBox(width: 6),
                    Text(
                      'CODE ${group.code}',
                      style: QuestTypography.labelMedium.copyWith(
                        color: ink,
                        letterSpacing: 3,
                        fontFamily: 'JetBrainsMono',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          const SizedBox(height: 18),
          const ArcadeSectionHeader(text: 'Members'),
          const SizedBox(height: 10),

          // Members list
          ...group.members.map((member) {
            final isLeader = isVersus &&
                maxVotes > 0 &&
                leadersCount == 1 &&
                member.voteCount == maxVotes;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _MemberTile(
                member: member,
                isVersus: isVersus,
                isLeader: isLeader,
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isVersus,
    required this.isLeader,
  });

  final CollabMemberStatus member;
  final bool isVersus;
  final bool isLeader;

  (String, Color) _status(BuildContext context) {
    final label = (member.submissionStatus ?? member.questStatus ?? 'assigned')
        .toUpperCase();
    if (member.submissionStatus == 'approved') {
      return (label, QuestColors.successGreen);
    }
    if (member.submissionStatus == 'pending' ||
        member.questStatus == 'submitted') {
      return (label, QuestColors.accentYellow);
    }
    if (member.submissionStatus == 'rejected') {
      return (label, QuestColors.softRed);
    }
    if (member.questStatus == 'expired') {
      return (label, QuestColors.textMuted);
    }
    return (label, QuestColors.osPrimary);
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final (statusText, statusColor) = _status(context);

    return ArcadeCard(
      backgroundColor: QuestColors.cardBg(context),
      borderColor: isLeader ? QuestColors.accentYellow : ink,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shadowOffset: 2,
      child: Row(
        children: [
          // Avatar
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: QuestColors.osPrimary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ink, width: 1.8),
            ),
            alignment: Alignment.center,
            child: Text(
              member.displayName.isNotEmpty
                  ? member.displayName[0].toUpperCase()
                  : '?',
              style: QuestTypography.headlineSmall.copyWith(
                color: QuestColors.osTextOnPrimary,
                fontSize: 16,
                height: 1,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isLeader)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Text('👑', style: TextStyle(fontSize: 14)),
                      ),
                    Flexible(
                      child: Text(
                        member.displayName.isNotEmpty
                            ? member.displayName
                            : member.username,
                        style: QuestTypography.labelMedium.copyWith(color: ink),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  '@${member.username}',
                  style: QuestTypography.bodySmall.copyWith(
                    color: ink.withAlpha(QuestColors.alphaInkMuted),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (isVersus && member.voteCount > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: QuestColors.accentYellow,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: ink, width: 1.2),
              ),
              child: Text(
                '${member.voteCount}V',
                style: QuestTypography.labelSmall.copyWith(
                  color: QuestColors.accentYellowInk,
                  fontSize: 10,
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: ink, width: 1.2),
            ),
            child: Text(
              statusText,
              style: QuestTypography.labelSmall.copyWith(
                color: QuestColors.osTextOnPrimary,
                fontSize: 9,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
