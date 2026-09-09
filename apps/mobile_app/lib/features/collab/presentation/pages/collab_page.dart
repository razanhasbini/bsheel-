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

/// Collab — built to `export/mobile/14-collab.jpg`.
///
/// Three stacked blocks, in the frame's order:
///
/// 1. an **ink hero panel** (`r18`, 2px cream outline, 6px **sky** shadow)
///    carrying the mode/status meta, a gold countdown, the quest title and
///    one option card per member — with a vote meter in VERSUS mode;
/// 2. YOUR GROUPS — a white card per group whose 3px shadow is the *status*
///    colour, jade for an open group and muted for a closed one;
/// 3. JOIN BY CODE — an inline field plus a violet JOIN, replacing the modal
///    dialog this page used to open.
///
/// On an ink panel every outline is **cream**, not ink: an ink border on an
/// ink ground is invisible. That is measured off the render, not a choice.
class CollabPage extends ConsumerStatefulWidget {
  const CollabPage({super.key});

  @override
  ConsumerState<CollabPage> createState() => _CollabPageState();
}

class _CollabPageState extends ConsumerState<CollabPage> {
  final _codeController = TextEditingController();
  String _selectedMode = CollabMode.with_;
  bool _creating = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ── Actions ──────────────────────────────────────────────────────────────

  Future<void> _createGroup(String userQuestId) async {
    // Guard double-tap: a fast second tap before _creating flips
    // synchronously would otherwise fire a duplicate createGroup RPC,
    // leaving an orphan group on the user's quest.
    if (_creating) return;
    if (guardAccountAction(context, ref)) return;
    setState(() => _creating = true);
    try {
      await ref.read(collabRepositoryProvider).createGroup(
            userQuestId,
            _selectedMode,
          );
      if (!mounted) return;
      // Invalidate the group status provider so the UI flips from
      // "create group" to the hero panel on this device immediately.
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

  void _shareCode(String code, String? mode) {
    if (guardAccountAction(context, ref)) return;
    final link = DeepLinkConfig.collabInviteLink(code);
    final modeLabel = mode == CollabMode.versus ? 'VERSUS' : 'COOP';
    SharePlus.instance.share(
      ShareParams(text: 'Join my $modeLabel quest on BSHEEL!\n\n$link'),
    );
    ref.read(analyticsProvider).track('collab_invite_shared', {'code': code});
  }

  void _copyLink(String code) {
    Clipboard.setData(
      ClipboardData(text: DeepLinkConfig.collabInviteLink(code)),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link copied!')),
    );
  }

  void _joinByCode() {
    // Normalize so pasting "abc 123" or "abc123 " still resolves.
    final code = _codeController.text
        .trim()
        .replaceAll(RegExp(r'\s+'), '')
        .toUpperCase();
    if (code.length != 6) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text('Code must be 6 characters (got ${code.length}).'),
        ));
      return;
    }
    context.pushNamed(RouteNames.joinCollab, pathParameters: {'code': code});
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final activeQuest = ref.watch(activeQuestProvider).valueOrNull;
    final groupAsync = activeQuest == null
        ? null
        : ref.watch(collabGroupStatusProvider(activeQuest.id));
    final group = groupAsync?.valueOrNull;

