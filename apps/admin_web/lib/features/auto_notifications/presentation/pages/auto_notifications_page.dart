import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _recentAutoNotificationsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  final data = await client
      .from(Tables.notifications)
      .select(
        '${NotificationColumns.id},'
        '${NotificationColumns.userId},'
        '${NotificationColumns.title},'
        '${NotificationColumns.body},'
        '${NotificationColumns.type},'
        '${NotificationColumns.createdAt},'
        'profiles!notifications_user_id_fkey(${ProfileColumns.username})',
      )
      .neq(NotificationColumns.type, NotificationType.announcement)
      .order(NotificationColumns.createdAt, ascending: false)
      .limit(50);

  return List<Map<String, dynamic>>.from(data as List);
});

// ── Static Rule Model ──────────────────────────────────────────────────────────

class _NotificationRule {
  final IconData icon;
  final String name;
  final String trigger;
  final String recipient;

  const _NotificationRule({
    required this.icon,
    required this.name,
    required this.trigger,
    required this.recipient,
  });
}

const _kRules = <_NotificationRule>[
  _NotificationRule(
    icon: Icons.assignment,
    name: 'Quest Assigned',
    trigger: 'User generates a quest',
    recipient: 'Quest owner',
  ),
  _NotificationRule(
    icon: Icons.celebration,
    name: 'First Quest Welcome',
    trigger: "User's very first quest",
    recipient: 'New user',
  ),
  _NotificationRule(
    icon: Icons.timer,
    name: 'Quest Timer Warning',
    trigger: '30 min left on quest',
    recipient: 'Quest owner',
  ),
  _NotificationRule(
    icon: Icons.timer_off,
    name: 'Quest Expired',
    trigger: 'Quest timer runs out',
    recipient: 'Quest owner',
  ),
  _NotificationRule(
    icon: Icons.check_circle,
    name: 'Submission Approved',
    trigger: 'Admin approves submission',
    recipient: 'Submitter',
  ),
  _NotificationRule(
    icon: Icons.cancel,
    name: 'Submission Rejected',
    trigger: 'Admin rejects submission',
    recipient: 'Submitter',
  ),
  _NotificationRule(
    icon: Icons.trending_up,
    name: 'Level Up',
    trigger: 'XP crosses level threshold',
    recipient: 'User',
  ),
  _NotificationRule(
    icon: Icons.favorite,
    name: 'New Reaction',
    trigger: 'Someone reacts to your post',
    recipient: 'Post owner',
  ),
  _NotificationRule(
    icon: Icons.local_fire_department,
    name: 'Reaction Milestone',
    trigger: 'Post reaches 10/25/50 reactions',
    recipient: 'Post owner',
  ),
  _NotificationRule(
    icon: Icons.comment,
    name: 'New Comment',
    trigger: 'Someone comments on your post',
    recipient: 'Post owner',
  ),
  _NotificationRule(
    icon: Icons.reply,
    name: 'Comment Reply',
    trigger: 'Someone else also comments',
    recipient: 'Previous commenters',
  ),
  _NotificationRule(
    icon: Icons.person_add,
    name: 'New Follower',
    trigger: 'Someone follows you',
    recipient: 'Followed user',
  ),
  _NotificationRule(
    icon: Icons.emoji_events,
    name: 'Followed User Completes Quest',
    trigger: 'Someone you follow gets approved',
    recipient: 'Your followers',
  ),
  _NotificationRule(
    icon: Icons.leaderboard,
    name: 'Leaderboard Overtaken',
    trigger: 'Someone passes you in rank',
    recipient: 'Displaced user',
  ),
  _NotificationRule(
    icon: Icons.military_tech,
    name: 'Top 10 Entry',
    trigger: 'User enters top 10',
    recipient: 'User',
  ),
  _NotificationRule(
    icon: Icons.admin_panel_settings,
    name: 'New Submission (Admin)',
    trigger: 'User submits proof',
    recipient: 'All admins',
  ),
  _NotificationRule(
    icon: Icons.gavel,
    name: 'Appeal Submitted (Admin)',
    trigger: 'User resubmits after rejection',
    recipient: 'All admins',
  ),
  _NotificationRule(
    icon: Icons.warning,
    name: 'Pending Review Reminder',
    trigger: '24h+ submissions exist',
    recipient: 'All admins',
  ),
];

