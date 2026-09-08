import 'package:app_contracts/app_contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final webQuestSuggestionsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, statusFilter) async {
    return AppBackend.repositories.admin.suggestions(
      status: statusFilter,
      limit: 500,
    );
  },
);

/// The status a suggestion holds until a moderator decides — the string the
/// intake endpoint writes and the one this page reads back. Suggestion
/// statuses have no `app_contracts` class, so this names the value the
/// existing code path already used rather than restating it at each site.
const String _statusPending = 'pending';

/// The categories the live quest bank owns, from `app_contracts` rather than
/// restated here. A suggestion whose category falls outside this set is drawn
/// untinted instead of being mapped to a colour it does not carry.
const Set<String> _questBankCategories = {
  QuestCategory.fitness,
  QuestCategory.creativity,
  QuestCategory.social,
  QuestCategory.learning,
  QuestCategory.adventure,
};

// ── Page ──────────────────────────────────────────────────────────────────────

class WebQuestSuggestionsPage extends ConsumerStatefulWidget {
  const WebQuestSuggestionsPage({super.key});

  @override
  ConsumerState<WebQuestSuggestionsPage> createState() =>
      _WebQuestSuggestionsPageState();
}

class _WebQuestSuggestionsPageState
    extends ConsumerState<WebQuestSuggestionsPage> {
  String _filter = 'pending';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(webQuestSuggestionsProvider(_filter));

    return AdminPane(
      title: 'Quest suggestions',
      meta: 'From players',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BsheelFilterChips(
            filters: const [
              BsheelFilter('pending', 'Pending'),
              BsheelFilter('approved', 'Approved'),
              BsheelFilter('rejected', 'Rejected'),
              BsheelFilter('all', 'All'),
            ],
            selected: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
          const SizedBox(height: 12),
          async.when(
            loading: () => const BsheelLoadingList(rows: 4, rowHeight: 108),
            error: (e, _) => BsheelErrorState(
              title: 'Suggestions didn’t load',
              message: 'The suggestion list didn’t come back, so nothing was '
                  'added to the quest bank and nothing was discarded. $e',
              onRetry: () =>
                  ref.invalidate(webQuestSuggestionsProvider(_filter)),
            ),
            data: (rows) {
              if (rows.isEmpty) return _empty();

              // A coloured shadow marks the one card that needs attention —
              // the oldest suggestion still waiting on a decision.
              final firstPending =
                  rows.indexWhere((r) => _status(r) == _statusPending);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i != 0) const SizedBox(height: 11),
                    _SuggestionCard(
                      data: rows[i],
                      highlighted: i == firstPending,
                      onApprove: () => _approve(rows[i]),
                      onReject: () =>
                          _setStatus(rows[i]['id'] as String, 'rejected'),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _empty() {
    final onAll = _filter == 'all';
    return BsheelEmptyState(
      title: onAll ? 'No suggestions yet' : 'Nothing $_filter',
      message: onAll
          ? 'No player has suggested a quest from the marketing site yet.'
          : 'No suggestion is $_filter right now. Switch to ALL to see every '
              'idea players have sent in.',
      actionLabel: onAll ? 'Reload' : 'Show all',
      onAction: onAll
          ? () => ref.invalidate(webQuestSuggestionsProvider(_filter))
          : () => setState(() => _filter = 'all'),
    );
  }

  // Defaults for quests created from a suggestion — mirror the "new quest"
  // dialog defaults in quest_management_page (xp 50, 4h timer, active).
  static const int _approvedXpReward = 50;
  static const int _approvedDurationHours = 4;

  static String _status(Map<String, dynamic> row) =>
      (row['status'] ?? _statusPending) as String;

  /// Approving really copies the suggestion into the live quest bank:
  /// insert into `quests` first, and only mark the suggestion approved
  /// once that insert succeeds.
  Future<void> _approve(Map<String, dynamic> suggestion) async {
    final id = suggestion['id'] as String;
    final title = (suggestion['title'] ?? '').toString().trim();
    // Category and difficulty need no client-side normalisation: the
    // intake endpoint only accepts the allowed values, and
    // `quest_suggestions` carries the same CHECK constraints as `quests`.
    final category = (suggestion['category'] ?? '').toString();
    final difficulty = (suggestion['difficulty'] ?? '').toString();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Approve suggestion',
        content: Text(
          'Approve “$title”?\n\n'
          'This adds it to the live quest bank as an active $difficulty '
          '$category quest ($_approvedXpReward XP · '
          '${_approvedDurationHours}h timer).',
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.positive(
            label: 'Add to bank',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // One audited transaction on the API creates the quest and flips the
    // suggestion together. The old two-step client version could leave a
    // quest in the bank with the suggestion still pending, or the reverse.
    try {
      await AppBackend.repositories.admin.reviewSuggestion(
        id,
        status: 'approved',
        xpReward: _approvedXpReward,
        durationHours: _approvedDurationHours,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Approved — quest added to the live bank.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approve failed — suggestion unchanged: $e')),
        );
      }
    }
    ref.invalidate(webQuestSuggestionsProvider(_filter));
  }

  Future<void> _setStatus(String id, String status) async {
    try {
      await AppBackend.repositories.admin.reviewSuggestion(
        id,
        status: status,
        xpReward: _approvedXpReward,
        durationHours: _approvedDurationHours,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'approved' ? 'Marked approved.' : 'Marked rejected.',
            ),
          ),
        );
      }
      ref.invalidate(webQuestSuggestionsProvider(_filter));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e')),
        );
      }
    }
  }
}

