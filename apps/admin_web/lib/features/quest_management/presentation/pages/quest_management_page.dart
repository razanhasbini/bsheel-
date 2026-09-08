import 'package:app_core/app_core.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_contracts/app_contracts.dart';

import '../../../../core/providers/admin_role_provider.dart';
import '../../../../core/backend/app_backend.dart';

import '../../../../core/theme/bsheel_design.dart';
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

class QuestManagementPage extends ConsumerStatefulWidget {
  const QuestManagementPage({super.key});

  @override
  ConsumerState<QuestManagementPage> createState() =>
      _QuestManagementPageState();
}

class _QuestManagementPageState extends ConsumerState<QuestManagementPage> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final questsAsync = ref.watch(_questsProvider);
    final isSuperAdmin = ref.watch(isSuperAdminProvider).valueOrNull ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelCard(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const BsheelEyebrow('Content · Quests'),
                    const SizedBox(height: 14),
                    BsheelDisplay(
                      'The {quest bank.}',
                      baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Browse, write and retire every quest in the catalog.',
                      style: BsheelType.bodyMd
                          .copyWith(color: BsheelColors.inkSoft),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (isSuperAdmin) ...[
                    BsheelButton.ghost(
                      label: 'IMPORT',
                      icon: Icons.upload_file_rounded,
                      small: true,
                      onPressed: () => _showImportDialog(context),
                    ),
                    BsheelButton.coral(
                      label: 'DELETE ALL',
                      icon: Icons.delete_forever_rounded,
                      small: true,
                      onPressed: () => _confirmDeleteAll(context),
                    ),
                  ],
                  BsheelButton.primary(
                    label: 'NEW QUEST',
                    icon: Icons.add_rounded,
                    small: true,
                    onPressed: () => _showQuestDialog(context),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: TextField(
            style: BsheelType.bodySm,
            decoration: InputDecoration(
              hintText: 'Search quests...',
              hintStyle: BsheelType.bodySm.copyWith(
                color: BsheelColors.inkMuted,
              ),
              prefixIcon:
                  const Icon(Icons.search, color: BsheelColors.inkMuted),
              filled: true,
              fillColor: BsheelColors.paper,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.md),
                borderSide: const BorderSide(color: BsheelColors.line),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.md),
                borderSide: const BorderSide(
                  color: BsheelColors.line,
                  width: BsheelBorders.thin,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.md),
                borderSide: const BorderSide(
                  color: BsheelColors.ink,
                  width: BsheelBorders.thin,
                ),
              ),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: questsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: BsheelColors.primary),
            ),
            error: (e, _) => Center(
              child: Text(
                'Error: $e',
                style: BsheelType.bodySm.copyWith(
                  color: BsheelColors.hot,
                ),
              ),
            ),
            data: (quests) {
              final filtered = quests.where((q) {
                if (_search.isEmpty) return true;
                final title =
                    (q[QuestColumns.title] ?? '').toString().toLowerCase();
                final desc = (q[QuestColumns.description] ?? '')
                    .toString()
                    .toLowerCase();
                return title.contains(_search) || desc.contains(_search);
              }).toList();

              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.assignment_outlined,
                        size: 64,
                        color: BsheelColors.inkMuted,
                      ),
                      const SizedBox(height: QuestSpacing.md),
                      Text(
                        'NO QUESTS FOUND',
                        style: BsheelType.labelMd.copyWith(
                          color: BsheelColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 600) {
                    return ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: QuestSpacing.sm),
                      itemBuilder: (context, i) =>
                          _buildMobileCard(context, filtered[i]),
                    );
                  }
                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: BsheelColors.paper,
                      border: Border.all(
                        color: BsheelColors.line,
                        width: BsheelBorders.thin,
                      ),
                      borderRadius: BorderRadius.circular(BsheelRadii.lg),
                    ),
                    child: SingleChildScrollView(
                      child: SizedBox(
                        width: double.infinity,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            BsheelColors.surface,
                          ),
                          columnSpacing: 24,
                          headingTextStyle: BsheelType.labelSm.copyWith(
                            color: BsheelColors.inkMuted,
                            letterSpacing: 1.5,
                          ),
                          dataTextStyle: BsheelType.bodySm.copyWith(
                            color: BsheelColors.ink,
                          ),
                          columns: const [
                            DataColumn(label: Text('TITLE')),
                            DataColumn(label: Text('CATEGORY')),
                            DataColumn(label: Text('DIFFICULTY')),
                            DataColumn(label: Text('XP'), numeric: true),
                            DataColumn(label: Text('DURATION')),
                            DataColumn(label: Text('ACTIVE')),
                            DataColumn(label: Text('CREATED')),
                            DataColumn(label: Text('ACTIONS')),
                          ],
                          rows: filtered
                              .asMap()
                              .entries
                              .map((e) => _buildRow(context, e.value, e.key))
                              .toList(),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMobileCard(BuildContext context, Map<String, dynamic> quest) {
    final id = quest[QuestColumns.id]?.toString() ?? '';
    final title = quest[QuestColumns.title]?.toString() ?? '-';
    final category = quest[QuestColumns.category]?.toString() ?? '-';
    final difficulty = quest[QuestColumns.difficulty]?.toString() ?? '-';
    final xp = quest[QuestColumns.xpReward] ?? 0;
    final durationHours = _toDurationHours(quest[QuestColumns.durationHours]);
    final isActive = quest[QuestColumns.isActive] == true;

    return Container(
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        border: Border.all(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: BsheelType.bodyMd.copyWith(
                    fontWeight: FontWeight.w500,
                    color: BsheelColors.ink,
                  ),
                ),
              ),
              Switch(
                value: isActive,
                activeThumbColor: BsheelColors.primary,
                inactiveThumbColor: BsheelColors.inkMuted,
                inactiveTrackColor: BsheelColors.surface,
                onChanged: (val) => _toggleActive(id, val),
              ),
            ],
          ),
          const SizedBox(height: QuestSpacing.xs),
          Wrap(
            spacing: QuestSpacing.sm,
            runSpacing: QuestSpacing.sm,
            children: [
              _CategoryChip(category: category),
              _DifficultyChip(difficulty: difficulty),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: QuestSpacing.sm,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: BsheelColors.surface,
                  borderRadius: BorderRadius.circular(BsheelRadii.full),
                  border: Border.all(color: BsheelColors.line),
                ),
                child: Text(
                  '$xp XP · ${durationHours}h',
                  style: BsheelType.labelSm.copyWith(
                    color: BsheelColors.accent,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: QuestSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  color: BsheelColors.cool,
                ),
                tooltip: 'Edit',
                onPressed: () => _showQuestDialog(context, quest: quest),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: BsheelColors.hot,
                ),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, id, title),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DataRow _buildRow(
    BuildContext context,
    Map<String, dynamic> quest,
    int index,
  ) {
    final id = quest[QuestColumns.id]?.toString() ?? '';
    final title = quest[QuestColumns.title]?.toString() ?? '-';
    final category = quest[QuestColumns.category]?.toString() ?? '-';
    final difficulty = quest[QuestColumns.difficulty]?.toString() ?? '-';
    final xp = quest[QuestColumns.xpReward] ?? 0;
    final durationHours = _toDurationHours(quest[QuestColumns.durationHours]);
    final isActive = quest[QuestColumns.isActive] == true;
    final createdAt = quest[QuestColumns.createdAt] != null
        ? DateTime.tryParse(quest[QuestColumns.createdAt].toString())
        : null;

    final rowColor = index.isEven ? BsheelColors.paper : BsheelColors.surface;

    return DataRow(
      color: WidgetStateProperty.all(rowColor),
      cells: [
        DataCell(
          Text(
            title,
            style: BsheelType.bodySm.copyWith(
              fontWeight: FontWeight.w500,
              color: BsheelColors.ink,
            ),
          ),
        ),
        DataCell(_CategoryChip(category: category)),
        DataCell(_DifficultyChip(difficulty: difficulty)),
        DataCell(
          Text(
            '$xp',
            style: BsheelType.labelSm.copyWith(
              color: BsheelColors.accent,
            ),
          ),
        ),
        DataCell(
          Text(
            '${durationHours}h',
            style: BsheelType.bodySm.copyWith(color: BsheelColors.ink),
          ),
        ),
        DataCell(
          Switch(
            value: isActive,
            activeThumbColor: BsheelColors.primary,
            inactiveThumbColor: BsheelColors.inkMuted,
            inactiveTrackColor: BsheelColors.ink,
            onChanged: (val) => _toggleActive(id, val),
          ),
        ),
        DataCell(
          Text(
            createdAt != null
                ? '${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}'
                : '-',
            style: BsheelType.labelSm.copyWith(
              color: BsheelColors.inkMuted,
            ),
          ),
        ),
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(
                  Icons.edit_outlined,
                  color: BsheelColors.cool,
                ),
                tooltip: 'Edit',
                onPressed: () => _showQuestDialog(context, quest: quest),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: BsheelColors.hot,
                ),
                tooltip: 'Delete',
                onPressed: () => _confirmDelete(context, id, title),
              ),
            ],
          ),
        ),
      ],
    );
  }

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
        title: 'DELETE QUEST',
        content: Text(
          'Delete "$title"? This cannot be undone.',
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'CANCEL',
              style: BsheelType.labelSm.copyWith(
                color: BsheelColors.inkMuted,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.hot,
              foregroundColor: BsheelColors.pureWhite,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.full),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteQuest(id);
            },
            child: Text(
              'DELETE',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.pureWhite),
            ),
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

  void _showQuestDialog(BuildContext context, {Map<String, dynamic>? quest}) {
    final isEdit = quest != null;
    final titleCtrl =
        TextEditingController(text: quest?[QuestColumns.title]?.toString());
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
    bool isActive = quest?[QuestColumns.isActive] ?? true;

    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: BsheelColors.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BsheelRadii.xl),
            side: const BorderSide(
              color: BsheelColors.line,
              width: BsheelBorders.thin,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(QuestSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEdit ? 'EDIT QUEST' : 'NEW QUEST',
                  style: BsheelType.displaySm.copyWith(
                    color: BsheelColors.ink,
                  ),
                ),
                const SizedBox(height: QuestSpacing.md),
                SizedBox(
                  width: 460,
                  child: Form(
                    key: formKey,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          BsheelFormField(
                            controller: titleCtrl,
                            label: 'TITLE',
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: QuestSpacing.md),
                          BsheelFormField(
                            controller: descCtrl,
                            label: 'DESCRIPTION',
                            maxLines: 3,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: QuestSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: BsheelDropdown<String>(
                                  value: category,
                                  label: 'CATEGORY',
                                  items: const [
                                    DropdownMenuItem(
                                      value: QuestCategory.fitness,
                                      child: Text('Fitness'),
                                    ),
                                    DropdownMenuItem(
                                      value: QuestCategory.creativity,
                                      child: Text('Creativity'),
                                    ),
                                    DropdownMenuItem(
                                      value: QuestCategory.social,
                                      child: Text('Social'),
                                    ),
                                    DropdownMenuItem(
                                      value: QuestCategory.learning,
                                      child: Text('Learning'),
                                    ),
                                    DropdownMenuItem(
                                      value: QuestCategory.adventure,
                                      child: Text('Adventure'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setDialogState(() => category = v!),
                                ),
                              ),
                              const SizedBox(width: QuestSpacing.md),
                              Expanded(
                                child: BsheelDropdown<String>(
                                  value: difficulty,
                                  label: 'DIFFICULTY',
                                  items: const [
                                    DropdownMenuItem(
                                      value: QuestDifficulty.easy,
                                      child: Text('Easy'),
                                    ),
                                    DropdownMenuItem(
                                      value: QuestDifficulty.medium,
                                      child: Text('Medium'),
                                    ),
                                    DropdownMenuItem(
                                      value: QuestDifficulty.hard,
                                      child: Text('Hard'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setDialogState(() => difficulty = v!),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: QuestSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: BsheelFormField(
                                  controller: xpCtrl,
                                  label: 'XP REWARD',
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
                              const SizedBox(width: QuestSpacing.md),
                              Expanded(
                                child: BsheelFormField(
                                  controller: durationCtrl,
                                  label: 'DURATION (HOURS)',
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
                          const SizedBox(height: QuestSpacing.md),
                          Row(
                            children: [
                              Text(
                                'ACTIVE',
                                style: BsheelType.labelSm.copyWith(
                                  color: BsheelColors.inkMuted,
                                ),
                              ),
                              Switch(
                                value: isActive,
                                activeThumbColor: BsheelColors.primary,
                                inactiveThumbColor: BsheelColors.inkMuted,
                                inactiveTrackColor: BsheelColors.surface,
                                onChanged: (v) =>
                                    setDialogState(() => isActive = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: QuestSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(
                        'CANCEL',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.inkMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: QuestSpacing.sm),
                    ElevatedButton(
                      onPressed: () async {
                        if (!formKey.currentState!.validate()) return;
                        Navigator.pop(ctx);
                        await _saveQuest(
                          id: quest?[QuestColumns.id]?.toString(),
                          title: titleCtrl.text.trim(),
                          description: descCtrl.text.trim(),
                          category: category,
                          difficulty: difficulty,
                          xpReward: int.parse(xpCtrl.text.trim()),
                          durationHours: int.parse(durationCtrl.text.trim()),
                          isActive: isActive,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BsheelColors.primary,
                        foregroundColor: BsheelColors.pureWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(BsheelRadii.full),
                        ),
                      ),
                      child: Text(
                        isEdit ? 'SAVE' : 'CREATE',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.pureWhite,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
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
      'adventure',
      'easy',
      '20',
      '4',
      'true',
    ],
    [
      'Sketch something',
      'Draw a small sketch of anything nearby.',
      'creativity',
      'medium',
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
        builder: (ctx, setDialogState) => Dialog(
          backgroundColor: BsheelColors.paper,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(BsheelRadii.xl),
            side: const BorderSide(
              color: BsheelColors.line,
              width: BsheelBorders.thin,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(QuestSpacing.lg),
            child: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IMPORT QUESTS (EXCEL)',
                      style: BsheelType.displaySm
                          .copyWith(color: BsheelColors.ink),
                    ),
                    const SizedBox(height: QuestSpacing.sm),
                    Text(
                      'Upload a .xlsx file. Row 1 must be the header row with '
                      'these exact column names, in this order:',
                      style: BsheelType.bodySm
                          .copyWith(color: BsheelColors.inkMuted),
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    _buildExampleTable(),
                    const SizedBox(height: QuestSpacing.sm),
                    Text(
                      'Rules: title 3-100, description 10-500, xp_reward 5-100, '
                      'duration_hours 1-168. category ∈ {fitness, creativity, '
                      'social, learning, adventure}. difficulty ∈ {easy, medium, '
                      'hard}. is_active is "true" / "false" (defaults to true).',
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.inkMuted,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(
                            Icons.description_outlined,
                            size: 16,
                            color: BsheelColors.primary,
                          ),
                          label: Text(
                            'COPY HEADER ROW',
                            style: BsheelType.labelSm
                                .copyWith(color: BsheelColors.primary),
                          ),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: _importHeaders.join('\t'),
                              ),
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
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: BsheelColors.ink,
                              width: BsheelBorders.thin,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                BsheelRadii.full,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(QuestSpacing.md),
                      decoration: BoxDecoration(
                        color: BsheelColors.surface,
                        border: Border.all(
                          color: BsheelColors.line,
                          width: BsheelBorders.thin,
                        ),
                        borderRadius: BorderRadius.circular(BsheelRadii.md),
                      ),
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
                          ElevatedButton.icon(
                            icon: const Icon(Icons.folder_open, size: 16),
                            label: Text(
                              'CHOOSE FILE',
                              style: BsheelType.labelSm
                                  .copyWith(color: BsheelColors.pureWhite),
                            ),
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
                            style: ElevatedButton.styleFrom(
                              backgroundColor: BsheelColors.primary,
                              foregroundColor: BsheelColors.pureWhite,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  BsheelRadii.full,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: QuestSpacing.sm),
                      Text(
                        error!,
                        style:
                            BsheelType.bodySm.copyWith(color: BsheelColors.hot),
                      ),
                    ],
                    const SizedBox(height: QuestSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              importing ? null : () => Navigator.pop(ctx),
                          child: Text(
                            'CANCEL',
                            style: BsheelType.labelSm
                                .copyWith(color: BsheelColors.inkMuted),
                          ),
                        ),
                        const SizedBox(width: QuestSpacing.sm),
                        ElevatedButton(
                          onPressed: (importing || picked == null)
                              ? null
                              : () async {
                                  setDialogState(() {
                                    error = null;
                                    importing = true;
                                  });
                                  final result = await _importQuestsFromXlsx(
                                    picked!.bytes,
                                  );
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
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BsheelColors.primary,
                            foregroundColor: BsheelColors.pureWhite,
                            disabledBackgroundColor:
                                BsheelColors.primary.withAlpha(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                BsheelRadii.full,
                              ),
                            ),
                          ),
                          child: importing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: BsheelColors.pureWhite,
                                  ),
                                )
                              : Text(
                                  'IMPORT',
                                  style: BsheelType.labelSm
                                      .copyWith(color: BsheelColors.pureWhite),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExampleTable() {
    final allRows = [_importHeaders, ..._importExampleRows];
    return Container(
      decoration: BoxDecoration(
        color: BsheelColors.bg,
        border: Border.all(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
        borderRadius: BorderRadius.circular(BsheelRadii.md),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            BsheelColors.surface,
          ),
          dataRowMaxHeight: 36,
          dataRowMinHeight: 30,
          headingRowHeight: 32,
          columnSpacing: QuestSpacing.lg,
          columns: _importHeaders
              .map(
                (h) => DataColumn(
                  label: Text(
                    h,
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.ink,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              )
              .toList(),
          rows: allRows
              .skip(1)
              .map(
                (row) => DataRow(
                  cells: row
                      .map(
                        (c) => DataCell(
                          Text(
                            c,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: BsheelColors.ink,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              )
              .toList(),
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
          return Dialog(
            backgroundColor: BsheelColors.paper,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.xl),
              side: const BorderSide(
                color: BsheelColors.hot,
                width: BsheelBorders.thin,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(QuestSpacing.lg),
              child: SizedBox(
                width: 460,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: BsheelColors.hot,
                          size: 24,
                        ),
                        const SizedBox(width: QuestSpacing.sm),
                        Text(
                          'DELETE ALL QUESTS',
                          style: BsheelType.displaySm.copyWith(
                            color: BsheelColors.hot,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    Text(
                      'This will permanently delete every quest. Active user_quests and submissions will cascade per your FK policies. There is no undo.',
                      style: BsheelType.bodySm
                          .copyWith(color: BsheelColors.ink, height: 1.4),
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    Text(
                      'Type  DELETE ALL  to confirm:',
                      style: BsheelType.labelSm
                          .copyWith(color: BsheelColors.inkMuted),
                    ),
                    const SizedBox(height: QuestSpacing.xs),
                    TextField(
                      controller: confirmCtrl,
                      style: BsheelType.bodyMd,
                      autofocus: true,
                      onChanged: (_) => setDialogState(() {}),
                      decoration: InputDecoration(
                        hintText: 'DELETE ALL',
                        hintStyle: BsheelType.bodySm
                            .copyWith(color: BsheelColors.inkMuted),
                        filled: true,
                        fillColor: BsheelColors.bg,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(BsheelRadii.md),
                          borderSide:
                              const BorderSide(color: BsheelColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(BsheelRadii.md),
                          borderSide: const BorderSide(
                            color: BsheelColors.line,
                            width: BsheelBorders.thin,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(BsheelRadii.md),
                          borderSide: const BorderSide(
                            color: BsheelColors.hot,
                            width: BsheelBorders.thin,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            'CANCEL',
                            style: BsheelType.labelSm
                                .copyWith(color: BsheelColors.inkMuted),
                          ),
                        ),
                        const SizedBox(width: QuestSpacing.sm),
                        ElevatedButton(
                          onPressed: enabled
                              ? () async {
                                  Navigator.pop(ctx);
                                  await _deleteAllQuests();
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: BsheelColors.hot,
                            foregroundColor: BsheelColors.pureWhite,
                            disabledBackgroundColor:
                                BsheelColors.hot.withAlpha(70),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                BsheelRadii.full,
                              ),
                            ),
                          ),
                          child: Text(
                            'DELETE ALL',
                            style: BsheelType.labelSm
                                .copyWith(color: BsheelColors.pureWhite),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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

// ── Chip widgets ─────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String category;
  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    // Monochrome type chip — the label carries the meaning.
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      child: Text(
        category.toUpperCase(),
        style:
            BsheelType.labelSm.copyWith(color: BsheelColors.ink, fontSize: 10),
      ),
    );
  }
}

class _DifficultyChip extends StatelessWidget {
  final String difficulty;
  const _DifficultyChip({required this.difficulty});

  @override
  Widget build(BuildContext context) {
    // Monochrome type chip — the label carries the meaning.
    final String label = switch (difficulty) {
      'easy' => 'EASY',
      'medium' => 'MEDIUM',
      'hard' => 'HARD',
      _ => difficulty.toUpperCase(),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(
          color: BsheelColors.line,
          width: BsheelBorders.thin,
        ),
      ),
      child: Text(
        label,
        style: BsheelType.labelSm
            .copyWith(color: BsheelColors.inkMuted, fontSize: 10),
      ),
    );
  }
}
