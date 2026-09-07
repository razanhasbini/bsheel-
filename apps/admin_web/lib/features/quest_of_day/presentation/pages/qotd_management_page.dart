import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Quest-of-the-Day scheduler. Admins pick one quest per UTC day and the
/// home page renders the entry whose `display_date` matches the current
/// UTC date (see migration 0139 + `get_quest_of_the_day`).
///
/// Past entries stay in the table for the audit trail — they just stop
/// being surfaced once the day rolls over.
class QotdManagementPage extends ConsumerStatefulWidget {
  const QotdManagementPage({super.key});

  @override
  ConsumerState<QotdManagementPage> createState() =>
      _QotdManagementPageState();
}

class _QotdManagementPageState extends ConsumerState<QotdManagementPage> {
  bool _busy = false;

  Future<List<_QotdEntry>> _loadEntries() async {
    // Pull the full list joined with quests so the admin sees the quest
    // title without a second round-trip. Show 60 days back + every queued
    // future entry — admins occasionally queue weeks ahead.
    final rows = await Supabase.instance.client
        .from(Tables.questOfTheDay)
        .select(
            'id, display_date, ticket_no, bonus_xp, note, created_at, quest_id, quests(title, category, xp_reward, difficulty)',)
        .gte('display_date',
            DateTime.now().toUtc().subtract(const Duration(days: 60)).toIso8601String().split('T').first,)
        .order('display_date', ascending: false);
    return (rows as List).map((r) {
      final m = r as Map<String, dynamic>;
      final q = (m['quests'] as Map<String, dynamic>?) ?? {};
      return _QotdEntry(
        id: m['id'] as String,
        displayDate: DateTime.parse(m['display_date'] as String),
        ticketNo: m['ticket_no'] as String?,
        bonusXp: (m['bonus_xp'] as int?) ?? 0,
        note: m['note'] as String?,
        questId: m['quest_id'] as String,
        questTitle: (q['title'] as String?) ?? '(quest deleted)',
        questCategory: (q['category'] as String?) ?? '',
        questXp: (q['xp_reward'] as int?) ?? 0,
        questDifficulty: (q['difficulty'] as String?) ?? 'medium',
      );
    }).toList();
  }

