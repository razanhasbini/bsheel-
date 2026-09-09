import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../data/quest_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../widgets/arcade_page_chrome.dart';

/// Quest history, drawn to `export/mobile/19-quest-history.jpg`.
///
/// The frame groups by outcome rather than listing a flat feed of cards:
/// a coloured mono header with its count, then one compact row per quest.
/// Each group's row has its own ground, so the outcome is legible before
/// any text is read — white + jade shadow cleared, gold in review, coral
/// rejected, dashed cream expired.
class QuestHistoryPage extends ConsumerWidget {
  const QuestHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(questHistoryProvider);
    final l = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            ArcadePageHeader(
              title: l.questHistoryTitle,
              display: true,
              onBack: () => safeBack(context),
            ),
            Expanded(
              child: RefreshIndicator(
                color: QuestColors.osPrimary,
                backgroundColor: QuestColors.cardBg(context),
                onRefresh: () async => ref.invalidate(questHistoryProvider),
                child: historyAsync.when(
                  loading: () => const _HistorySkeleton(),
                  error: (e, _) => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 80),
                      ArcadeInlineError(
                        title: 'HISTORY UNAVAILABLE',
                        subtitle: l.failedToLoadHistory,
                        onRetry: () => ref.invalidate(questHistoryProvider),
                      ),
                    ],
                  ),
                  data: (history) {
                    if (history.isEmpty) {
                      return ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 90),
                          _EmptyState(subtitle: l.completeToSeeHistory),
                        ],
                      );
                    }

                    List<UserQuestModel> group(String status) => history
                        .where((q) => q.status == status)
                        .toList(growable: false);

                    final completed = group(UserQuestStatus.approved);
                    final inReview = group(UserQuestStatus.submitted);
                    final rejected = group(UserQuestStatus.rejected);
                    final expired = group(UserQuestStatus.expired);

                    // The durable route into the appeal flow. The other
                    // three — a notification tap, the QOTD stub, and the
                    // redirect after submitting — are all transient; if push
                    // delivery breaks, history is the one place a rejected
                    // user will look.
                    final appealOpen = rejected.any((q) => q.appealAvailable);

                    void openQuest(UserQuestModel q) {
                      if (q.quest == null) return;
                      context.pushNamed(
                        RouteNames.questDetails,
                        pathParameters: {'id': q.questId},
                      );
                    }

                    void openAppeal(UserQuestModel q) => context.pushNamed(
                          RouteNames.submissionStatus,
                          pathParameters: {'id': q.id},
                        );

                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        QuestSpacing.screenPadding,
                        0,
                        QuestSpacing.screenPadding,
                        28,
                      ),
                      children: [
                        if (completed.isNotEmpty)
                          _Group(
                            label: 'COMPLETED',
                            count: completed.length,
                            labelColor: QuestColors.osSuccessText,
                            rows: [
                              for (final q in completed)
                                _HistoryRow(
                                  title: q.quest?.title ?? 'Quest',
                                  trailing: '+${q.quest?.xpReward ?? 0}',
                                  trailingSize: 11,
                                  ground: QuestColors.osCard,
                                  // The shadow carries the outcome: reading
                                  // a row's result from the colour under it
                                  // beats reading the label.
                                  shadow: QuestColors.osSuccess,
                                  titleColor: QuestColors.osTextPrimary,
                                  trailingColor: QuestColors.osSuccessText,
                                  onTap: () => openQuest(q),
                                ),
                            ],
                          ),
                        if (inReview.isNotEmpty)
                          _Group(
                            label: 'IN REVIEW',
                            count: inReview.length,
                            labelColor: QuestColors.osAccentText,
                            rows: [
                              for (final q in inReview)
                                _HistoryRow(
                                  title: q.quest?.title ?? 'Quest',
                                  trailing: _waiting(q),
                                  ground: QuestColors.osAccent,
                                  shadow: QuestColors.osTextPrimary,
                                  titleColor: QuestColors.onAccent(
                                      QuestColors.osAccent),
                                  trailingColor: QuestColors.onAccent(
                                      QuestColors.osAccent),
                                  onTap: () => openQuest(q),
                                ),
                            ],
                          ),
                        if (rejected.isNotEmpty)
                          _Group(
                            label: 'REJECTED',
                            count: rejected.length,
                            labelColor: QuestColors.osRedText,
                            rows: [
                              for (final q in rejected)
                                _RejectedRow(
                                  title: q.quest?.title ?? 'Quest',
                                  appealAvailable: q.appealAvailable,
                                  onAppeal: q.appealAvailable
                                      ? () => openAppeal(q)
                                      : null,
                                  onTap: () => openQuest(q),
                                ),
                            ],
                          ),
                        if (expired.isNotEmpty)
                          _Group(
                            label: 'EXPIRED',
                            count: expired.length,
                            labelColor: QuestColors.osTextSecondary,
                            rows: [
                              for (final q in expired)
                                _ExpiredRow(
                                  title: q.quest?.title ?? 'Quest',
                                  onTap: () => openQuest(q),
                                ),
                            ],
                          ),
                        if (appealOpen) ...[
                          const SizedBox(height: 2),
                          const _AppealHint(),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Hours left before the review SLA note in the frame ("4H"). Falls back
  /// to a plain marker when the server sent no expiry.
  static String _waiting(UserQuestModel q) {
    final since = q.completedAt ?? q.assignedAt;
    final h = DateTime.now().difference(since).inHours;
    return h <= 0 ? 'NEW' : '${h}H';
  }
}

// ── Group ──────────────────────────────────────────────────────────────────

/// Coloured mono header + its rows, at the frame's `15` inter-group and
/// `8` intra-group gaps.
class _Group extends StatelessWidget {
  const _Group({
    required this.label,
    required this.count,
    required this.labelColor,
    required this.rows,
  });

  final String label;
  final int count;
  final Color labelColor;
  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '$label · $count',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QuestTypography.osLabelMedium.copyWith(
              color: labelColor,
              fontSize: 11,
              letterSpacing: 1.32,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            rows[i],
          ],
        ],
      ),
    );
  }
}

