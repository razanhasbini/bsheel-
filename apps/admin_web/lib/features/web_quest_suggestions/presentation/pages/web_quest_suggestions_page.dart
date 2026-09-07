import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final webQuestSuggestionsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>(
  (ref, statusFilter) async {
    final client = ref.watch(supabaseClientProvider);
    var query = client.from('quest_suggestions').select(
          'id, title, description, category, difficulty, suggested_by_name, suggested_by_handle, status, created_at',
        );
    if (statusFilter != 'all') {
      query = query.eq('status', statusFilter);
    }
    final data = await query.order('created_at', ascending: false).limit(500);
    return List<Map<String, dynamic>>.from(data as List);
  },
);

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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelCard(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BsheelEyebrow('Web · Suggestions'),
              const SizedBox(height: 14),
              BsheelDisplay(
                'Community quest {ideas.}',
                baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
              ),
              const SizedBox(height: 12),
              Text(
                'Quest ideas submitted from the marketing site. Approve '
                'to copy into the live quest bank, or dismiss.',
                style: BsheelType.bodyMd
                    .copyWith(color: BsheelColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: _FilterTabs(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
        ),
        Expanded(
            child: async.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: BsheelColors.primary),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e',
                    style: BsheelType.bodySm.copyWith(color: BsheelColors.hot),),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inbox_outlined,
                            size: 64,
                            color: BsheelColors.primary.withAlpha(100),),
                        const SizedBox(height: QuestSpacing.md),
                        Text('NO ${_filter.toUpperCase()} SUGGESTIONS',
                            style: BsheelType.displaySm
                                .copyWith(color: BsheelColors.inkMuted),),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: QuestSpacing.sm),
                  itemBuilder: (context, index) {
                    final r = rows[index];
                    return _SuggestionCard(
                      data: r,
                      onApprove: () => _approve(r),
                      onReject: () => _setStatus(r['id'] as String, 'rejected'),
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  // Defaults for quests created from a suggestion — mirror the "new quest"
  // dialog defaults in quest_management_page (xp 50, 4h timer, active).
  static const int _approvedXpReward = 50;
  static const int _approvedDurationHours = 4;

  /// Approving really copies the suggestion into the live quest bank:
  /// insert into `quests` first, and only mark the suggestion approved
  /// once that insert succeeds.
  Future<void> _approve(Map<String, dynamic> suggestion) async {
    final id = suggestion['id'] as String;
    final title = (suggestion['title'] ?? '').toString().trim();
    final description = (suggestion['description'] ?? '').toString().trim();

    // The marketing site sends free-form category/difficulty text; the
    // quests table enforces CHECK constraints, so normalise to the same
    // allowed sets (and dialog defaults) used by quest management.
    const allowedCategories = {
      QuestCategory.fitness,
      QuestCategory.creativity,
      QuestCategory.social,
      QuestCategory.learning,
      QuestCategory.adventure,
    };
    const allowedDifficulties = {
      QuestDifficulty.easy,
      QuestDifficulty.medium,
      QuestDifficulty.hard,
    };
    final rawCategory =
        (suggestion['category'] ?? '').toString().trim().toLowerCase();
    final category = allowedCategories.contains(rawCategory)
        ? rawCategory
        : QuestCategory.fitness;
    final rawDifficulty =
        (suggestion['difficulty'] ?? '').toString().trim().toLowerCase();
    final difficulty = allowedDifficulties.contains(rawDifficulty)
        ? rawDifficulty
        : QuestDifficulty.easy;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BsheelColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.md),
          side: const BorderSide(color: BsheelColors.ink, width: 1),
        ),
        title: Text(
          'APPROVE SUGGESTION',
          style: BsheelType.displaySm.copyWith(color: BsheelColors.ink),
        ),
        content: Text(
          'Approve "$title"?\n\n'
          'This adds it to the live quest bank as an active $difficulty '
          '$category quest ($_approvedXpReward XP · '
          '${_approvedDurationHours}h timer).',
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.success,
              foregroundColor: BsheelColors.pureBlack,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'APPROVE',
              style:
                  BsheelType.labelSm.copyWith(color: BsheelColors.pureBlack),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final client = ref.read(supabaseClientProvider);

    // 1) Copy into the quest bank — same column set as quest management's
    //    _saveQuest insert.
    try {
      await client.from(Tables.quests).insert({
        QuestColumns.title: title,
        QuestColumns.description: description,
        QuestColumns.category: category,
        QuestColumns.difficulty: difficulty,
        QuestColumns.xpReward: _approvedXpReward,
        QuestColumns.durationHours: _approvedDurationHours,
        QuestColumns.isActive: true,
        QuestColumns.createdBy: client.auth.currentUser!.id,
      });
    } catch (e) {
      // Quest insert failed → the suggestion must NOT be marked approved.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not add quest to the bank — suggestion left pending: $e',
            ),
          ),
        );
      }
      return;
    }

    // 2) Only now flip the suggestion's status.
    try {
      await client
          .from('quest_suggestions')
          .update({'status': 'approved'}).eq('id', id);
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
          SnackBar(
            content: Text(
              'Quest was added, but marking the suggestion approved '
              'failed: $e',
            ),
          ),
        );
      }
    }
    ref.invalidate(webQuestSuggestionsProvider(_filter));
  }

  Future<void> _setStatus(String id, String status) async {
    final client = ref.read(supabaseClientProvider);
    try {
      await client
          .from('quest_suggestions')
          .update({'status': status}).eq('id', id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                status == 'approved' ? 'Marked approved.' : 'Marked rejected.',),
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

class _FilterTabs extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _FilterTabs({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tabs = [
      ('pending', 'PENDING'),
      ('approved', 'APPROVED'),
      ('rejected', 'REJECTED'),
      ('all', 'ALL'),
    ];
    return Wrap(
      spacing: QuestSpacing.xs,
      children: tabs.map((t) {
        final selected = value == t.$1;
        return ChoiceChip(
          label: Text(
            t.$2,
            style: BsheelType.labelSm.copyWith(
              letterSpacing: 1.2,
              color: selected ? BsheelColors.ink : BsheelColors.inkMuted,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          selected: selected,
          backgroundColor: BsheelColors.bg,
          selectedColor: BsheelColors.accent,
          side: const BorderSide(color: BsheelColors.ink, width: 1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BsheelRadii.sm),
          ),
          onSelected: (_) => onChanged(t.$1),
        );
      }).toList(),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _SuggestionCard({
    required this.data,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final title = (data['title'] ?? '') as String;
    final description = (data['description'] ?? '') as String;
    final category = (data['category'] ?? '') as String;
    final difficulty = (data['difficulty'] ?? '') as String;
    final suggesterName = (data['suggested_by_name'] ?? '') as String?;
    final suggesterHandle = (data['suggested_by_handle'] ?? '') as String?;
    final status = (data['status'] ?? 'pending') as String;
    final createdAt = DateTime.tryParse((data['created_at'] ?? '') as String);

    return Container(
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        border: Border.all(color: BsheelColors.ink, width: 1),
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: BsheelType.bodyMdBold.copyWith(
                    color: BsheelColors.ink,
                    fontSize: 17,
                  ),
                ),
              ),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: QuestSpacing.xs),
          Wrap(
            spacing: QuestSpacing.xs,
            runSpacing: 4,
            children: [
              _Chip(label: category.toUpperCase(), color: BsheelColors.primary),
              _Chip(label: difficulty.toUpperCase(), color: BsheelColors.cool),
            ],
          ),
          const SizedBox(height: QuestSpacing.sm),
          Text(
            description,
            style: BsheelType.bodyMd.copyWith(color: BsheelColors.ink),
          ),
          const SizedBox(height: QuestSpacing.sm),
          Row(
            children: [
              if ((suggesterName ?? '').isNotEmpty ||
                  (suggesterHandle ?? '').isNotEmpty)
                Expanded(
                  child: Text(
                    [
                      if ((suggesterName ?? '').isNotEmpty) suggesterName,
                      if ((suggesterHandle ?? '').isNotEmpty) suggesterHandle,
                    ].whereType<String>().join(' · '),
                    style: BsheelType.labelSm
                        .copyWith(color: BsheelColors.inkMuted),
                  ),
                )
              else
                Expanded(
                  child: Text(
                    'Anonymous submission',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.inkMuted,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              if (createdAt != null)
                Text(
                  _formatDate(createdAt),
                  style:
                      BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
                ),
            ],
          ),
          if (status == 'pending') ...[
            const SizedBox(height: QuestSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close, size: 16),
                  label: Text(
                    'REJECT',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.hot,
                      letterSpacing: 1.2,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: BsheelColors.hot, width: 1),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(BsheelRadii.sm),
                    ),
                  ),
                ),
                const SizedBox(width: QuestSpacing.sm),
                ElevatedButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check, size: 16),
                  label: Text(
                    'APPROVE',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.pureBlack,
                      letterSpacing: 1.2,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: BsheelColors.success,
                    foregroundColor: BsheelColors.pureBlack,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(BsheelRadii.sm),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg) = switch (status) {
      'approved' => (BsheelColors.success, BsheelColors.pureBlack),
      'rejected' => (BsheelColors.hot, BsheelColors.paper),
      _ => (BsheelColors.accent, BsheelColors.ink),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: BsheelColors.ink, width: 1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.toUpperCase(),
        style: BsheelType.labelSm.copyWith(
          color: fg,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
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
        color: color.withAlpha(40),
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: BsheelType.labelSm.copyWith(
          color: color,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