// ── Card ──────────────────────────────────────────────────────────────────────

class _SuggestionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool highlighted;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _SuggestionCard({
    required this.data,
    required this.highlighted,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? '') as String;
    final description = (data['description'] ?? '') as String;
    final category = (data['category'] ?? '') as String;
    final difficulty = (data['difficulty'] ?? '') as String;
    final status = (data['status'] ?? _statusPending) as String;
    final pending = status == _statusPending;

    return BsheelCard(
      padding: const EdgeInsets.all(13),
      shadowColor: highlighted ? BsheelColors.success : BsheelColors.ink,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: BsheelType.bodySmMedium.copyWith(fontSize: 15),
          ),
          const SizedBox(height: 8),
          Text(_metaLine(), style: BsheelType.labelMd),
          if (category.isNotEmpty || difficulty.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (category.isNotEmpty)
                  _questBankCategories.contains(category)
                      ? BsheelTag.category(category)
                      : BsheelTag(category),
                if (difficulty.isNotEmpty) BsheelTag(difficulty),
              ],
            ),
          ],
          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              description,
              style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
            ),
          ],
          const SizedBox(height: 8),
          if (pending)
            Row(
              children: [
                BsheelButton.positive(
                  label: 'Add to bank',
                  small: true,
                  onPressed: onApprove,
                ),
                const SizedBox(width: 7),
                BsheelButton.ghost(
                  label: 'Discard',
                  small: true,
                  onPressed: onReject,
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerLeft,
              child: BsheelPill.status(status),
            ),
        ],
      ),
    );
  }

  /// `nour.k · 11 MAR · SUGGESTED SOCIAL` — the mono meta line the design
  /// draws. The handle is the public identity, so it wins over the display
  /// name; an intake with neither reads as anonymous rather than blank.
  String _metaLine() {
    final handle = (data['suggested_by_handle'] ?? '').toString().trim();
    final name = (data['suggested_by_name'] ?? '').toString().trim();
    final category = (data['category'] ?? '').toString().trim();
    final createdAt = DateTime.tryParse((data['created_at'] ?? '').toString());

    return [
      if (handle.isNotEmpty)
        handle
      else if (name.isNotEmpty)
        name
      else
        'anonymous',
      if (createdAt != null) _formatDate(createdAt),
      if (category.isNotEmpty) 'SUGGESTED ${category.toUpperCase()}',
    ].join(' · ');
  }

  static const List<String> _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];

  /// `11 MAR` — the form the design draws.
  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')} '
        '${_months[local.month - 1]}';
  }
}
