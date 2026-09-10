import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
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

  /// Stored minus computed. Positive means the profile is holding XP the
  /// approved history does not account for.
  int get xpDelta => currentXp - expectedXp;

  String get label => username.isNotEmpty
      ? username
      : (displayName.isNotEmpty ? displayName : userId);
}

// ── Page ─────────────────────────────────────────────────────────────────────

class XpManagementPage extends ConsumerWidget {
  const XpManagementPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auditAsync = ref.watch(_xpAuditProvider);

    return AdminPane(
      title: 'XP reconciliation',
      meta: 'Audit',
      child: auditAsync.when(
        loading: () => const BsheelLoadingList(rows: 5, rowHeight: 46),
        error: (e, _) => BsheelErrorState(
          title: 'Audit didn’t run',
          message: 'The comparison didn’t come back, so nothing was compared '
              'and no balance has been touched. $e',
          onRetry: () => ref.invalidate(_xpAuditProvider),
        ),
        data: (users) => _AuditBody(users: users),
      ),
    );
  }
}

class _AuditBody extends ConsumerWidget {
  final List<_UserXpAudit> users;

  const _AuditBody({required this.users});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drifted = users.where((u) => !u.isConsistent).toList();
    final inSync = users.length - drifted.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text.rich(
          const TextSpan(
            children: [
              TextSpan(text: 'Compares '),
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _MonoChip('profiles.xp'),
              ),
              TextSpan(
                text: ' against the sum of approved submissions. A drift '
                    'means an award, reversal or deletion did not settle.',
              ),
            ],
          ),
          style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: BsheelStatTile(
                label: 'In sync',
                value: _grouped(inSync),
                ground: BsheelColors.success,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: BsheelStatTile(
                label: 'Drifted',
                value: _grouped(drifted.length),
                ground: BsheelColors.danger,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (drifted.isEmpty)
          BsheelEmptyState.allClear(
            message: 'Every profile matches the XP its approved submissions '
                'imply. Nothing to reconcile — come back after the next '
                'batch of approvals.',
            actionLabel: 'Re-run the audit',
            onAction: () => ref.invalidate(_xpAuditProvider),
          )
        else
          BsheelTable(
            depth: 4,
            columns: const [
              BsheelColumn('User'),
              BsheelColumn('Stored', width: 84),
              BsheelColumn('Computed', width: 84),
              BsheelColumn('Delta', width: 80),
            ],
            rows: [
              for (final u in drifted)
                BsheelRow(
                  [
                    Text(
                      u.label,
                      style: BsheelType.titleMd,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    BsheelCell.mono(_grouped(u.currentXp), bold: false),
                    BsheelCell.mono(_grouped(u.expectedXp), bold: false),
                    BsheelCell.mono(
                      _signed(u.xpDelta),
                      color: BsheelColors.dangerText,
                    ),
                  ],
                  // The design draws no per-row action, so the row itself
                  // opens the single-user reconcile the page has always
                  // had — each one is its own audited transaction.
                  onTap: () => _confirmOne(context, ref, u),
                ),
            ],
          ),
        const SizedBox(height: 14),
        // Bulk reconcile is deliberately unavailable.
        //
        // "Drift" means profiles.xp disagrees with the submission ledger — but
        // a manual grant through the adjuster below writes profiles.xp without
        // a ledger row, so every hand-adjusted player reads as drifted
        // forever. A bulk rewrite would silently zero all of them, with no
        // undo. Reconcile one profile at a time, after checking why it drifted.
        //
        // Re-enable once manual adjustments record a ledger entry.
        const Align(
          alignment: Alignment.centerLeft,
          child: BsheelButton.primary(
            label: 'Reconcile all',
            onPressed: null,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Bulk reconcile is disabled: manual XP grants leave no ledger entry, '
          'so they read as drift and would be zeroed. Reconcile individually '
          'after confirming the cause.',
          style: BsheelType.bodySm,
        ),
        const SizedBox(height: 26),
        const BsheelLabel('Manual adjustment'),
        const SizedBox(height: 8),
        _ManualXpAdjuster(users: users),
      ],
    );
  }

  Future<void> _confirmOne(
    BuildContext context,
    WidgetRef ref,
    _UserXpAudit user,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        // Named per-user because this is the only reconcile path left, and the
        // operator needs to know a manual grant is an expected cause of drift
        // rather than a bug to "fix".
        title: 'Reconcile ${user.label}?',
        content: Text(
          'Rewrites this profile to ${_grouped(user.expectedXp)} XP, level '
          '${user.expectedLevel} and ${user.expectedQuests} completed '
          'quests — the totals recorded on its awarded submissions. The '
          'change lands in the admin audit log with your name on it, and '
          'there is no undo.\n\n'
          'Check the cause first: a manual XP grant writes no ledger entry, '
          'so a hand-adjusted player shows as drifted and reconciling would '
          'remove the grant.',
          style: BsheelType.bodySm,
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          BsheelButton.coral(
            label: 'Reconcile',
            small: true,
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (ok == true) await _fixUser(ref, user);
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
}

// ── Inline code chip ─────────────────────────────────────────────────────────

/// A column name drawn inside a sentence: cream box, 2px ink outline,
/// mono type. Small enough to sit on the body baseline.
class _MonoChip extends StatelessWidget {
  final String text;

  const _MonoChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: BsheelColors.surface,
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
        border: const Border.fromBorderSide(BsheelBorders.inkSide),
      ),
      child: Text(text, style: BsheelType.monoSm),
    );
  }
}

// ── Number helpers ───────────────────────────────────────────────────────────

/// `11780` → `11,780`. Grouped so a five-figure balance can be read at a
/// glance in an 84px column.
String _grouped(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '−' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

/// A delta always carries its sign, so the direction of the drift is
/// readable without comparing the two columns beside it.
String _signed(int n) {
  if (n == 0) return '0';
  return '${n > 0 ? '+' : '−'}${_grouped(n.abs())}';
}

// ── Manual adjustment ────────────────────────────────────────────────────────

/// Kept from the previous page: a direct grant or deduction, still routed
/// through the audited `admin_set_user_xp` RPC. The design frame does not
/// draw it, but removing it would drop an audited capability.
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
    return BsheelCard(
      depth: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Add or remove XP for one player. The adjustment is logged '
            'against your account with its reason.',
            style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
          ),
          const SizedBox(height: 12),
          BsheelDropdown<String?>(
            label: 'Player',
            value: _selectedUserId,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Pick a player…'),
              ),
              for (final u in widget.users)
                DropdownMenuItem<String?>(
                  value: u.userId,
                  child: Text('${u.label} · ${_grouped(u.currentXp)} XP'),
                ),
            ],
            onChanged: (v) => setState(() => _selectedUserId = v),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: BsheelField(
                  controller: _amountCtrl,
                  label: 'XP amount',
                  hint: '+50 or -30',
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: BsheelField(
                  controller: _reasonCtrl,
                  label: 'Reason',
                  hint: 'Optional — shown in the audit log',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: BsheelButton.ghost(
              label: 'Apply adjustment',
              small: true,
              onPressed: _selectedUserId == null ? null : _applyXp,
            ),
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
