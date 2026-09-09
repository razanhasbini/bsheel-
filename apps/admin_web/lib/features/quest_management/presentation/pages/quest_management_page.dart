import 'package:app_contracts/app_contracts.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/providers/admin_role_provider.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Quest bank, newest first. Rows stay maps because the table, the edit
/// dialog and the CSV export all read them by column name.
final _questsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final quests = await AppBackend.repositories.quests.listAllQuestsAdmin();
  final rows = quests
      .map((quest) => <String, dynamic>{
            'id': quest.id,
            'title': quest.title,
            'description': quest.description,
            'category': quest.category,
            'difficulty': quest.difficulty,
            'xp_reward': quest.xpReward,
            'duration_hours': quest.durationHours,
            'is_active': quest.isActive,
            'created_by': quest.createdBy,
            'created_at': quest.createdAt.toIso8601String(),
            'updated_at': quest.updatedAt?.toIso8601String(),
          })
      .toList();
  rows.sort((a, b) =>
      (b['created_at'] as String).compareTo(a['created_at'] as String));
  return rows;
});

/// Every category the CHECK constraint allows, in the order the design
/// draws the filter row. The strings come from `app_contracts`, never
/// from a literal — the DB constraint and this list cannot drift.
const List<String> _questCategories = [
  QuestCategory.fitness,
  QuestCategory.creativity,
  QuestCategory.social,
  QuestCategory.learning,
  QuestCategory.adventure,
];

/// Every difficulty the CHECK constraint allows.
const List<String> _questDifficulties = [
  QuestDifficulty.easy,
  QuestDifficulty.medium,
  QuestDifficulty.hard,
];