// ── Rows ───────────────────────────────────────────────────────────────────

/// The base row: `r12`, 2px ink, 3px shadow, `12 / 13` padding, a flexible
/// 14pt title and a mono trailing marker.
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.title,
    required this.trailing,
    required this.ground,
    required this.shadow,
    required this.titleColor,
    required this.trailingColor,
    required this.onTap,
    this.trailingSize = 10,
  });

  final String title;
  final String trailing;
  final Color ground;
  final Color shadow;
  final Color titleColor;
  final Color trailingColor;
  final double trailingSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(
          minHeight: QuestSpacing.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: ground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: QuestSpacing.hardShadow(3, color: shadow),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QuestTypography.osBodyMedium.copyWith(
                  color: titleColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontVariations: const [FontVariation('wght', 600)],
                  height: 1.2,
                ),
              ),
            ),
            const SizedBox(width: 11),
            Text(
              trailing,
              maxLines: 1,
              style: QuestTypography.osLabelMedium.copyWith(
                color: trailingColor,
                fontSize: trailingSize,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Coral row with the stacked title + `1 APPEAL AVAILABLE`, and the cream
/// APPEAL button that is the only durable way into the appeal flow.
class _RejectedRow extends StatelessWidget {
  const _RejectedRow({
    required this.title,
    required this.appealAvailable,
    required this.onAppeal,
    required this.onTap,
  });

  final String title;

  /// Server-computed. Only when this is true does the API honour an appeal,
  /// so the button is a promise the backend will keep.
  final bool appealAvailable;
  final VoidCallback? onAppeal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final onCoral = QuestColors.onAccent(QuestColors.osRed);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: QuestColors.osRed,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: QuestSpacing.shadowSm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QuestTypography.osBodyMedium.copyWith(
                      color: onCoral,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      fontVariations: const [FontVariation('wght', 600)],
                      height: 1.2,
                    ),
                  ),
                  if (appealAvailable) ...[
                    const SizedBox(height: 1),
                    Text(
                      '1 APPEAL AVAILABLE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: QuestTypography.osLabelMedium.copyWith(
                        color: onCoral,
                        fontSize: 10,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (appealAvailable && onAppeal != null) ...[
              const SizedBox(width: 11),
              _AppealButton(onTap: onAppeal!),
            ],
          ],
        ),
      ),
    );
  }
}

/// `h40` painted inside a 44pt hit area, `r10`, cream on coral, 2px ink.
class _AppealButton extends StatelessWidget {
  const _AppealButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minHeight: QuestSpacing.minTouchTarget,
        ),
        child: Center(
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: QuestColors.osBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ink, width: 2),
            ),
            child: Text(
              'APPEAL',
              style: QuestTypography.osHeadlineMedium.copyWith(
                fontSize: 12,
                fontVariations: const [FontVariation('wght', 700)],
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed cream row — inert, not empty. No shadow, because nothing about an
/// expired quest is still waiting on the player.
class _ExpiredRow extends StatelessWidget {
  const _ExpiredRow({required this.title, required this.onTap});
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: ArcadeDashedBox(
        radius: 12,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: QuestSpacing.minTouchTarget,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: QuestTypography.osBodyMedium.copyWith(
                    color: QuestColors.osTextSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontVariations: const [FontVariation('wght', 600)],
                    height: 1.2,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Text(
                'NO XP',
                style: QuestTypography.osLabelMedium.copyWith(
                  color: QuestColors.osTextSecondary,
                  fontSize: 10,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The violet note under the groups. The frame's own copy describes the
/// design change; this says the same thing to the person holding the phone.
class _AppealHint extends StatelessWidget {
  const _AppealHint();

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: QuestColors.osPrimary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ink, width: 2),
        boxShadow: QuestSpacing.shadowSm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '+',
            style: QuestTypography.osHeadlineMedium.copyWith(
              color: QuestColors.onAccent(QuestColors.osPrimary),
              fontSize: 15,
              height: 1.3,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Tap APPEAL on a rejected quest to ask a moderator to look '
              'again. You get one appeal per submission.',
              style: QuestTypography.osBodySmall.copyWith(
                color: QuestColors.onAccent(QuestColors.osPrimary),
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty + skeleton ───────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            AppLocalizations.of(context)!.noQuestsYet.toUpperCase(),
            textAlign: TextAlign.center,
            style: QuestTypography.osDisplaySmall.copyWith(fontSize: 22),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: QuestTypography.osBodyMedium.copyWith(
              color: QuestColors.osTextSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.screenPadding,
      ),
      children: [
        for (var group = 0; group < 3; group++) ...[
          const ArcadeSkeleton(
            width: 120,
            height: 11,
            radius: 4,
            bordered: false,
          ),
          const SizedBox(height: 8),
          const ArcadeSkeleton(height: 46, radius: 12),
          const SizedBox(height: 8),
          const ArcadeSkeleton(height: 46, radius: 12),
          const SizedBox(height: 15),
        ],
      ],
    );
  }
}