    return Scaffold(
      backgroundColor: QuestColors.osBg,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          children: [
            Row(
              children: [
                _IconButton(
                  icon: Icons.arrow_back_rounded,
                  onTap: () => context.canPop()
                      ? context.pop()
                      : context.goNamed(RouteNames.home),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FitText(
                    'COLLAB',
                    minFontSize: 18,
                    style: QuestTypography.osDisplayMedium.copyWith(
                      fontSize: 28,
                      letterSpacing: -0.6,
                      height: 1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (activeQuest == null)
              const _NoQuestPanel()
            else if (groupAsync!.isLoading)
              const ArcadeSkeleton(height: 220, radius: 18)
            else if (groupAsync.hasError)
              const _DashedPanel(
                label: 'ERROR',
                title: "Couldn't load group",
                body: 'Pull down or try again in a moment.',
              )
            else if (group != null && group.isCollab)
              _CollabHero(
                title: activeQuest.quest?.title ?? 'QUEST',
                group: group,
                expiresAt: group.expiresAt ?? activeQuest.expiresAt,
                onCastVote: () => context.goNamed(RouteNames.feed),
                onShare: group.code == null
                    ? null
                    : () => _shareCode(group.code!, group.mode),
              )
            else
              _CreateGroupPanel(
                questTitle: activeQuest.quest?.title ?? 'YOUR QUEST',
                selectedMode: _selectedMode,
                creating: _creating,
                onModeChange: (mode) => setState(() => _selectedMode = mode),
                onCreate: () => _createGroup(activeQuest.id),
              ),
            if (group != null && group.isCollab) ...[
              const SizedBox(height: 18),
              const _SectionLabel('YOUR GROUPS'),
              const SizedBox(height: 10),
              _GroupCard(
                title: activeQuest?.quest?.title ?? 'QUEST',
                memberCount: group.members.length,
                code: group.code,
                open: group.status == CollabGroupStatus.open,
                onTap: group.code == null ? null : () => _copyLink(group.code!),
              ),
            ],
            const SizedBox(height: 18),
            const _SectionLabel('JOIN BY CODE'),
            const SizedBox(height: 10),
            _JoinByCodeRow(
              controller: _codeController,
              onJoin: _joinByCode,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Hero ──────────────────────────────────────────────────────────────────

class _CollabHero extends StatelessWidget {
  const _CollabHero({
    required this.title,
    required this.group,
    required this.expiresAt,
    required this.onCastVote,
    required this.onShare,
  });

  final String title;
  final CollabGroupStatusModel group;
  final DateTime? expiresAt;
  final VoidCallback onCastVote;
  final VoidCallback? onShare;

  // Option-card avatar tints, in the frame's order: jade then coral.
  static const _tints = <Color>[
    QuestColors.osSuccess,
    QuestColors.osRed,
    QuestColors.osCool,
    QuestColors.osAccent,
    QuestColors.osPrimary,
  ];

  @override
  Widget build(BuildContext context) {
    final isVersus = group.mode == CollabMode.versus;
    final open = group.status == CollabGroupStatus.open;
    final meta = isVersus
        ? 'HEAD-TO-HEAD · ${open ? 'VOTING OPEN' : 'VOTING CLOSED'}'
        : 'TEAM QUEST · ${(group.status ?? 'OPEN').toUpperCase()}';
    final totalVotes =
        group.members.fold<int>(0, (sum, m) => sum + m.voteCount);
    final remaining = expiresAt?.difference(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: QuestColors.osTextPrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: QuestColors.osTextPrimary, width: 2),
        boxShadow: const [
          // Sky, at 6px: the frame reserves the coloured hero shadow for the
          // one thing the screen is about.
          BoxShadow(
            color: QuestColors.osCool,
            offset: Offset(6, 6),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.labelMedium
                      .copyWith(color: QuestColors.osCool),
                ),
              ),
              if (remaining != null) ...[
                const SizedBox(width: 8),
                Text(
                  // Same formatter the shared timer uses, recoloured for the
                  // ink panel: gold mono, as the frame sets it.
                  ArcadeTimer.format(remaining),
                  style: QuestTypography.labelMedium.copyWith(
                    color: QuestColors.osAccent,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title.toUpperCase(),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.displayMedium.copyWith(
              fontSize: 26,
              color: QuestColors.pureWhite,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (var i = 0; i < group.members.length; i++)
                    SizedBox(
                      width: width,
                      child: _OptionCard(
                        member: group.members[i],
                        tint: _tints[i % _tints.length],
                        isVersus: isVersus,
                        totalVotes: totalVotes,
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (isVersus)
            _HeroButton(
              label: 'CAST YOUR VOTE',
              ground: QuestColors.osCool,
              onTap: onCastVote,
            )
          else if (onShare != null)
            _HeroButton(
              label: 'SHARE INVITE',
              ground: QuestColors.osCool,
              onTap: onShare!,
            ),
        ],
      ),
    );
  }
}

/// One member inside the hero: `darkSurface` ground, 2px cream outline,
/// `r12`. VERSUS shows a gold vote meter and the share; the co-op mode shows
/// the member's review status instead, because a vote count would read 0.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.member,
    required this.tint,
    required this.isVersus,
    required this.totalVotes,
  });

  final CollabMemberStatus member;
  final Color tint;
  final bool isVersus;
  final int totalVotes;

  @override
  Widget build(BuildContext context) {
    final share = totalVotes == 0 ? 0.0 : member.voteCount / totalVotes;
    final statusLabel =
        (member.submissionStatus ?? member.questStatus ?? 'assigned')
            .toUpperCase();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: QuestColors.darkSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: QuestColors.osBg, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: tint,
                  shape: BoxShape.circle,
                  border: Border.all(color: QuestColors.osBg, width: 2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  member.username.isNotEmpty
                      ? member.username
                      : member.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.headlineMedium
                      .copyWith(color: QuestColors.pureWhite),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isVersus) ...[
            _DarkMeter(progress: share),
            const SizedBox(height: 8),
            Text(
              '${(share * 100).round()}% · ${member.voteCount} VOTES',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.labelSmall
                  .copyWith(color: QuestColors.textSecondary),
            ),
          ] else
            Text(
              statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: QuestTypography.labelSmall
                  .copyWith(color: QuestColors.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// `ArcadeMeter` is built for cream surfaces — white track, ink outline. On
/// the ink hero the frame inverts both: `darkSurface` track, cream outline,
/// gold fill.
class _DarkMeter extends StatelessWidget {
  const _DarkMeter({required this.progress});
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 14,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: QuestColors.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: QuestColors.osBg, width: 2),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: progress.clamp(0.0, 1.0),
          child: Container(
            decoration: BoxDecoration(
              color: QuestColors.osAccent,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width button inside the ink hero: accent ground, ink type via
/// `onAccent`, cream outline, `r12`.
class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.ground,
    required this.onTap,
  });

  final String label;
  final Color ground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: QuestColors.osBg, width: 2),
        ),
        child: FitText(
          label,
          minFontSize: 14,
          textAlign: TextAlign.center,
          style: QuestTypography.osDisplaySmall.copyWith(
            fontSize: 22,
            color: QuestColors.onAccent(ground),
            letterSpacing: 0.4,
            height: 1,
          ),
        ),
      ),
    );
  }
}

// ── Create group ──────────────────────────────────────────────────────────

class _CreateGroupPanel extends StatelessWidget {
  const _CreateGroupPanel({
    required this.questTitle,
    required this.selectedMode,
    required this.creating,
    required this.onModeChange,
    required this.onCreate,
  });

  final String questTitle;
  final String selectedMode;
  final bool creating;
  final ValueChanged<String> onModeChange;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: QuestColors.osCard,
        borderRadius: BorderRadius.circular(18),
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
          Text(
            'ACTIVE QUEST',
            style: QuestTypography.osLabelMedium.copyWith(
              color: QuestColors.osTextSecondary,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            questTitle.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osDisplaySmall
                .copyWith(fontSize: 22, height: 1.1),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _OptionChip(
                label: 'WITH',
                selected: selectedMode == CollabMode.with_,
                onTap: () => onModeChange(CollabMode.with_),
              ),
              _OptionChip(
                label: 'VERSUS',
                selected: selectedMode == CollabMode.versus,
                onTap: () => onModeChange(CollabMode.versus),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ArcadeButton(
            label: creating ? 'Creating…' : 'Create group',
            isLoading: creating,
            onTap: creating ? null : onCreate,
          ),
          const SizedBox(height: 8),
          Text(
            'Up to 5 players.',
            textAlign: TextAlign.center,
            style: QuestTypography.osBodySmall
                .copyWith(color: QuestColors.osTextSecondary),
          ),
        ],
      ),
    );
  }
}

class _NoQuestPanel extends StatelessWidget {
  const _NoQuestPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _DashedPanel(
          label: 'EMPTY STATE',
          title: 'NO COLLAB YET',
          body: 'Roll a quest to invite friends, or join one with a code.',
        ),
        const SizedBox(height: 16),
        ArcadeButton(
          label: 'Generate a quest',
          onTap: () => context.goNamed(RouteNames.home),
        ),
      ],
    );
  }
}

// ── Groups ────────────────────────────────────────────────────────────────

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.memberCount,
    required this.code,
    required this.open,
    required this.onTap,
  });