/// `fitness` → `Fitness`, for dropdown items that read as words rather
/// than as DB values.
String _readable(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

class QuestManagementPage extends ConsumerStatefulWidget {
  const QuestManagementPage({super.key});

  @override
  ConsumerState<QuestManagementPage> createState() =>
      _QuestManagementPageState();
}

class _QuestManagementPageState extends ConsumerState<QuestManagementPage> {
  /// Filter keys that are not category values. Retirement is
  /// `is_active = false`, not a status string, so it has no contract.
  static const String _filterAll = 'all';
  static const String _filterRetired = 'retired';

  final TextEditingController _searchCtrl = TextEditingController();
  String _search = '';
  String _filter = _filterAll;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questsAsync = ref.watch(_questsProvider);
    final isSuperAdmin = ref.watch(isSuperAdminProvider).valueOrNull ?? false;

    return AdminPage(
      title: 'Quest bank',
      actions: [
        BsheelSearchField(
          controller: _searchCtrl,
          hint: 'Search quests…',
          width: 220,
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        ),
        // Bulk import and the bank-wide wipe stay super-admin only, and
        // stay in the header as icons so the row cannot overflow.
        if (isSuperAdmin) ...[
          BsheelIconButton(
            icon: Icons.upload_file_rounded,
            tooltip: 'Import quests from a spreadsheet',
            onTap: () => _showImportDialog(context),
          ),
          BsheelIconButton(
            icon: Icons.delete_forever_rounded,
            ground: BsheelColors.danger,
            tooltip: 'Delete every quest',
            onTap: () => _confirmDeleteAll(context),
          ),
        ],
        BsheelButton.primary(
          label: 'New quest',
          small: true,
          onPressed: () => _showQuestDialog(context),
        ),
      ],
      subheader: _filterRow(questsAsync.valueOrNull),
      child: questsAsync.when(
        loading: () => const BsheelLoadingList(rows: 6, rowHeight: 44),
        error: (e, _) => BsheelErrorState(
          message: 'The quest bank did not come back. Nothing was changed — '
              'no quest has been written, edited or retired. ($e)',
          onRetry: () => ref.invalidate(_questsProvider),
        ),
        data: (quests) => _bank(context, quests),
      ),
    );
  }

  // ── Filters ────────────────────────────────────────────────

  Widget _filterRow(List<Map<String, dynamic>>? quests) {
    int? countWhere(bool Function(Map<String, dynamic>) test) =>
        quests?.where(test).length;

    return BsheelFilterChips(
      selected: _filter,
      onChanged: (value) => setState(() => _filter = value),
      filters: [
        // ALL stays untinted — it is not a category.
        BsheelFilter(_filterAll, 'All', count: quests?.length),
        for (final category in _questCategories)
          BsheelFilter(
            category,
            category,
            count: countWhere(
              (q) => q[QuestColumns.category]?.toString() == category,
            ),
            ground: BsheelColors.category(category),
          ),
        BsheelFilter(
          _filterRetired,
          'Retired',
          count: countWhere((q) => q[QuestColumns.isActive] != true),
          dashed: true,
        ),
      ],
    );
  }

  bool _matches(Map<String, dynamic> quest) {
    if (_filter == _filterRetired) {
      if (quest[QuestColumns.isActive] == true) return false;
    } else if (_filter != _filterAll) {
      if (quest[QuestColumns.category]?.toString() != _filter) return false;
    }
    if (_search.isEmpty) return true;
    final title = (quest[QuestColumns.title] ?? '').toString().toLowerCase();
    final description =
        (quest[QuestColumns.description] ?? '').toString().toLowerCase();
    return title.contains(_search) || description.contains(_search);
  }

  // ── Table ──────────────────────────────────────────────────

  Widget _bank(BuildContext context, List<Map<String, dynamic>> quests) {
    final filtered = quests.where(_matches).toList();

    if (filtered.isEmpty) {
      final filtering = _search.isNotEmpty || _filter != _filterAll;
      return Padding(
        padding: const EdgeInsets.only(top: 36),
        child: filtering
            ? BsheelEmptyState(
                title: 'No matches',
                message: 'No quest matches that search or filter. Nothing has '
                    'been removed — clear the filter to see the whole bank.',
                actionLabel: 'Clear filters',
                onAction: () => setState(() {
                  _search = '';
                  _filter = _filterAll;
                  _searchCtrl.clear();
                }),
              )
            : BsheelEmptyState(
                title: 'The bank is empty',
                message: 'The generator has nothing to hand out until a quest '
                    'exists. Write the first one.',
                actionLabel: 'New quest',
                onAction: () => _showQuestDialog(context),
              ),
      );
    }

    // BsheelTable scrolls itself sideways once its six columns stop
    // fitting, so there is no wrapper here.
    return BsheelTable(
      depth: 5,
      columns: const [
        BsheelColumn('Title'),
        BsheelColumn('Category', width: 112),
        BsheelColumn('Difficulty', width: 92),
        BsheelColumn('Timer', width: 74),
        BsheelColumn('XP', width: 74),
        BsheelColumn('Status', width: 96),
      ],
      rows: [for (final quest in filtered) _tableRow(context, quest)],
    );
  }

  BsheelRow _tableRow(BuildContext context, Map<String, dynamic> quest) {
    final retired = quest[QuestColumns.isActive] != true;
    // A retired row greys wholesale, so every cell reads as inactive.
    final Color? dim = retired ? BsheelColors.inkMuted : null;

    return BsheelRow(
      [
        BsheelCell.title(
          quest[QuestColumns.title]?.toString() ?? '—',
          muted: retired,
        ),
        BsheelCell.label(
          quest[QuestColumns.category]?.toString() ?? '—',
          color: dim ?? BsheelColors.ink,
        ),
        BsheelCell.label(
          quest[QuestColumns.difficulty]?.toString() ?? '—',
          color: dim,
        ),
        BsheelCell.meta(
          '${_toDurationHours(quest[QuestColumns.durationHours])}h',
          color: dim,
        ),
        BsheelCell.mono('${quest[QuestColumns.xpReward] ?? 0}', color: dim),
        BsheelCell.pill(
          retired
              ? const BsheelPill.muted('retired', small: true)
              : const BsheelPill('live',
                  tone: BsheelPillTone.green, small: true),
        ),
      ],
      muted: retired,
      onTap: () => _showQuestDialog(context, quest: quest),
    );
  }

  // ── Retire / restore, delete ───────────────────────────────

  Future<void> _toggleActive(String id, bool active) async {
    try {
      final quest = await AppBackend.repositories.quests.getQuest(id);
      await AppBackend.repositories.quests
          .updateQuest(quest.copyWith(isActive: active));
      ref.invalidate(_questsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, String id, String title) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Delete quest',
        content: Text(
          'Delete "$title"? This cannot be undone. Retiring it instead keeps '
          'the history and stops it being handed out.',
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx),
          ),
          BsheelButton.coral(
            label: 'Delete',
            small: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteQuest(id);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteQuest(String id) async {
    try {
      await AppBackend.repositories.quests.deleteQuest(id);
      ref.invalidate(_questsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Quest deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  // ── Create / edit ──────────────────────────────────────────

  void _showQuestDialog(BuildContext context, {Map<String, dynamic>? quest}) {
    final isEdit = quest != null;
    final id = quest?[QuestColumns.id]?.toString();
    final storedTitle = quest?[QuestColumns.title]?.toString() ?? '';

    final titleCtrl = TextEditingController(text: storedTitle);
    final descCtrl = TextEditingController(
      text: quest?[QuestColumns.description]?.toString(),
    );
    final xpCtrl = TextEditingController(
      text: (quest?[QuestColumns.xpReward] ?? 50).toString(),
    );
    final durationCtrl = TextEditingController(
      text: _toDurationHours(quest?[QuestColumns.durationHours]).toString(),
    );

    String category =
        quest?[QuestColumns.category]?.toString() ?? QuestCategory.fitness;
    String difficulty =
        quest?[QuestColumns.difficulty]?.toString() ?? QuestDifficulty.easy;
    // A new quest goes live; an edit keeps whatever the row already is
    // and the footer's retire / restore is the one control that flips it.
    final bool isActive = quest?[QuestColumns.isActive] ?? true;

    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => BsheelDialog(
          title: isEdit ? 'Edit quest' : 'New quest',
          maxWidth: 540,
          content: SizedBox(
            width: 500,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 440),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BsheelField(
                        controller: titleCtrl,
                        label: 'Title',
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      BsheelField(
                        controller: descCtrl,
                        label: 'Description',
                        maxLines: 3,
                        validator: (v) =>
                            v == null || v.trim().isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: BsheelDropdown<String>(
                              value: category,
                              label: 'Category',
                              items: [
                                for (final value in _questCategories)
                                  DropdownMenuItem(
                                    value: value,
                                    child: Text(_readable(value)),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setDialogState(() => category = v!),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: BsheelDropdown<String>(
                              value: difficulty,
                              label: 'Difficulty',
                              items: [
                                for (final value in _questDifficulties)
                                  DropdownMenuItem(
                                    value: value,
                                    child: Text(_readable(value)),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setDialogState(() => difficulty = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: BsheelField(
                              controller: xpCtrl,
                              label: 'XP reward',
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                final n = int.tryParse(v.trim());
                                if (n == null || n < 0) {
                                  return 'Invalid number';
                                }
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: BsheelField(
                              controller: durationCtrl,
                              label: 'Timer (hours)',
                              keyboardType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) {
                                  return 'Required';
                                }
                                final n = int.tryParse(v.trim());
                                if (n == null || n < 1 || n > 168) {
                                  return 'Use 1-168';
                                }
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      if (isEdit && id != null) ...[
                        const SizedBox(height: 18),
                        Container(
                          height: BsheelBorders.hairline,
                          color: BsheelColors.rowLine,
                        ),
                        const SizedBox(height: 14),
                        const BsheelLabel('This quest'),
                        const SizedBox(height: 4),
                        Text(
                          isActive
                              ? 'Retiring keeps the quest and its history, and '
                                  'stops the generator handing it out.'
                              : 'This quest is retired. Restoring puts it back '
                                  'into rotation.',
                          style: BsheelType.bodyXs,
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 9,
                          runSpacing: 9,
                          children: [
                            BsheelButton.ghost(
                              label: isActive ? 'Retire quest' : 'Restore',
                              small: true,
                              onPressed: () {
                                Navigator.pop(ctx);
                                _toggleActive(id, !isActive);
                              },
                            ),
                            BsheelButton.coral(
                              label: 'Delete quest',
                              small: true,
                              onPressed: () {
                                Navigator.pop(ctx);
                                _confirmDelete(context, id, storedTitle);
                              },
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            BsheelButton.ghost(
              label: 'Cancel',
              small: true,
              onPressed: () => Navigator.pop(ctx),
            ),
            BsheelButton.primary(
              label: isEdit ? 'Save' : 'Create',
              small: true,
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                await _saveQuest(
                  id: id,
                  title: titleCtrl.text.trim(),
                  description: descCtrl.text.trim(),
                  category: category,
                  difficulty: difficulty,
                  xpReward: int.parse(xpCtrl.text.trim()),
                  durationHours: int.parse(durationCtrl.text.trim()),
                  isActive: isActive,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveQuest({
    String? id,
    required String title,
    required String description,
    required String category,
    required String difficulty,
    required int xpReward,
    required int durationHours,
    required bool isActive,
  }) async {
    try {
      final quests = AppBackend.repositories.quests;
      if (id != null) {
        final existing = await quests.getQuest(id);
        await quests.updateQuest(
          existing.copyWith(
            title: title,
            description: description,
            category: category,
            difficulty: difficulty,
            xpReward: xpReward,
            durationHours: durationHours,
            isActive: isActive,
          ),
        );
      } else {
        // The API records the creating admin from the access token.
        await quests.createQuest(
          title: title,
          description: description,
          category: category,
          difficulty: difficulty,
          xpReward: xpReward,
          durationHours: durationHours,
          isActive: isActive,
        );
      }
      ref.invalidate(_questsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(id != null ? 'Quest updated.' : 'Quest created.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  int _toDurationHours(dynamic value) {
    if (value is int && value > 0) return value;
    if (value is num && value.toInt() > 0) return value.toInt();
    final parsed = int.tryParse(value?.toString() ?? '');
    if (parsed == null || parsed < 1) return 4;
    return parsed;
  }

  // ── Import quests (Excel .xlsx) ────────────────────────────

  /// Columns expected in row 1 of the spreadsheet, in exact order.
  static const List<String> _importHeaders = [
    'title',
    'description',
    'category',
    'difficulty',
    'xp_reward',
    'duration_hours',
    'is_active',
  ];

  /// Example rows shown to admins. Each inner list is one spreadsheet row.
  static const List<List<String>> _importExampleRows = [
    [
      'Take a mindful walk',
      'Walk for 20 minutes, no phone, just observe.',
      QuestCategory.adventure,
      QuestDifficulty.easy,
      '20',
      '4',
      'true',
    ],
    [
      'Sketch something',
      'Draw a small sketch of anything nearby.',
      QuestCategory.creativity,
      QuestDifficulty.medium,
      '50',
      '6',
      'true',
    ],
  ];

  void _showImportDialog(BuildContext context) {
    _PickedFile? picked;
    bool importing = false;
    String? error;
    int? parsedCount;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => BsheelDialog(
          title: 'Import quests',
          maxWidth: 760,
          content: SizedBox(
            width: 720,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Upload a .xlsx file. Row 1 must be the header row with '
                      'these exact column names, in this order:',
                      style: BsheelType.bodySm
                          .copyWith(color: BsheelColors.inkSoft),
                    ),
                    const SizedBox(height: 12),
                    _importExample(),
                    const SizedBox(height: 10),
                    Text(
                      'Rules: title 3-100, description 10-500, xp_reward 5-100, '
                      'duration_hours 1-168. category ∈ '
                      '{${_questCategories.join(', ')}}. difficulty ∈ '
                      '{${_questDifficulties.join(', ')}}. is_active is '
                      '"true" / "false" (defaults to true).',
                      style: BsheelType.bodyXs,
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BsheelButton.ghost(
                        label: 'Copy header row',
                        icon: Icons.description_outlined,
                        small: true,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _importHeaders.join('\t')),
                          );
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Header row copied — paste into Excel row 1.',
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                    BsheelCard.flat(
                      color: BsheelColors.surface,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              picked == null
                                  ? 'No file selected.'
                                  : '${picked!.name} — $parsedCount quest(s) ready',
                              style: BsheelType.bodySm.copyWith(
                                color: picked == null
                                    ? BsheelColors.inkMuted
                                    : BsheelColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          BsheelButton(
                            label: 'Choose file',
                            icon: Icons.folder_open,
                            small: true,
                            background: BsheelColors.card,
                            onPressed: importing
                                ? null
                                : () async {
                                    final result =
                                        await FilePicker.platform.pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: const ['xlsx'],
                                      withData: true,
                                    );
                                    if (result == null ||
                                        result.files.isEmpty) {
                                      return;
                                    }
                                    final f = result.files.first;
                                    final bytes = f.bytes;
                                    if (bytes == null) {
                                      setDialogState(() {
                                        error = 'Could not read file bytes.';
                                        picked = null;
                                        parsedCount = null;
                                      });
                                      return;
                                    }
                                    try {
                                      final rowsCount = _countDataRows(bytes);
                                      setDialogState(() {
                                        picked = _PickedFile(
                                          name: f.name,
                                          bytes: bytes,
                                        );
                                        parsedCount = rowsCount;
                                        error = null;
                                      });
                                    } catch (e) {
                                      setDialogState(() {
                                        error = 'Invalid .xlsx: $e';
                                        picked = null;
                                        parsedCount = null;
                                      });
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      BsheelCallout.danger(error!),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            BsheelButton.ghost(
              label: 'Cancel',
              small: true,
              onPressed: importing ? null : () => Navigator.pop(ctx),
            ),
            BsheelButton.primary(
              label: 'Import',
              small: true,
              loading: importing,
              onPressed: (importing || picked == null)
                  ? null
                  : () async {
                      setDialogState(() {
                        error = null;
                        importing = true;
                      });
                      final result = await _importQuestsFromXlsx(picked!.bytes);
                      if (!ctx.mounted) return;
                      if (result.error != null) {
                        setDialogState(() {
                          error = result.error;
                          importing = false;
                        });
                        return;
                      }
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Imported ${result.inserted} quest(s).',
                          ),
                        ),
                      );
                    },
            ),
          ],
        ),
      ),
    );
  }

  /// The header row and two example rows, column-aligned in mono so the
  /// admin can read it as a spreadsheet. The header keeps its exact
  /// lower-case spelling — the parser matches it character for character.
  Widget _importExample() {
    final allRows = [_importHeaders, ..._importExampleRows];
    final widths = [
      for (var col = 0; col < _importHeaders.length; col++)
        allRows.map((r) => col < r.length ? r[col].length : 0).reduce(
              (a, b) => a > b ? a : b,
            ),
    ];
    String line(List<String> row) => [
          for (var col = 0; col < widths.length; col++)
            (col < row.length ? row[col] : '').padRight(widths[col]),
        ].join('  ');

    return BsheelCard.flat(
      color: BsheelColors.surface,
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < allRows.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == 0 ? 6 : 2),
                child: Text(
                  line(allRows[i]),
                  style: BsheelType.monoSm.copyWith(
                    color: i == 0 ? BsheelColors.ink : BsheelColors.inkSoft,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Parses the xlsx and returns the number of non-empty data rows.
  /// Throws if the header row is missing or columns don't match.
  int _countDataRows(List<int> bytes) {
    final book = xl.Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) {
      throw 'No sheets found.';
    }
    final sheet = book.tables[book.tables.keys.first]!;
    if (sheet.maxRows < 2) {
      throw 'Sheet must have a header row and at least one data row.';
    }
    final header = sheet.rows.first
        .map((c) => c?.value?.toString().trim().toLowerCase() ?? '')
        .toList();
    for (var i = 0; i < _importHeaders.length; i++) {
      if (i >= header.length || header[i] != _importHeaders[i]) {
        throw 'Header mismatch at column ${i + 1}: '
            'expected "${_importHeaders[i]}", got "${i < header.length ? header[i] : '(empty)'}".';
      }
    }
    var count = 0;
    for (var i = 1; i < sheet.rows.length; i++) {
      if (sheet.rows[i].any(
        (c) => (c?.value?.toString().trim().isNotEmpty ?? false),
      )) {
        count++;
      }
    }
    return count;
  }

  Future<_ImportResult> _importQuestsFromXlsx(List<int> bytes) async {
    const validCategories = {
      QuestCategory.fitness,
      QuestCategory.creativity,
      QuestCategory.social,
      QuestCategory.learning,
      QuestCategory.adventure,
    };
    const validDifficulties = {
      QuestDifficulty.easy,
      QuestDifficulty.medium,
      QuestDifficulty.hard,
    };

    xl.Excel book;
    try {
      book = xl.Excel.decodeBytes(bytes);
    } catch (e) {
      return _ImportResult(error: 'Invalid .xlsx: $e');
    }
    if (book.tables.isEmpty) {
      return _ImportResult(error: 'No sheets found.');
    }
    final sheet = book.tables[book.tables.keys.first]!;
    if (sheet.rows.length < 2) {
      return _ImportResult(error: 'Sheet must have at least one data row.');
    }

    String cell(List<xl.Data?> row, int idx) =>
        idx < row.length ? (row[idx]?.value?.toString().trim() ?? '') : '';

    final rows = <Map<String, dynamic>>[];
    for (var i = 1; i < sheet.rows.length; i++) {
      final r = sheet.rows[i];
      final isEmpty = r.every(
        (c) => (c?.value?.toString().trim().isEmpty ?? true),
      );
      if (isEmpty) continue;

      final displayRow = i + 1; // 1-indexed row number for error messages
      final title = cell(r, 0);
      final desc = cell(r, 1);
      final category = cell(r, 2).toLowerCase();
      final difficulty = cell(r, 3).toLowerCase();
      final xpStr = cell(r, 4);
      final durationStr = cell(r, 5);
      final isActiveStr = cell(r, 6).toLowerCase();

      if (title.length < 3 || title.length > 100) {
        return _ImportResult(
          error: 'Row $displayRow: title must be 3-100 chars.',
        );
      }
      if (desc.length < 10 || desc.length > 500) {
        return _ImportResult(
          error: 'Row $displayRow: description must be 10-500 chars.',
        );
      }
      if (!validCategories.contains(category)) {
        return _ImportResult(
          error: 'Row $displayRow: invalid category "$category".',
        );
      }
      if (!validDifficulties.contains(difficulty)) {
        return _ImportResult(
          error: 'Row $displayRow: invalid difficulty "$difficulty".',
        );
      }
      final xp = int.tryParse(xpStr);
      if (xp == null || xp < 5 || xp > 100) {
        return _ImportResult(
          error: 'Row $displayRow: xp_reward must be 5-100.',
        );
      }
      final duration = int.tryParse(durationStr.isEmpty ? '4' : durationStr);
      if (duration == null || duration < 1 || duration > 168) {
        return _ImportResult(
          error: 'Row $displayRow: duration_hours must be 1-168.',
        );
      }
      final isActive = isActiveStr.isEmpty
          ? true
          : (isActiveStr == 'true' ||
              isActiveStr == '1' ||
              isActiveStr == 'yes');

      rows.add({
        'title': title,
        'description': desc,
        'category': category,
        'difficulty': difficulty,
        'xpReward': xp,
        'durationHours': duration,
        'isActive': isActive,
      });
    }

    if (rows.isEmpty) {
      return _ImportResult(error: 'No data rows to import.');
    }

    try {
      final created =
          await AppBackend.repositories.quests.createQuestsBulk(rows);
      ref.invalidate(_questsProvider);
      return _ImportResult(inserted: created.length);
    } catch (e) {
      return _ImportResult(error: 'Insert failed: $e');
    }
  }

  // ── Delete all quests ──────────────────────────────────────

  Future<void> _confirmDeleteAll(BuildContext context) async {
    final confirmCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final enabled = confirmCtrl.text.trim() == 'DELETE ALL';
          return BsheelDialog(
            title: 'Delete all quests',
            content: SizedBox(
              width: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const BsheelCallout.danger(
                    'This will permanently delete every quest. Active '
                    'user_quests and submissions will cascade per your FK '
                    'policies. There is no undo.',
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Type  DELETE ALL  to confirm:',
                    style: BsheelType.bodySm.copyWith(
                      color: BsheelColors.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 8),
                  BsheelField(
                    controller: confirmCtrl,
                    hint: 'DELETE ALL',
                    onChanged: (_) => setDialogState(() {}),
                  ),
                ],
              ),
            ),
            actions: [
              BsheelButton.ghost(
                label: 'Cancel',
                small: true,
                onPressed: () => Navigator.pop(ctx),
              ),
              BsheelButton.coral(
                label: 'Delete all',
                small: true,
                onPressed: enabled
                    ? () async {
                        Navigator.pop(ctx);
                        await _deleteAllQuests();
                      }
                    : null,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteAllQuests() async {
    try {
      await AppBackend.repositories.quests.deleteAllQuests();
      ref.invalidate(_questsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All quests deleted.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }
}

class _ImportResult {
  final int inserted;
  final String? error;
  _ImportResult({this.inserted = 0, this.error});
}

class _PickedFile {
  final String name;
  final List<int> bytes;
  const _PickedFile({required this.name, required this.bytes});
}
