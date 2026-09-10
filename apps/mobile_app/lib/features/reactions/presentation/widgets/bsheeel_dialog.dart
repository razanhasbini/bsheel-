import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_core/app_core.dart';
import '../../../../core/utils/account_lock_guard.dart';
import '../../../quests/data/quest_providers.dart';
import '../providers/reaction_controller.dart';

/// Shows the BSHEEEL popup flow.
///
/// Outcomes from the prompt:
///   * `null`  — barrier tap / outside the card → do nothing (no save)
///   * `false` — JUST SAVE → save the post, stop
///   * `true`  — LET'S GO!  → save the post AND assign the quest
///
/// If the post is already saved, this just toggles it off (unsave).
Future<void> showBsheeelDialog({
  required BuildContext context,
  required WidgetRef ref,
  required String submissionId,
  required String questId,
  required String questTitle,
  required String userId,
}) async {
  // Banned/suspended account: skip both the optimistic flip AND the
  // dialog. RLS would reject the save anyway and the dialog is a
  // false-promise of action.
  if (guardAccountAction(context, ref)) return;

  final repo = ref.read(savedPostsRepositoryProvider);
  final isSaved = ref
          .read(
              isPostSavedProvider((submissionId: submissionId, userId: userId)))
          .valueOrNull ??
      false;

  // Already saved → toggle OFF immediately. No dialog.
  if (isSaved) {
    await repo.unsavePost(submissionId, userId);
    ref.invalidate(
      isPostSavedProvider((submissionId: submissionId, userId: userId)),
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('REMOVED FROM BSHEEEL'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    return;
  }

  // Not saved → ask FIRST, save AFTER confirmation. Tapping outside the
  // card returns null and we treat that as "cancel, don't save".
  final choice = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _BsheeelTakeOnDialog(questTitle: questTitle),
  );

  if (choice == null) {
    // User dismissed the card by tapping outside — no save.
    return;
  }

  // User picked an action — save now, then maybe take the quest.
  await repo.savePost(submissionId, userId);
  ref.invalidate(
    isPostSavedProvider((submissionId: submissionId, userId: userId)),
  );

  if (choice == false) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SAVED TO BSHEEEL'),
          duration: Duration(seconds: 1),
        ),
      );
    }
    return;
  }

  // choice == true → save + assign.
  if (!context.mounted) return;
  await assignQuestFlow(
    context: context,
    ref: ref,
    questId: questId,
    questTitle: questTitle,
    userId: userId,
  );
}

/// Asks for confirmation, then assigns the quest as the user's active quest.
/// If the user already has an active quest, surface a snackbar and stop —
/// no replace flow (the active quest must finish first).
Future<void> assignQuestFlow({
  required BuildContext context,
  required WidgetRef ref,
  required String questId,
  required String questTitle,
  required String userId,
}) async {
  // Use the *cached* active-quest value so the BSHEEEL tap responds
  // instantly. Previously this awaited a network refetch before opening
  // the confirm dialog — the server-side `assign_specific_quest` RPC
  // already rejects duplicates, and the catch-block below surfaces the
  // same "already active" snackbar, so the eager refetch was just lag.
  final activeQuest = ref.read(activeQuestProvider).valueOrNull;

  // Only a LIVE quest blocks a new one. `/quests/active` also returns rows
  // whose status is `submitted`, and this checked for null alone — so a
  // player whose only quest was awaiting moderation could not take another
  // from the detail page, a profile, or this dialog, even though the server
  // accepts it. Migration 0021 narrowed the database index for exactly this
  // reason: review latency is not something the player can clear, and
  // blocking on it leaves them with nothing to do.
  if (activeQuest != null && activeQuest.status == UserQuestStatus.assigned) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Can't — there is already an active quest"),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => _ConfirmTakeQuestDialog(questTitle: questTitle),
  );
  if (confirm != true || !context.mounted) return;

  try {
    await ref
        .read(questsRepositoryProvider)
        .assignSpecificQuest(userId, questId);
    ref.invalidate(activeQuestProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('QUEST ASSIGNED: ${questTitle.toUpperCase()}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  } catch (e) {
    if (!context.mounted) return;
    final msg = e.toString();
    String userMsg = 'Failed to assign quest';
    if (msg.contains('not found or inactive')) {
      userMsg = 'This quest is no longer active';
    } else if (msg.contains('already has an active quest')) {
      userMsg = "Can't — there is already an active quest";
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(userMsg)));
  }
}

