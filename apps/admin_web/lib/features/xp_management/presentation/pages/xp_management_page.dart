import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';
// ── Providers ────────────────────────────────────────────────────────────────

/// One aggregate query returns stored totals beside expected totals for
/// every profile — the page previously fetched every profile and every
/// approved user_quest and reconciled them in the browser.
final _xpAuditProvider =
    FutureProvider.autoDispose<List<_UserXpAudit>>((ref) async {
  final rows = await AppBackend.repositories.admin.xpAudit();
  int value(Map<String, dynamic> row, String key) =>
      (row[key] as num?)?.toInt() ?? 0;
  return rows
      .map((row) => _UserXpAudit(
            userId: row['user_id']?.toString() ?? '',
            username: row['username']?.toString() ?? '',
            displayName: row['display_name']?.toString() ?? '',
            currentXp: value(row, 'current_xp'),
            currentLevel: value(row, 'current_level'),
            currentQuests: value(row, 'current_quests'),
            expectedXp: value(row, 'expected_xp'),
            expectedLevel: value(row, 'expected_level'),
            expectedQuests: value(row, 'expected_quests'),
          ))
      .toList();
});

class _UserXpAudit {
  final String userId;
  final String username;
  final String displayName;
  final int currentXp;
  final int currentLevel;
  final int currentQuests;
  final int expectedXp;
  final int expectedLevel;
  final int expectedQuests;

  const _UserXpAudit({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.currentXp,
    required this.currentLevel,
    required this.currentQuests,
    required this.expectedXp,
    required this.expectedLevel,
    required this.expectedQuests,
  });

  bool get isConsistent =>
      currentXp == expectedXp &&
      currentLevel == expectedLevel &&
      currentQuests == expectedQuests;
}

// ── Page ─────────────────────────────────────────────────────────────────────