  final String title;
  final int memberCount;
  final String? code;
  final bool open;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // The list-row rule: a 3px shadow in the STATUS colour. Jade while the
    // group is open, muted once it closes.
    final statusColor = open ? QuestColors.osSuccess : QuestColors.osTextMuted;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: QuestColors.osCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          boxShadow: [
            BoxShadow(
              color: statusColor,
              offset: const Offset(3, 3),
              blurRadius: 0,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osDisplaySmall
                        .copyWith(fontSize: 20, height: 1.1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    code == null
                        ? '$memberCount MEMBERS'
                        : '$memberCount MEMBERS · CODE $code',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osLabelSmall.copyWith(height: 1.2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ArcadeCategoryTag(
              label: open ? 'ACTIVE' : 'IDLE',
              tint: open ? QuestColors.osSuccess : QuestColors.osSurface,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Join by code ──────────────────────────────────────────────────────────

class _JoinByCodeRow extends StatelessWidget {
  const _JoinByCodeRow({required this.controller, required this.onJoin});

  final TextEditingController controller;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: QuestColors.osCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: QuestColors.osTextPrimary, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: QuestColors.osTextPrimary,
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Center(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                maxLength: 6,
                onSubmitted: (_) => onJoin(),
                style: QuestTypography.osLabelLarge.copyWith(
                  fontSize: 16,
                  letterSpacing: 6,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  hintText: '- - - - - -',
                  hintStyle: QuestTypography.osLabelLarge.copyWith(
                    fontSize: 16,
                    letterSpacing: 2,
                    color: QuestColors.osTextMuted,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onJoin,
          child: Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: QuestColors.osPrimary,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: QuestColors.osTextPrimary, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: QuestColors.osTextPrimary,
                  offset: Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Text(
              'JOIN',
              style: QuestTypography.displaySmall.copyWith(
                fontSize: 22,
                // White on violet is the correct pair and must stay.
                color: QuestColors.onAccent(QuestColors.osPrimary),
                height: 1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Pieces ────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: QuestTypography.osLabelMedium.copyWith(
        color: QuestColors.osTextSecondary,
        letterSpacing: 1.6,
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        // No `alignment:` on this Container. Inside a Wrap the constraints
        // are bounded, and an Align with no widthFactor stretches the chip
        // to the full run width — which is what made these read as stacked
        // full-width bars instead of a row of chips.
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? QuestColors.osTextPrimary : QuestColors.osCard,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: QuestColors.osTextPrimary, width: 2),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelMedium.copyWith(
              color: selected ? QuestColors.osBg : QuestColors.osTextPrimary,
              fontSize: 12,
              letterSpacing: 1,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

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