class _ConfirmTakeQuestDialog extends StatelessWidget {
  const _ConfirmTakeQuestDialog({required this.questTitle});
  final String questTitle;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ink, width: 2),
          boxShadow: [
            BoxShadow(color: ink, offset: const Offset(0, 4), blurRadius: 0),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: QuestColors.accentYellow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ink, width: 2),
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.flag_rounded,
                  color: QuestColors.accentYellowInk, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              'TAKE THIS QUEST?',
              textAlign: TextAlign.center,
              style: QuestTypography.headlineSmall.copyWith(
                color: ink,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              questTitle,
              textAlign: TextAlign.center,
              style: QuestTypography.bodyMedium.copyWith(
                color: ink.withAlpha(QuestColors.alphaInkMuted),
                height: 1.3,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: QuestColors.cardBg(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ink, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'CANCEL',
                        style: QuestTypography.labelMedium.copyWith(
                          color: ink,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      constraints: const BoxConstraints(
                        minHeight: QuestSpacing.minTouchTarget,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: QuestColors.osSuccess,
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
                        'YES',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: QuestTypography.labelMedium.copyWith(
                          color: QuestColors.onAccent(QuestColors.osSuccess),
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
    );
  }
}

// ── BSHEEEL? card — chunky Arcade-Pop style ─────────────────────────────────

class _BsheeelTakeOnDialog extends StatelessWidget {
  const _BsheeelTakeOnDialog({required this.questTitle});
  final String questTitle;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
        decoration: BoxDecoration(
          color: QuestColors.cardBg(context),
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
          children: [
            // Bookmark badge
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: QuestColors.accentYellow,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: ink, width: 2),
                boxShadow: [
                  BoxShadow(
                      color: ink, offset: const Offset(0, 3), blurRadius: 0),
                ],
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.bookmark_rounded,
                  color: QuestColors.accentYellowInk, size: 32),
            ),
            const SizedBox(height: 16),
            // Title
            Text(
              'BSHEEEL?',
              textAlign: TextAlign.center,
              style: QuestTypography.headlineLarge.copyWith(
                color: ink,
                fontSize: 26,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Save it — and want to take it on?',
              textAlign: TextAlign.center,
              style: QuestTypography.bodyMedium.copyWith(
                color: ink.withAlpha(QuestColors.alphaInkMuted),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 14),
            // Quest title chip
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: QuestColors.bg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ink.withAlpha(70), width: 2),
              ),
              child: Text(
                questTitle.toUpperCase(),
                textAlign: TextAlign.center,
                style: QuestTypography.labelMedium.copyWith(
                  color: ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 18),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: _PopBtn(
                    label: 'JUST SAVE',
                    fill: QuestColors.cardBg(context),
                    fg: ink,
                    raised: false,
                    onTap: () => Navigator.pop(context, false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PopBtn(
                    label: "LET'S GO!",
                    fill: QuestColors.accentYellow,
                    fg: QuestColors.accentYellowInk,
                    raised: true,
                    onTap: () => Navigator.pop(context, true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PopBtn extends StatelessWidget {
  const _PopBtn({
    required this.label,
    required this.fill,
    required this.fg,
    required this.raised,
    required this.onTap,
  });

  final String label;
  final Color fill;
  final Color fg;
  final bool raised;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = QuestColors.text(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink, width: 2),
          boxShadow: raised
              ? [
                  BoxShadow(
                      color: ink, offset: const Offset(0, 3), blurRadius: 0),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: QuestTypography.labelMedium.copyWith(
            color: fg,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