class XpManagementPage extends ConsumerWidget {
  const XpManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(_xpAuditProvider);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BsheelCard(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelEyebrow('Community · XP Manager'),
                const SizedBox(height: 14),
                BsheelDisplay(
                  'Mind the {ledger.}',
                  baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
                ),
                const SizedBox(height: 12),
                Text(
                  'Audit XP values against approved quests. Reconcile any '
                  'inconsistencies before they show up on the leaderboard.',
                  style:
                      BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Formula info card
          Container(
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
                Text(
                  'XP SYSTEM RULES',
                  style: BsheelType.labelSm.copyWith(
                    color: BsheelColors.ink,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: QuestSpacing.sm),
                Text(
                  'Level Formula: level = floor(XP / 100) + 1',
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
                Text(
                  '100 XP = Level 2, 200 XP = Level 3, etc.',
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
                Text(
                  'XP Source: Only from approved quest submissions',
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
                Text(
                  'DB Trigger: handle_submission_approved() awards XP atomically',
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: QuestSpacing.lg),

          // Audit table
          auditAsync.when(
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
            data: (users) {
              final inconsistent = users.where((u) => !u.isConsistent).toList();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (inconsistent.isNotEmpty) ...[
                    _SectionHeader(
                      title: 'INCONSISTENCIES FOUND (${inconsistent.length})',
                      color: BsheelColors.hot,
                    ),
                    const SizedBox(height: QuestSpacing.sm),
                    ElevatedButton.icon(
                      onPressed: () => _fixAll(ref, inconsistent),
                      icon: const Icon(Icons.auto_fix_high, size: 16),
                      label: Text(
                        'FIX ALL',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.pureWhite,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: BsheelColors.hot,
                        foregroundColor: BsheelColors.pureWhite,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(BsheelRadii.full),
                        ),
                      ),
                    ),
                    const SizedBox(height: QuestSpacing.md),
                    ...inconsistent.map(
                      (u) => _AuditCard(
                        user: u,
                        onFix: () => _fixUser(ref, u),
                      ),
                    ),
                    const SizedBox(height: QuestSpacing.lg),
                  ],
                  _SectionHeader(
                    title: 'ALL USERS (${users.length})',
                    color: BsheelColors.cool,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 600) {
                        return Column(
                          children: users.map((u) {
                            return Container(
                              margin: const EdgeInsets.only(
                                bottom: QuestSpacing.sm,
                              ),
                              padding: const EdgeInsets.all(QuestSpacing.md),
                              decoration: BoxDecoration(
                                color: BsheelColors.paper,
                                border: Border.all(
                                  color: u.isConsistent
                                      ? BsheelColors.line
                                      : BsheelColors.hot.withAlpha(80),
                                  width: BsheelBorders.thin,
                                ),
                                borderRadius: BorderRadius.circular(
                                  BsheelRadii.lg,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '@${u.username}',
                                          style: BsheelType.bodySm.copyWith(
                                            color: BsheelColors.ink,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                      u.isConsistent
                                          ? const Icon(
                                              Icons.check_circle,
                                              color: BsheelColors.success,
                                              size: 16,
                                            )
                                          : const Icon(
                                              Icons.warning,
                                              color: BsheelColors.hot,
                                              size: 16,
                                            ),
                                    ],
                                  ),
                                  const SizedBox(height: QuestSpacing.xs),
                                  Text(
                                    'XP: ${u.currentXp} (exp ${u.expectedXp})  '
                                    'LV: ${u.currentLevel} (exp ${u.expectedLevel})  '
                                    'Q: ${u.currentQuests} (exp ${u.expectedQuests})',
                                    style: BsheelType.labelSm.copyWith(
                                      color: u.isConsistent
                                          ? BsheelColors.inkMuted
                                          : BsheelColors.hot,
                                      fontSize: 10,
                                    ),
                                  ),
                                  if (!u.isConsistent) ...[
                                    const SizedBox(height: QuestSpacing.xs),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: () => _fixUser(ref, u),
                                        child: Text(
                                          'FIX',
                                          style: BsheelType.labelSm.copyWith(
                                            color: BsheelColors.primary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      }
                      return Container(
                        decoration: BoxDecoration(
                          color: BsheelColors.paper,
                          border: Border.all(
                            color: BsheelColors.line,
                            width: BsheelBorders.thin,
                          ),
                          borderRadius: BorderRadius.circular(BsheelRadii.lg),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowColor: WidgetStateProperty.all(
                              BsheelColors.surface,
                            ),
                            columnSpacing: 20,
                            headingTextStyle: BsheelType.labelSm.copyWith(
                              color: BsheelColors.inkMuted,
                              letterSpacing: 1.5,
                            ),
                            dataTextStyle: BsheelType.bodySm.copyWith(
                              color: BsheelColors.ink,
                            ),
                            columns: const [
                              DataColumn(label: Text('USER')),
                              DataColumn(label: Text('XP'), numeric: true),
                              DataColumn(
                                  label: Text('EXPECTED'), numeric: true),
                              DataColumn(label: Text('LEVEL'), numeric: true),
                              DataColumn(label: Text('EXP LVL'), numeric: true),
                              DataColumn(label: Text('QUESTS'), numeric: true),
                              DataColumn(label: Text('EXP QST'), numeric: true),
                              DataColumn(label: Text('STATUS')),
                              DataColumn(label: Text('ACTIONS')),
                            ],
                            rows: users
                                .asMap()
                                .entries
                                .map(
                                  (e) => DataRow(
                                    color: WidgetStateProperty.all(
                                      e.key.isEven
                                          ? BsheelColors.paper
                                          : BsheelColors.surface,
                                    ),
                                    cells: [
                                      DataCell(
                                        Text(
                                          '@${e.value.username}',
                                          style: BsheelType.bodySm.copyWith(
                                              color: BsheelColors.ink),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${e.value.currentXp}',
                                          style: BsheelType.labelSm.copyWith(
                                            color: e.value.currentXp !=
                                                    e.value.expectedXp
                                                ? BsheelColors.hot
                                                : BsheelColors.accent,
                                            fontWeight: e.value.currentXp !=
                                                    e.value.expectedXp
                                                ? FontWeight.w500
                                                : null,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${e.value.expectedXp}',
                                          style: BsheelType.bodySm.copyWith(
                                            color: BsheelColors.inkMuted,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${e.value.currentLevel}',
                                          style: BsheelType.labelSm.copyWith(
                                            color: e.value.currentLevel !=
                                                    e.value.expectedLevel
                                                ? BsheelColors.hot
                                                : BsheelColors.primary,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${e.value.expectedLevel}',
                                          style: BsheelType.bodySm.copyWith(
                                            color: BsheelColors.inkMuted,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${e.value.currentQuests}',
                                          style: BsheelType.labelSm.copyWith(
                                            color: e.value.currentQuests !=
                                                    e.value.expectedQuests
                                                ? BsheelColors.hot
                                                : BsheelColors.ink,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        Text(
                                          '${e.value.expectedQuests}',
                                          style: BsheelType.bodySm.copyWith(
                                            color: BsheelColors.inkMuted,
                                          ),
                                        ),
                                      ),
                                      DataCell(
                                        e.value.isConsistent
                                            ? const Icon(
                                                Icons.check_circle,
                                                color: BsheelColors.success,
                                                size: 18,
                                              )
                                            : const Icon(
                                                Icons.warning,
                                                color: BsheelColors.hot,
                                                size: 18,
                                              ),
                                      ),
                                      DataCell(
                                        e.value.isConsistent
                                            ? const SizedBox.shrink()
                                            : TextButton(
                                                onPressed: () =>
                                                    _fixUser(ref, e.value),
                                                child: Text(
                                                  'FIX',
                                                  style: BsheelType.labelSm
                                                      .copyWith(
                                                    color: BsheelColors.primary,
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: QuestSpacing.xl),
                  Text(
                    'MANUAL XP ADJUSTMENT',
                    style: BsheelType.labelMd.copyWith(
                      color: BsheelColors.ink,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  _ManualXpAdjuster(users: users),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // SEC-009: route through admin_set_user_xp so each fix lands in
  // admin_audit_log with the actor + before/after diff. The previous
  // direct .update() relied on the profiles_update_admin RLS policy
  // and bypassed the audit trail entirely.
  Future<void> _fixUser(WidgetRef ref, _UserXpAudit user) async {
    await AppBackend.repositories.admin.setXp(
      userId: user.userId,
      xp: user.expectedXp,
      level: user.expectedLevel,
      questsCompleted: user.expectedQuests,
      reason: 'XP audit auto-fix (single user)',
    );
    ref.invalidate(_xpAuditProvider);
  }

  Future<void> _fixAll(WidgetRef ref, List<_UserXpAudit> users) async {
    // Sequential on purpose: each fix is its own audited transaction, and
    // a bulk correction should stay legible in the audit log.
    for (final u in users) {
      await AppBackend.repositories.admin.setXp(
        userId: u.userId,
        xp: u.expectedXp,
        level: u.expectedLevel,
        questsCompleted: u.expectedQuests,
        reason: 'XP audit auto-fix (bulk)',
      );
    }
    ref.invalidate(_xpAuditProvider);
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;
  const _SectionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 4, height: 20, color: color),
        const SizedBox(width: QuestSpacing.sm),
        Text(
          title,
          style: BsheelType.labelMd.copyWith(
            color: BsheelColors.ink,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _AuditCard extends StatelessWidget {
  final _UserXpAudit user;
  final VoidCallback onFix;
  const _AuditCard({required this.user, required this.onFix});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: QuestSpacing.sm),
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.hot.withAlpha(15),
        border: Border.all(
          color: BsheelColors.hot.withAlpha(80),
          width: BsheelBorders.thin,
        ),
        borderRadius: BorderRadius.circular(BsheelRadii.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${user.username}',
                  style: BsheelType.bodyMd.copyWith(
                    fontWeight: FontWeight.w500,
                    color: BsheelColors.ink,
                  ),
                ),
                const SizedBox(height: QuestSpacing.xs),
                Text(
                  'XP: ${user.currentXp} → ${user.expectedXp}  |  '
                  'Level: ${user.currentLevel} → ${user.expectedLevel}  |  '
                  'Quests: ${user.currentQuests} → ${user.expectedQuests}',
                  style: BsheelType.labelSm.copyWith(
                    color: BsheelColors.hot,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: onFix,
            style: OutlinedButton.styleFrom(
              foregroundColor: BsheelColors.primary,
              side: const BorderSide(
                color: BsheelColors.primary,
                width: BsheelBorders.thin,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.full),
              ),
            ),
            child: Text(
              'FIX',
              style: BsheelType.labelSm.copyWith(
                color: BsheelColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualXpAdjuster extends ConsumerStatefulWidget {
  final List<_UserXpAudit> users;
  const _ManualXpAdjuster({required this.users});

  @override
  ConsumerState<_ManualXpAdjuster> createState() => _ManualXpAdjusterState();
}

class _ManualXpAdjusterState extends ConsumerState<_ManualXpAdjuster> {
  String? _selectedUserId;
  final _amountCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _amountCtrl.dispose();
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          Text(
            'Add or remove XP for a user manually.',
            style: BsheelType.bodySm.copyWith(
              color: BsheelColors.inkMuted,
            ),
          ),
          const SizedBox(height: QuestSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;

              final userDropdown = DropdownButtonFormField<String>(
                decoration: InputDecoration(
                  labelText: 'USER',
                  labelStyle: BsheelType.labelSm.copyWith(
                    color: BsheelColors.inkMuted,
                  ),
                  filled: true,
                  fillColor: BsheelColors.bg,
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
                style: BsheelType.bodySm,
                dropdownColor: BsheelColors.paper,
                initialValue: _selectedUserId,
                items: widget.users
                    .map(
                      (u) => DropdownMenuItem(
                        value: u.userId,
                        child: Text('@${u.username} (${u.currentXp} XP)'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _selectedUserId = v),
              );

              final amountField = BsheelTextField(
                controller: _amountCtrl,
                label: 'XP AMOUNT',
                hint: '+50 or -30',
                keyboardType: TextInputType.number,
                style: BsheelType.bodySm,
                hintStyle:
                    BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
                isDense: true,
              );

              final reasonField = BsheelTextField(
                controller: _reasonCtrl,
                label: 'REASON (OPTIONAL)',
                style: BsheelType.bodySm,
                hintStyle:
                    BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
                isDense: true,
              );

              final applyBtn = ElevatedButton(
                onPressed: _selectedUserId == null ? null : _applyXp,
                style: ElevatedButton.styleFrom(
                  backgroundColor: BsheelColors.primary,
                  foregroundColor: BsheelColors.pureWhite,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(BsheelRadii.full),
                  ),
                ),
                child: Text(
                  'APPLY',
                  style: BsheelType.labelSm.copyWith(
                    color: BsheelColors.pureWhite,
                  ),
                ),
              );

              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    userDropdown,
                    const SizedBox(height: QuestSpacing.sm),
                    amountField,
                    const SizedBox(height: QuestSpacing.sm),
                    reasonField,
                    const SizedBox(height: QuestSpacing.sm),
                    applyBtn,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 2, child: userDropdown),
                  const SizedBox(width: QuestSpacing.md),
                  Expanded(child: amountField),
                  const SizedBox(width: QuestSpacing.md),
                  Expanded(child: reasonField),
                  const SizedBox(width: QuestSpacing.md),
                  applyBtn,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _applyXp() async {
    final amount = int.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount == 0 || _selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid XP amount.')),
      );
      return;
    }

    // SEC-009: route through audited RPC. Pull current state first
    // (read-only) then call admin_set_user_xp so a delta becomes a
    // properly-logged "set" with reason.
    final profile =
        await AppBackend.repositories.profiles.getProfile(_selectedUserId!);
    if (profile == null) return;

    final currentXp = profile.xp;
    final currentDone = profile.questsCompleted;
    final newXp = (currentXp + amount).clamp(0, 999999);
    final newLevel = (newXp ~/ 100) + 1;
    final reason = _reasonCtrl.text.trim().isEmpty
        ? (amount > 0 ? 'Manual XP grant' : 'Manual XP deduction')
        : _reasonCtrl.text.trim();

    await AppBackend.repositories.admin.setXp(
      userId: _selectedUserId!,
      xp: newXp,
      level: newLevel,
      questsCompleted: currentDone,
      reason: reason,
    );

    ref.invalidate(_xpAuditProvider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Applied ${amount > 0 ? '+' : ''}$amount XP. New total: $newXp',
          ),
        ),
      );
      _amountCtrl.clear();
      _reasonCtrl.clear();
    }
  }
}