// ── Helpers ───────────────────────────────────────────────────────────────────

Color _colorForType(String type) {
  const questTypes = {
    NotificationType.questAssigned,
    NotificationType.questExpired,
    NotificationType.questTimerWarning,
    NotificationType.submissionApproved,
    NotificationType.submissionRejected,
    NotificationType.levelUp,
    NotificationType.followQuestCompleted,
  };
  const socialTypes = {
    NotificationType.reactionReceived,
    NotificationType.reactionMilestone,
    NotificationType.newComment,
    NotificationType.commentReply,
    NotificationType.newFollower,
  };
  const adminTypes = {
    NotificationType.newSubmission,
    NotificationType.appealSubmitted,
    NotificationType.pendingReviewReminder,
  };
  const leaderboardTypes = {
    NotificationType.leaderboardOvertaken,
    NotificationType.top10Entry,
  };

  if (questTypes.contains(type)) return BsheelColors.cool;
  if (socialTypes.contains(type)) return BsheelColors.primary;
  if (adminTypes.contains(type)) return BsheelColors.ink;
  if (leaderboardTypes.contains(type)) return BsheelColors.cool;
  return BsheelColors.inkMuted;
}

String _labelForType(String type) => type.replaceAll('_', ' ').toUpperCase();

// ── Page ──────────────────────────────────────────────────────────────────────

