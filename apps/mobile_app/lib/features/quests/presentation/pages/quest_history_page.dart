import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_core/app_core.dart';
import 'package:app_contracts/app_contracts.dart';
import '../../../../core/router/route_names.dart';
import '../../../../core/router/safe_back.dart';
import '../../data/quest_providers.dart';
import '../../../../l10n/app_localizations.dart';

/// Arcade Pop quest history. Logic unchanged: reads [questHistoryProvider],
/// computes approved / rejected / expired counts, taps into quest details.
class QuestHistoryPage extends ConsumerWidget {
  const QuestHistoryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(questHistoryProvider);
    final l = AppLocalizations.of(context)!;
    final ink = QuestColors.text(context);

    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                QuestSpacing.screenPadding,
                14,
                QuestSpacing.screenPadding,
                4,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => safeBack(context),
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: QuestColors.cardBg(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ink, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: ink,
                            offset: const Offset(2, 3),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                      child:
                          Icon(Icons.arrow_back_rounded, color: ink, size: 20),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)!.questHistoryTitle,
                    style: QuestTypography.headlineSmall.copyWith(
                      color: ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      height: 1,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 36,
                    height: 6,
                    decoration: BoxDecoration(
                      color: QuestColors.softRed,
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(color: ink, width: 1.5),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                color: QuestColors.softRed,
                backgroundColor: QuestColors.cardBg(context),
                onRefresh: () async => ref.invalidate(questHistoryProvider),
                child: historyAsync.when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  error: (e, _) => _ErrorState(
                    message: l.failedToLoadHistory,
                    retry: l.tapToRetry,
                    onRetry: () => ref.invalidate(questHistoryProvider),
                  ),
                  data: (history) {
                    if (history.isEmpty) {
                      return _EmptyState(
                        subtitle: l.completeToSeeHistory,
                      );
                    }

                    final approved = history
                        .where((q) => q.status == UserQuestStatus.approved)
                        .length;
                    final rejected = history
                        .where((q) => q.status == UserQuestStatus.rejected)
                        .length;
                    final expired = history
                        .where((q) => q.status == UserQuestStatus.expired)
                        .length;

                    return Column(
                      children: [
                        // ── Stat row ────────────────────────────────
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: QuestSpacing.screenPadding,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: _ArcadeCountTile(
                                  label: 'COMPLETED',
                                  value: approved,
                                  tint: QuestColors.successGreen,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _ArcadeCountTile(
                                  label: 'REJECTED',
                                  value: rejected,
                                  tint: QuestColors.softRed,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: _ArcadeCountTile(
                                  label: 'EXPIRED',
                                  value: expired,
                                  tint: QuestColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // ── List ─────────────────────────────────────
                        Expanded(
                          child: ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(
                              QuestSpacing.screenPadding,
                              4,
                              QuestSpacing.screenPadding,
                              24,
                            ),
                            itemCount: history.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final uq = history[index];
                              final quest = uq.quest;
                              return _ArcadeHistoryCard(
                                title: quest?.title ?? 'Quest',
                                category: quest?.category ?? '',
                                difficulty: quest?.difficulty ?? '',
                                xpReward: quest?.xpReward ?? 0,
                                status: uq.status,
                                onTap: quest != null
                                    ? () => context.pushNamed(
                                          RouteNames.questDetails,
                                          pathParameters: {'id': uq.questId},
                                        )
                                    : null,
                              );
                            },
                          ),
                        ),
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
}

// ── Count-up stat tile ──────────────────────────────────────────────────────

class _ArcadeCountTile extends StatefulWidget {
  const _ArcadeCountTile({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final int value;
  final Color tint;

  @override
  State<_ArcadeCountTile> createState() => _ArcadeCountTileState();
}

class _ArcadeCountTileState extends State<_ArcadeCountTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ac = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _ac.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: widget.tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ink, width: 2),
        boxShadow: [
          BoxShadow(
            color: ink,
            offset: const Offset(2, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: _ac,
            builder: (_, __) {
              final v =
                  (widget.value * Curves.easeOutCubic.transform(_ac.value))
                      .round();
              return Text(
                '$v',
                style: QuestTypography.headlineLarge.copyWith(
                  color: QuestColors.osTextOnPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Text(
            widget.label,
            style: QuestTypography.labelSmall.copyWith(
              color: QuestColors.osTextOnPrimary,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

// ── History card ────────────────────────────────────────────────────────────

class _ArcadeHistoryCard extends StatelessWidget {
  const _ArcadeHistoryCard({
    required this.title,
    required this.category,
    required this.difficulty,
    required this.xpReward,
    required this.status,
    this.onTap,
  });

  final String title;
  final String category;
  final String difficulty;
  final int xpReward;
  final String status;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    final (statusLabel, statusColor) = _status();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ink, width: 2),
          boxShadow: [
            BoxShadow(
              color: ink,
              offset: const Offset(2, 3),
              blurRadius: 0,
            ),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Status pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ink, width: 1.5),
                  ),
                  child: Text(
                    statusLabel,
                    style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.osTextOnPrimary,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (category.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: QuestColors.osPrimary.withAlpha(40),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: QuestColors.osPrimary, width: 1.5),
                    ),
                    child: Text(
                      category.toUpperCase(),
                      style: QuestTypography.labelSmall.copyWith(
                        color: QuestColors.osPrimary,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                const Spacer(),
                if (xpReward > 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: QuestColors.accentYellow,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: ink, width: 1.5),
                    ),
                    child: Text(
                      '+$xpReward XP',
                      style: QuestTypography.labelSmall.copyWith(
                        color: ink,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: QuestTypography.headlineSmall.copyWith(
                color: ink,
                fontSize: 15,
                fontWeight: FontWeight.w800,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (difficulty.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                difficulty.toUpperCase(),
                style: QuestTypography.labelSmall.copyWith(
                  color: ink.withAlpha(160),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  (String, Color) _status() {
    switch (status) {
      case UserQuestStatus.approved:
        return ('COMPLETED', QuestColors.successGreen);
      case UserQuestStatus.rejected:
        return ('REJECTED', QuestColors.softRed);
      case UserQuestStatus.expired:
        return ('EXPIRED', QuestColors.textMuted);
      case UserQuestStatus.submitted:
        return ('IN REVIEW', QuestColors.accentYellow);
      default:
        return (status.toUpperCase(), QuestColors.osPrimary);
    }
  }
}

// ── Empty + error ──────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.subtitle});
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: ink, width: 2.5),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [QuestColors.osPrimary, QuestColors.softRed],
              ),
              boxShadow: [
                BoxShadow(
                  color: ink,
                  offset: const Offset(2, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: const Icon(Icons.history_rounded,
                color: QuestColors.osTextOnPrimary, size: 38),
          ),
          const SizedBox(height: 20),
          Text(
            AppLocalizations.of(context)!.noQuestsYet,
            style: QuestTypography.headlineSmall.copyWith(
              color: ink,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              subtitle,
              textAlign: TextAlign.center,
              style: QuestTypography.bodyMedium.copyWith(
                color: ink.withAlpha(170),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.retry,
    required this.onRetry,
  });
  final String message;
  final String retry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 80),
        Center(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: QuestColors.softRed,
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: ink,
                  offset: const Offset(2, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: const Icon(Icons.error_outline,
                color: QuestColors.osTextOnPrimary, size: 36),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: Text(
            message,
            style: QuestTypography.headlineSmall.copyWith(
              color: ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: GestureDetector(
            onTap: onRetry,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: QuestColors.accentYellow,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: ink,
                    offset: const Offset(2, 3),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Text(
                retry.toUpperCase(),
                style: QuestTypography.labelMedium.copyWith(
                  color: ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