  Future<List<_QuestRow>> _loadQuests() async {
    final rows = await Supabase.instance.client
        .from(Tables.quests)
        .select('id, title, category, xp_reward, difficulty, is_active')
        .eq('is_active', true)
        .order('title');
    return (rows as List)
        .map((r) => _QuestRow.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  Future<void> _save({
    String? existingId,
    required DateTime date,
    required String questId,
    String? ticketNo,
    int bonusXp = 0,
    String? note,
  }) async {
    setState(() => _busy = true);
    try {
      final payload = {
        'display_date':
            DateTime.utc(date.year, date.month, date.day).toIso8601String().split('T').first,
        'quest_id': questId,
        'ticket_no': (ticketNo == null || ticketNo.isEmpty) ? null : ticketNo,
        'bonus_xp': bonusXp,
        'note': (note == null || note.isEmpty) ? null : note,
        'created_by': Supabase.instance.client.auth.currentUser?.id,
      };
      if (existingId != null) payload['id'] = existingId;

      // ON CONFLICT on display_date so admins can fix a typo without
      // first deleting the row. The unique index in migration 0139 backs
      // this behavior.
      await Supabase.instance.client.from(Tables.questOfTheDay).upsert(
            payload,
            onConflict: 'display_date',
          );
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BsheelColors.paper,
        title: const Text(
          'DELETE QOTD ENTRY?',
          style: TextStyle(color: BsheelColors.ink, letterSpacing: 1.5),
        ),
        content: const Text(
          "The home-page ticket will disappear for that day. Quests themselves aren't touched.",
          style: TextStyle(color: BsheelColors.inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.hot,
              foregroundColor: BsheelColors.pureWhite,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await Supabase.instance.client
          .from(Tables.questOfTheDay)
          .delete()
          .eq('id', id);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEditor({_QotdEntry? existing}) async {
    final quests = await _loadQuests();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _QotdEditorDialog(
        existing: existing,
        quests: quests,
        onSave: ({
          required DateTime date,
          required String questId,
          String? ticketNo,
          int bonusXp = 0,
          String? note,
        }) async {
          await _save(
            existingId: existing?.id,
            date: date,
            questId: questId,
            ticketNo: ticketNo,
            bonusXp: bonusXp,
            note: note,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BsheelCard(
            padding:
                const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelEyebrow('Curation · Quest of the Day'),
                const SizedBox(height: 14),
                BsheelDisplay(
                  'Stack a {ticket} per day.',
                  baseStyle:
                      BsheelType.displayXl.copyWith(fontSize: 44),
                ),
                const SizedBox(height: 12),
                Text(
                  'One quest per UTC day shows as the yellow ticket above the generator. Queue future entries to keep the rotation hot — uniqueness on `display_date` means you can edit any row by saving the same date.',
                  style:
                      BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  ElevatedButton.icon(
                    onPressed: _busy ? null : () => _openEditor(),
                    icon: const Icon(Icons.add),
                    label: const Text('QUEUE NEW QOTD'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BsheelColors.ink,
                      foregroundColor: BsheelColors.paper,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14,),
                    ),
                  ),
                ],),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: FutureBuilder<List<_QotdEntry>>(
              future: _loadEntries(),
              builder: (ctx, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),);
                }
                if (snap.hasError) {
                  return Text(
                    'Error loading entries: ${snap.error}',
                    style: const TextStyle(color: BsheelColors.hot),
                  );
                }
                final entries = snap.data ?? const <_QotdEntry>[];
                if (entries.isEmpty) {
                  return BsheelCard(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No quests queued yet. Hit QUEUE NEW QOTD above.',
                      style: BsheelType.bodyMd
                          .copyWith(color: BsheelColors.inkSoft),
                    ),
                  );
                }
                final todayUtc = DateTime.now().toUtc();
                final todayKey = DateTime.utc(
                    todayUtc.year, todayUtc.month, todayUtc.day,);
                return Column(
                  children: [
                    for (final e in entries) ...[
                      _QotdRow(
                        entry: e,
                        isToday: e.displayDate == todayKey,
                        isFuture: e.displayDate.isAfter(todayKey),
                        onEdit: () => _openEditor(existing: e),
                        onDelete: () => _delete(e.id),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
// Row + Editor
// ─────────────────────────────────────────────────────────────────────────

class _QotdEntry {
  _QotdEntry({
    required this.id,
    required this.displayDate,
    required this.ticketNo,
    required this.bonusXp,
    required this.note,
    required this.questId,
    required this.questTitle,
    required this.questCategory,
    required this.questXp,
    required this.questDifficulty,
  });

  final String id;
  final DateTime displayDate;
  final String? ticketNo;
  final int bonusXp;
  final String? note;
  final String questId;
  final String questTitle;
  final String questCategory;
  final int questXp;
  final String questDifficulty;
}

class _QuestRow {
  _QuestRow({
    required this.id,
    required this.title,
    required this.category,
    required this.xpReward,
    required this.difficulty,
  });

  final String id;
  final String title;
  final String category;
  final int xpReward;
  final String difficulty;

  factory _QuestRow.fromMap(Map<String, dynamic> m) => _QuestRow(
        id: m['id'] as String,
        title: (m['title'] as String?) ?? '',
        category: (m['category'] as String?) ?? '',
        xpReward: (m['xp_reward'] as int?) ?? 0,
        difficulty: (m['difficulty'] as String?) ?? 'medium',
      );
}

class _QotdRow extends StatelessWidget {
  const _QotdRow({
    required this.entry,
    required this.isToday,
    required this.isFuture,
    required this.onEdit,
    required this.onDelete,
  });

  final _QotdEntry entry;
  final bool isToday;
  final bool isFuture;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = isToday
        ? BsheelColors.ink
        : isFuture
            ? BsheelColors.inkSoft
            : BsheelColors.inkMuted;
    final dateStr =
        '${entry.displayDate.year}-${entry.displayDate.month.toString().padLeft(2, '0')}-${entry.displayDate.day.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
        border: Border.all(
          color: isToday
              ? BsheelColors.ink
              : BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(BsheelRadii.full),
              border: Border.all(
                  color: accent, width: BsheelBorders.thin,),
            ),
            child: Text(
              isToday
                  ? 'TODAY'
                  : isFuture
                      ? 'UPCOMING'
                      : 'PAST',
              style: BsheelType.labelMd.copyWith(
                color: accent,
                letterSpacing: 1.4,
                fontSize: 10,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 110,
            child: Text(
              dateStr,
              style: BsheelType.labelMd.copyWith(
                color: BsheelColors.ink,
                letterSpacing: 0.8,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.questTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: BsheelType.labelLg.copyWith(
                    color: BsheelColors.ink,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.questCategory.toUpperCase()} · ${entry.questXp + entry.bonusXp} XP'
                  '${entry.bonusXp > 0 ? " (+${entry.bonusXp} bonus)" : ""}'
                  '${entry.ticketNo != null && entry.ticketNo!.isNotEmpty ? "  ·  №${entry.ticketNo}" : ""}',
                  style: BsheelType.bodySm
                      .copyWith(color: BsheelColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onEdit,
            child: Text(
              'EDIT',
              style: BsheelType.labelMd.copyWith(color: BsheelColors.ink),
            ),
          ),
          const SizedBox(width: 4),
          TextButton(
            onPressed: onDelete,
            child: Text(
              'DELETE',
              style: BsheelType.labelMd.copyWith(color: BsheelColors.hot),
            ),
          ),
        ],
      ),
    );
  }
}

class _QotdEditorDialog extends StatefulWidget {
  const _QotdEditorDialog({
    required this.existing,
    required this.quests,
    required this.onSave,
  });

  final _QotdEntry? existing;
  final List<_QuestRow> quests;
  final Future<void> Function({
    required DateTime date,
    required String questId,
    String? ticketNo,
    int bonusXp,
    String? note,
  }) onSave;

  @override
  State<_QotdEditorDialog> createState() => _QotdEditorDialogState();
}

class _QotdEditorDialogState extends State<_QotdEditorDialog> {
  late DateTime _date;
  String? _questId;
  late final TextEditingController _ticketCtrl;
  late final TextEditingController _bonusCtrl;
  late final TextEditingController _noteCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _date = existing?.displayDate ??
        DateTime.utc(
            DateTime.now().toUtc().year,
            DateTime.now().toUtc().month,
            DateTime.now().toUtc().day,);
    _questId = existing?.questId;
    _ticketCtrl = TextEditingController(text: existing?.ticketNo ?? '');
    _bonusCtrl =
        TextEditingController(text: (existing?.bonusXp ?? 0).toString());
    _noteCtrl = TextEditingController(text: existing?.note ?? '');
  }

  @override
  void dispose() {
    _ticketCtrl.dispose();
    _bonusCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.utc(2024, 1, 1),
      lastDate: DateTime.utc(DateTime.now().year + 2, 12, 31),
    );
    if (picked != null) {
      setState(() => _date = DateTime.utc(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr =
        '${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
    return AlertDialog(
      backgroundColor: BsheelColors.paper,
      title: Text(
        widget.existing == null ? 'QUEUE NEW QOTD' : 'EDIT QOTD',
        style: const TextStyle(color: BsheelColors.ink, letterSpacing: 1.5),
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Text('Date:',
                  style: TextStyle(
                      color: BsheelColors.ink, fontWeight: FontWeight.w500,),),
              const SizedBox(width: 12),
              TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today,
                    size: 16, color: BsheelColors.ink,),
                label: Text(
                  dateStr,
                  style:
                      const TextStyle(color: BsheelColors.ink, fontSize: 14),
                ),
              ),
            ],),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _questId,
              decoration: const InputDecoration(
                labelText: 'Quest',
                helperText: 'Pick from active quests.',
              ),
              isExpanded: true,
              items: [
                for (final q in widget.quests)
                  DropdownMenuItem(
                    value: q.id,
                    child: Text(
                      '${q.title} · ${q.category} · +${q.xpReward} XP',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) => setState(() => _questId = v),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _ticketCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Ticket № (optional)',
                    helperText:
                        'Defaults to MMDD if left empty.',
                  ),
                  style: const TextStyle(color: BsheelColors.ink),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _bonusCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Bonus XP',
                    helperText: 'Above quest base reward.',
                  ),
                  style: const TextStyle(color: BsheelColors.ink),
                ),
              ),
            ],),
            const SizedBox(height: 12),
            TextField(
              controller: _noteCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Admin note (not shown to users)',
              ),
              style: const TextStyle(color: BsheelColors.ink),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('CANCEL'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: BsheelColors.ink,
            foregroundColor: BsheelColors.pureWhite,
          ),
          onPressed: _saving || _questId == null
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.onSave(
                    date: _date,
                    questId: _questId!,
                    ticketNo: _ticketCtrl.text.trim(),
                    bonusXp: int.tryParse(_bonusCtrl.text.trim()) ?? 0,
                    note: _noteCtrl.text.trim(),
                  );
                  if (context.mounted) Navigator.pop(context);
                },
          child: Text(widget.existing == null ? 'QUEUE' : 'SAVE'),
        ),
      ],
    );
  }
}