class AutoNotificationsPage extends ConsumerWidget {
  const AutoNotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(_recentAutoNotificationsProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BsheelCard(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelEyebrow('Community · Auto rules'),
                const SizedBox(height: 14),
                BsheelDisplay(
                  'Know the {triggers.}',
                  baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
                ),
                const SizedBox(height: 12),
                Text(
                  'Read-only reference of the server-side notification '
                  'triggers, plus a live feed of the most recent '
                  'automatic sends.',
                  style: BsheelType.bodyMd
                      .copyWith(color: BsheelColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section 1: Notification Rules (server-side triggers, read-only)
          const _SectionHeader(label: 'SERVER TRIGGERS · READ-ONLY'),
          const SizedBox(height: QuestSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              if (isMobile) {
                return Column(
                  children: _kRules
                      .map(
                        (rule) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: QuestSpacing.sm,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            child: _RuleCard(rule: rule),
                          ),
                        ),
                      )
                      .toList(),
                );
              }
              return Wrap(
                spacing: QuestSpacing.md,
                runSpacing: QuestSpacing.md,
                children: _kRules
                    .map((rule) => _RuleCard(rule: rule))
                    .toList(),
              );
            },
          ),
          const SizedBox(height: QuestSpacing.xxl),

          // Section 2: Recent Auto Notifications
          const _SectionHeader(label: 'RECENT AUTO NOTIFICATIONS'),
          const SizedBox(height: QuestSpacing.md),
          notificationsAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(QuestSpacing.xxl),
                child: CircularProgressIndicator(
                  color: BsheelColors.cool,
                ),
              ),
            ),
            error: (e, _) => Container(
              padding: const EdgeInsets.all(QuestSpacing.md),
              decoration: BoxDecoration(
                color: BsheelColors.hot.withAlpha(20),
                border: Border.all(
                  color: BsheelColors.hot.withAlpha(80),
                  width: BsheelBorders.thin,
                ),
                borderRadius: BorderRadius.circular(BsheelRadii.md),
              ),
              child: Text(
                'Failed to load notifications: $e',
                style: BsheelType.bodySm.copyWith(
                  color: BsheelColors.hot,
                ),
              ),
            ),
            data: (notifications) => notifications.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(QuestSpacing.xl),
                    decoration: BoxDecoration(
                      color: BsheelColors.paper,
                      borderRadius:
                          BorderRadius.circular(BsheelRadii.lg),
                      border: Border.all(
                        color: BsheelColors.line,
                        width: BsheelBorders.thin,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'No auto notifications found.',
                        style: BsheelType.bodySm.copyWith(
                          color: BsheelColors.inkMuted,
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: notifications
                        .map((n) => _NotificationTile(data: n))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          color: BsheelColors.cool,
        ),
        const SizedBox(width: QuestSpacing.sm),
        Text(
          label,
          style: BsheelType.labelMd.copyWith(
            color: BsheelColors.ink,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }
}

// ── Rule Card ─────────────────────────────────────────────────────────────────

class _RuleCard extends StatelessWidget {
  final _NotificationRule rule;
  const _RuleCard({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 280),
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: Border.all(
            color: BsheelColors.line, width: BsheelBorders.thin,),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(QuestSpacing.sm),
                decoration: BoxDecoration(
                  color: BsheelColors.surface,
                  borderRadius: BorderRadius.circular(BsheelRadii.md),
                ),
                child: Icon(
                  rule.icon,
                  color: BsheelColors.cool,
                  size: 16,
                ),
              ),
              const SizedBox(width: QuestSpacing.sm),
              Expanded(
                child: Text(
                  rule.name.toUpperCase(),
                  style: BsheelType.labelSm.copyWith(
                    color: BsheelColors.ink,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              // No status badge: these cards mirror server-side triggers
              // that can't be toggled from here, so a per-rule "ACTIVE"
              // pill would just be decoration. The section header already
              // marks them read-only.
            ],
          ),
          const SizedBox(height: QuestSpacing.sm),
          Text(
            rule.trigger,
            style: BsheelType.bodySm.copyWith(
              color: BsheelColors.inkSoft,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: QuestSpacing.xs),
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 12,
                color: BsheelColors.inkMuted,
              ),
              const SizedBox(width: 4),
              Text(
                rule.recipient,
                style: BsheelType.labelSm.copyWith(
                  color: BsheelColors.inkMuted,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Notification Tile ─────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _NotificationTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final type = (data[NotificationColumns.type] as String?) ?? '';
    final title = (data[NotificationColumns.title] as String?) ?? '';
    final body = (data[NotificationColumns.body] as String?) ?? '';
    final createdAt = data[NotificationColumns.createdAt] as String?;
    final profileMap = data[Tables.profiles] as Map<String, dynamic>?;
    final username = profileMap?[ProfileColumns.username] as String?;
    final typeColor = _colorForType(type);

    final typeChip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: typeColor.withAlpha(100)),
        borderRadius: BorderRadius.circular(BsheelRadii.full),
      ),
      child: Text(
        _labelForType(type),
        style: BsheelType.labelSm.copyWith(
          color: typeColor,
          fontSize: 9,
          letterSpacing: 0.5,
        ),
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: QuestSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.md,
        vertical: QuestSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: Border.all(
            color: BsheelColors.line, width: BsheelBorders.thin,),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 500;
          if (isMobile) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    typeChip,
                    const Spacer(),
                    Text(
                      bsheelTimeAgo(createdAt, caps: false, fallback: '?'),
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.inkMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: QuestSpacing.xs),
                Text(
                  title,
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: BsheelType.bodySm.copyWith(
                      color: BsheelColors.inkMuted,
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (username != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    style: BsheelType.bodySm.copyWith(
                      color: BsheelColors.inkSoft,
                      fontSize: 11,
                    ),
                  ),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              typeChip,
              const SizedBox(width: QuestSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: BsheelType.bodySm.copyWith(
                        color: BsheelColors.ink,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (body.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        body,
                        style: BsheelType.bodySm.copyWith(
                          color: BsheelColors.inkMuted,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: QuestSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (username != null)
                    Text(
                      '@$username',
                      style: BsheelType.bodySm.copyWith(
                        color: BsheelColors.inkSoft,
                        fontSize: 11,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    bsheelTimeAgo(createdAt, caps: false, fallback: '?'),
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.inkMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
