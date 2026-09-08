import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Quest-of-the-Day scheduler. Admins pick one quest per UTC day and the
/// home page renders the entry whose `display_date` matches the current
/// UTC date (see migration 0139 + `get_quest_of_the_day`).
///
/// Past entries stay in the table for the audit trail — they just stop
/// being surfaced once the day rolls over.
///
/// The API hands `display_date` back as a bare `YYYY-MM-DD` string, which
/// `DateTime.parse` reads as *local* midnight. Every comparison here runs
/// through [_utcDay], which rebuilds the printed calendar date as UTC
/// midnight — the same day the home page matches on. Comparing a parsed
/// value directly against `DateTime.utc(...)` never matches, because
/// `DateTime ==` also compares `isUtc`.
class QotdManagementPage extends ConsumerStatefulWidget {
  const QotdManagementPage({super.key});

  @override
  ConsumerState<QotdManagementPage> createState() => _QotdManagementPageState();
}

/// The UTC day [date] names, as UTC midnight.
DateTime _utcDay(DateTime date) =>
    DateTime.utc(date.year, date.month, date.day);

/// Today, in UTC — the day the home page's ticket query uses.
DateTime _utcToday() => _utcDay(DateTime.now().toUtc());

const List<String> _monthNames = [
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

/// `13 MAR` — the 76px date column in the schedule.
String _dayMonth(DateTime day) => '${day.day} ${_monthNames[day.month - 1]}';

/// `2026-03-13` — the exact value written to `display_date`.
String _isoDay(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

class _QotdManagementPageState extends ConsumerState<QotdManagementPage> {
  bool _busy = false;
  late Future<List<_QotdEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
  }

  void _reload() {
    if (mounted) setState(() => _entriesFuture = _loadEntries());
  }

  Future<List<_QotdEntry>> _loadEntries() async {
    // Pull the full list joined with quests so the admin sees the quest
    // title without a second round-trip. Show 60 days back + every queued
    // future entry — admins occasionally queue weeks ahead.
    // Newest first, which puts queued future entries at the top. The window
    // is trimmed client-side so admins still see ~60 days of history plus
    // everything they have queued ahead.
    final rows = await AppBackend.repositories.admin.questOfTheDay(limit: 200);
    final earliest = DateTime.now().toUtc().subtract(const Duration(days: 60));
    return rows.where((row) {
      final date = DateTime.tryParse(row['display_date']?.toString() ?? '');
      return date == null || !date.isBefore(earliest);
    }).map((m) {
      final q = (m['quests'] as Map<String, dynamic>?) ?? {};
      return _QotdEntry(
        id: m['id'] as String,
        displayDate: DateTime.parse(m['display_date'] as String),
        ticketNo: m['ticket_no'] as String?,
        bonusXp: (m['bonus_xp'] as num?)?.toInt() ?? 0,
        note: m['note'] as String?,
        questId: m['quest_id'] as String,
        questTitle: (q['title'] as String?) ?? '(quest deleted)',
        questCategory: (q['category'] as String?) ?? '',
        questXp: (q['xp_reward'] as num?)?.toInt() ?? 0,
        questDifficulty: (q['difficulty'] as String?) ?? 'medium',
      );
    }).toList();
  }

  Future<List<_QuestRow>> _loadQuests() async {
    final quests = await AppBackend.repositories.quests.listAllQuestsAdmin();
    return (quests
        .where((quest) => quest.isActive)
        .map((quest) => _QuestRow(
              id: quest.id,
              title: quest.title,
              category: quest.category,
              xpReward: quest.xpReward,
              difficulty: quest.difficulty,
            ))
        .toList()
      ..sort((a, b) => a.title.compareTo(b.title)));
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
      // Upserts on display_date so an admin can fix a typo without first
      // deleting the row. The actor is taken from the access token.
      await AppBackend.repositories.admin.setQuestOfTheDay(
        questId: questId,
        displayDate: DateTime.utc(date.year, date.month, date.day)
            .toIso8601String()
            .split('T')
            .first,
        ticketNo: (ticketNo == null || ticketNo.isEmpty) ? null : ticketNo,
        bonusXp: bonusXp,
        note: (note == null || note.isEmpty) ? null : note,
      );
      _reload();
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
      builder: (ctx) => BsheelDialog(
        title: 'Pull from rotation',
        content: Text(
          'The home-page ticket will disappear for that day. Quests '
          "themselves aren't touched.",
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.coral(
            label: 'Unschedule',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await AppBackend.repositories.admin.deleteQuestOfTheDay(id);
      _reload();
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

  Future<void> _openEditor({_QotdEntry? existing, DateTime? forDay}) async {
    final quests = await _loadQuests();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _QotdEditorDialog(
        existing: existing,
        initialDate: forDay,
        quests: quests,
        onDelete: existing == null ? null : () => _delete(existing.id),
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
    return AdminPane(
      title: 'Quest of the day',
      meta: 'Schedule',
      child: FutureBuilder<List<_QotdEntry>>(
        future: _entriesFuture,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const BsheelLoadingList(rows: 4, rowHeight: 52);
          }
          if (snap.hasError) {
            return BsheelErrorState(
              message: 'The schedule did not come back. Nothing was changed '
                  '— no day has been scheduled or pulled. (${snap.error})',
              onRetry: _reload,
            );
          }
          return _schedule(context, snap.data ?? const <_QotdEntry>[]);
        },
      ),
    );
  }

  Widget _schedule(BuildContext context, List<_QotdEntry> entries) {
    final today = _utcToday();
    final byDay = <DateTime, _QotdEntry>{
      for (final entry in entries) _utcDay(entry.displayDate): entry,
    };
    final todayEntry = byDay[today];

    // Every day from tomorrow to the furthest queued entry, or a week
    // out — whichever is later. A gap between two queued days is the one
    // thing this screen exists to surface.
    var horizon = today.add(const Duration(days: 7));
    for (final day in byDay.keys) {
      if (day.isAfter(horizon)) horizon = day;
    }
    final upcoming = <DateTime>[];
    for (var day = today.add(const Duration(days: 1));
        !day.isAfter(horizon);
        day = day.add(const Duration(days: 1))) {
      upcoming.add(day);
    }

    // Newest first, as the API returns them.
    final past = [
      for (final entry in entries)
        if (_utcDay(entry.displayDate).isBefore(today)) entry,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (todayEntry != null)
          _hero(todayEntry, today)
        else
          const BsheelCallout.danger(
            'Nothing is scheduled for today. The Quest of the Day ticket '
            'will not render on the home page until a quest is scheduled.',
          ),
        const SizedBox(height: 20),
        const BsheelLabel('Scheduled'),
        const SizedBox(height: 8),
        _rowList([
          for (var i = 0; i < upcoming.length; i++)
            _dayRow(
              day: upcoming[i],
              entry: byDay[upcoming[i]],
              last: i == upcoming.length - 1,
            ),
        ]),
        if (past.isNotEmpty) ...[
          const SizedBox(height: 20),
          const BsheelLabel('Already ran'),
          const SizedBox(height: 8),
          _rowList([
            for (var i = 0; i < past.length; i++)
              _dayRow(
                day: _utcDay(past[i].displayDate),
                entry: past[i],
                last: i == past.length - 1,
                spent: true,
              ),
          ]),
        ],
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: BsheelButton.primary(
            label: 'Schedule a day',
            icon: Icons.event_available_rounded,
            onPressed: _busy ? null : () => _openEditor(),
          ),
        ),
      ],
    );
  }

  /// Today's live entry — gold, because the ticket is the one thing on
  /// this page a person is waiting on.
  Widget _hero(_QotdEntry entry, DateTime today) {
    const ground = BsheelColors.accent;
    final fg = BsheelColors.onAccent(ground);
    final stats = <String>[
      if (entry.questCategory.isNotEmpty) entry.questCategory.toUpperCase(),
      if (entry.questDifficulty.isNotEmpty)
        entry.questDifficulty.toUpperCase(),
      '+${entry.questXp} XP',
      if (entry.bonusXp > 0) 'BONUS +${entry.bonusXp} XP',
      if (entry.ticketNo != null && entry.ticketNo!.isNotEmpty)
        '№${entry.ticketNo}',
    ];

    return BsheelCard(
      color: ground,
      radius: BsheelRadii.lg,
      depth: 4,
      padding: const EdgeInsets.all(16),
      onTap: _busy ? null : () => _openEditor(existing: entry),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BsheelLabel('Today · ${_dayMonth(today)} · Live', color: fg),
          const SizedBox(height: 9),
          Text(entry.questTitle, style: BsheelType.displaySm.copyWith(color: fg)),
          const SizedBox(height: 9),
          Wrap(
            spacing: 16,
            runSpacing: 5,
            children: [
              for (final stat in stats)
                Text(
                  stat,
                  style: BsheelType.labelMd.copyWith(
                    color: fg,
                    letterSpacing: 0.6,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 13),
          BsheelButton(
            label: 'Pull from rotation',
            small: true,
            background: BsheelColors.bg,
            onPressed: _busy ? null : () => _delete(entry.id),
          ),
        ],
      ),
    );
  }

  Widget _rowList(List<Widget> rows) => BsheelCard.flat(
        padding: EdgeInsets.zero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BsheelRadii.card),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
      );

  /// One day in the schedule. An unscheduled day is drawn on cream with
  /// its date and its consequence in red — the ticket silently not
  /// rendering is the failure this screen has to make visible.
  Widget _dayRow({
    required DateTime day,
    required _QotdEntry? entry,
    required bool last,
    bool spent = false,
  }) {
    final missing = entry == null;
    final dateColor = missing
        ? BsheelColors.dangerText
        : (spent ? BsheelColors.inkMuted : null);

    return BsheelPressable(
      depth: 0,
      onTap: _busy
          ? null
          : () => missing
              ? _openEditor(forDay: day)
              : _openEditor(existing: entry),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: missing || spent ? BsheelColors.surface : BsheelColors.card,
          border: last ? null : const Border(bottom: BsheelBorders.rowSide),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 76,
              child: BsheelCell.meta(_dayMonth(day), color: dateColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: missing
                  ? Text(
                      'Nothing scheduled — the QOTD ticket will not render '
                      'that day',
                      style: BsheelType.bodySmMedium.copyWith(
                        color: BsheelColors.dangerText,
                      ),
                    )
                  : BsheelCell.title(entry.questTitle, muted: spent),
            ),
            if (!missing) ...[
              const SizedBox(width: 10),
              SizedBox(
                width: 76,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: BsheelCell.meta(
                    '+${entry.questXp + entry.bonusXp} XP',
                    color: spent ? BsheelColors.inkMuted : BsheelColors.ink,
                  ),
                ),
              ),
            ],
          ],
        ),
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
}

class _QotdEditorDialog extends StatefulWidget {
  const _QotdEditorDialog({
    required this.existing,
    required this.quests,
    required this.onSave,
    this.initialDate,
    this.onDelete,
  });

  final _QotdEntry? existing;

  /// Pre-selected day, used when an admin taps an unscheduled row.
  final DateTime? initialDate;
  final List<_QuestRow> quests;
  final Future<void> Function()? onDelete;
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
    // Always a UTC midnight, whichever branch it comes from.
    _date = existing != null
        ? _utcDay(existing.displayDate)
        : (widget.initialDate == null
            ? _utcToday()
            : _utcDay(widget.initialDate!));
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
      setState(
          () => _date = DateTime.utc(picked.year, picked.month, picked.day));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BsheelDialog(
      title: widget.existing == null ? 'Schedule a day' : 'Edit QOTD',
      maxWidth: 560,
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const BsheelLabel('Display date'),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: BsheelButton.ghost(
                    label: _isoDay(_date),
                    icon: Icons.calendar_today,
                    small: true,
                    onPressed: _saving ? null : _pickDate,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'The home page matches this date in UTC. Saving a date that '
                  'already has an entry overwrites that day.',
                  style: BsheelType.bodyXs,
                ),
                const SizedBox(height: 14),
                BsheelDropdown<String?>(
                  value: _questId,
                  label: 'Quest',
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Select a quest…'),
                    ),
                    for (final q in widget.quests)
                      DropdownMenuItem<String?>(
                        value: q.id,
                        child: Text(
                          '${q.title} · ${q.category} · +${q.xpReward} XP',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _questId = v),
                ),
                const SizedBox(height: 5),
                const Text('Pick from active quests.', style: BsheelType.bodyXs),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: BsheelField(
                        controller: _ticketCtrl,
                        label: 'Ticket №',
                        hint: 'Defaults to MMDD',
                        enabled: !_saving,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: BsheelField(
                        controller: _bonusCtrl,
                        label: 'Bonus XP',
                        hint: 'Above base reward',
                        keyboardType: TextInputType.number,
                        enabled: !_saving,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                BsheelField(
                  controller: _noteCtrl,
                  label: 'Admin note',
                  hint: 'Not shown to users',
                  maxLines: 2,
                  enabled: !_saving,
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.onDelete != null)
          BsheelButton.coral(
            label: 'Unschedule',
            small: true,
            onPressed: _saving
                ? null
                : () async {
                    final onDelete = widget.onDelete!;
                    Navigator.pop(context);
                    await onDelete();
                  },
          ),
        BsheelButton.ghost(
          label: 'Cancel',
          small: true,
          onPressed: _saving ? null : () => Navigator.pop(context),
        ),
        BsheelButton.primary(
          label: widget.existing == null ? 'Schedule' : 'Save',
          small: true,
          loading: _saving,
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
        ),
      ],
    );
  }
}
