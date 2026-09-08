import 'package:app_models/app_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/providers/admin_role_provider.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

class _UserOption {
  final String id;
  final String username;
  final String displayName;
  const _UserOption({
    required this.id,
    required this.username,
    required this.displayName,
  });
}

final _usersProvider =
    FutureProvider.autoDispose<List<_UserOption>>((ref) async {
  final rows = await AppBackend.repositories.admin.users(limit: 200);
  return (rows
      .map((row) => _UserOption(
            id: row['id']?.toString() ?? '',
            username: row['username']?.toString() ?? '',
            displayName: row['display_name']?.toString() ?? '',
          ))
      .toList()
    ..sort((a, b) => a.username.compareTo(b.username)));
});

/// The quest bank the QUEST field searches. Injection creates the quest
/// row server-side from these fields, so the picked quest is a template
/// rather than a reference — the admin never authors one by hand here.
final _questBankProvider =
    FutureProvider.autoDispose<List<QuestModel>>((ref) async {
  final quests = await AppBackend.repositories.quests.listAllQuestsAdmin();
  return quests.toList()..sort((a, b) => a.title.compareTo(b.title));
});

class _PendingInjection {
  final String id;
  final String questTitle;
  final String targetUserId;
  final String targetUsername;
  final DateTime createdAt;
  const _PendingInjection({
    required this.id,
    required this.questTitle,
    required this.targetUserId,
    required this.targetUsername,
    required this.createdAt,
  });
}

/// Unconsumed injections, newest first. The API joins the quest title and
/// the target username, replacing three client round-trips.
///
/// This is also the only block the client can know about before it
/// submits: `admin_quest_injections_pending_idx` is UNIQUE on
/// `target_user_id WHERE consumed_at IS NULL`, so a user already in this
/// list cannot take another injection.
final _pendingInjectionsProvider =
    FutureProvider.autoDispose<List<_PendingInjection>>((ref) async {
  final rows = await AppBackend.repositories.admin.injections();
  return rows
      .map((row) => _PendingInjection(
            id: row['id']?.toString() ?? '',
            questTitle: row['quest_title']?.toString() ?? 'UNKNOWN',
            targetUserId: row['target_user_id']?.toString() ?? '',
            targetUsername: row['target_username']?.toString() ?? 'unknown',
            createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.now(),
          ))
      .toList();
});

class QuestInjectionPage extends ConsumerStatefulWidget {
  const QuestInjectionPage({super.key});

  @override
  ConsumerState<QuestInjectionPage> createState() => _QuestInjectionPageState();
}

class _QuestInjectionPageState extends ConsumerState<QuestInjectionPage> {
  final _userCtrl = TextEditingController();
  final _questCtrl = TextEditingController();

  _UserOption? _selectedUser;
  QuestModel? _selectedQuest;
  String _userSearch = '';
  String _questSearch = '';
  bool _injecting = false;

  @override
  void dispose() {
    _userCtrl.dispose();
    _questCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = ref.watch(isSuperAdminProvider).valueOrNull ?? false;

    return AdminPane(
      title: 'Injection',
      // Coral, because this bypasses the roll: it is the one action on the
      // console that hands a user a quest they did not draw.
      meta: 'Direct assignment',
      metaColor: BsheelColors.dangerText,
      child: isSuperAdmin ? _form() : _locked(),
    );
  }

  Widget _locked() => const BsheelCallout.danger(
        'Quest injection is a super-admin action. Your role can review '
        'submissions but cannot assign a quest directly.',
      );

  Widget _form() {
    final blocking = _blockingInjection();
    final ready = _selectedUser != null && _selectedQuest != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Assign a quest to a specific user, bypassing the roll. The server '
          'still enforces one active quest per user, so this fails if they '
          'already have one running or awaiting review.',
          style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
        ),
        const SizedBox(height: 14),
        _userField(),
        const SizedBox(height: 14),
        _questField(),
        if (blocking != null) ...[
          const SizedBox(height: 14),
          BsheelCallout.danger(
            '@${blocking.targetUsername} already has an injected quest '
            'waiting — “${blocking.questTitle}”. A second injection will be '
            'rejected by the unique partial index.',
            trailing: BsheelButton.ghost(
              label: 'Cancel it',
              small: true,
              onPressed: () => _cancelInjection(blocking),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: BsheelButton.primary(
            label: 'Inject quest',
            loading: _injecting,
            // Null, not merely dim: the component draws the dashed
            // unavailable treatment so the block reads before the copy.
            onPressed: (ready && blocking == null) ? _injectQuest : null,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'EVERY INJECTION IS WRITTEN TO admin_audit_log',
          style: BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
        ),
      ],
    );
  }

  /// The pending injection that blocks the selected user, if any.
  ///
  /// There is no admin endpoint that reports another user's active quest,
  /// so this is not a full precheck: a user mid-quest with no pending
  /// injection reads as clear here and is refused by the server.
  _PendingInjection? _blockingInjection() {
    final user = _selectedUser;
    if (user == null) return null;
    final pending = ref.watch(_pendingInjectionsProvider).valueOrNull;
    if (pending == null) return null;
    for (final injection in pending) {
      if (injection.targetUserId == user.id) return injection;
    }
    return null;
  }

  // ── User field ─────────────────────────────────────────────────────

  Widget _userField() {
    final usersAsync = ref.watch(_usersProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelField(
          controller: _userCtrl,
          label: 'User',
          hint: 'Search by username or id…',
          suffix: _selectedUser == null
              ? null
              : BsheelIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Clear user',
                  size: 34,
                  ground: BsheelColors.card,
                  onTap: () {
                    _userCtrl.clear();
                    setState(() {
                      _selectedUser = null;
                      _userSearch = '';
                    });
                  },
                ),
          onChanged: (v) => setState(() {
            _userSearch = v.trim().toLowerCase();
            _selectedUser = null;
          }),
        ),
        if (_selectedUser == null && _userSearch.isNotEmpty)
          usersAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 8),
              child: BsheelLoadingList(rows: 2, rowHeight: 34),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'The user list didn’t come back, so nobody was selected '
                'and nothing was assigned. $e',
                style:
                    BsheelType.bodyXs.copyWith(color: BsheelColors.dangerText),
              ),
            ),
            data: (users) {
              final matches = users
                  .where((u) =>
                      u.username.toLowerCase().contains(_userSearch) ||
                      u.displayName.toLowerCase().contains(_userSearch) ||
                      u.id.toLowerCase().contains(_userSearch))
                  .take(6)
                  .toList(growable: false);
              return _results(
                empty: 'No user matches “${_userCtrl.text.trim()}”.',
                rows: [
                  for (final u in matches)
                    _ResultRow(
                      title: '@${u.username}',
                      subtitle: u.displayName.isEmpty ? u.id : u.displayName,
                      onTap: () {
                        _userCtrl.text = u.username;
                        setState(() {
                          _selectedUser = u;
                          _userSearch = '';
                        });
                      },
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  // ── Quest field ────────────────────────────────────────────────────

  Widget _questField() {
    final bankAsync = ref.watch(_questBankProvider);
    final selected = _selectedQuest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelField(
          controller: _questCtrl,
          label: 'Quest',
          hint: 'Search the quest bank…',
          suffix: selected == null
              ? null
              : BsheelIconButton(
                  icon: Icons.close_rounded,
                  tooltip: 'Clear quest',
                  size: 34,
                  ground: BsheelColors.card,
                  onTap: () {
                    _questCtrl.clear();
                    setState(() {
                      _selectedQuest = null;
                      _questSearch = '';
                    });
                  },
                ),
          onChanged: (v) => setState(() {
            _questSearch = v.trim().toLowerCase();
            _selectedQuest = null;
          }),
        ),
        if (selected != null) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              BsheelTag.category(selected.category),
              BsheelPill(selected.difficulty, small: true),
              BsheelPill('${selected.xpReward} XP', small: true),
              BsheelPill('${selected.durationHours}h', small: true),
            ],
          ),
        ],
        if (selected == null && _questSearch.isNotEmpty)
          bankAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 8),
              child: BsheelLoadingList(rows: 2, rowHeight: 34),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'The quest bank didn’t come back, so no quest was selected '
                'and nothing was assigned. $e',
                style:
                    BsheelType.bodyXs.copyWith(color: BsheelColors.dangerText),
              ),
            ),
            data: (quests) {
              final matches = quests
                  .where((q) =>
                      q.title.toLowerCase().contains(_questSearch) ||
                      q.category.toLowerCase().contains(_questSearch))
                  .take(6)
                  .toList(growable: false);
              return _results(
                empty: 'No quest in the bank matches '
                    '“${_questCtrl.text.trim()}”.',
                rows: [
                  for (final q in matches)
                    _ResultRow(
                      title: q.title,
                      subtitle: '${q.category} · ${q.difficulty} · '
                          '${q.xpReward} XP · ${q.durationHours}h',
                      onTap: () {
                        _questCtrl.text = q.title;
                        setState(() {
                          _selectedQuest = q;
                          _questSearch = '';
                        });
                      },
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _results({required String empty, required List<Widget> rows}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: BsheelCard.flat(
        color: BsheelColors.surface,
        child: rows.isEmpty
            ? Text(
                empty,
                style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────

  Future<void> _injectQuest() async {
    final user = _selectedUser;
    final quest = _selectedQuest;
    if (user == null || quest == null) return;

    setState(() => _injecting = true);
    try {
      await AppBackend.repositories.admin.injectQuest(
        targetUserId: user.id,
        title: quest.title,
        description: quest.description,
        category: quest.category,
        difficulty: quest.difficulty,
        xpReward: quest.xpReward,
        durationHours: quest.durationHours,
      );
      _snack('Quest injected for @${user.username}.');
      _questCtrl.clear();
      setState(() {
        _selectedQuest = null;
        _questSearch = '';
      });
      ref.invalidate(_pendingInjectionsProvider);
    } catch (e) {
      // A 23505 on admin_quest_injections_pending_idx arrives as
      // PENDING_INJECTION_EXISTS. Refetching makes the blocked callout
      // appear instead of leaving the failure only in a snack bar.
      ref.invalidate(_pendingInjectionsProvider);
      _snack('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _injecting = false);
    }
  }

  Future<void> _cancelInjection(_PendingInjection injection) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Cancel this injection',
        content: Text(
          'Cancel “${injection.questTitle}” for @${injection.targetUsername}? '
          'It will not surface on their next roll. The quest record stays in '
          'the database for audit and is excluded from the public random '
          'pool.',
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Keep it',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.coral(
            label: 'Cancel injection',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      // The API marks the row consumed rather than deleting it: deleting
      // would let the orphaned quest leak back into the public random pool,
      // whose isolation check matches on a row existing in this table.
      await AppBackend.repositories.admin.cancelInjection(injection.id);
      ref.invalidate(_pendingInjectionsProvider);
      _snack('Injection cancelled.');
    } catch (e) {
      _snack('Failed: $e', isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    if (!mounted) return;
    final ground = isError ? BsheelColors.danger : BsheelColors.card;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: ground,
        content: Text(
          message,
          // The snack ground is coral on an error: ink, never white.
          style: BsheelType.bodySm.copyWith(
            color: BsheelColors.onAccent(ground),
          ),
        ),
      ),
    );
  }
}

/// One tappable search result under a field.
class _ResultRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ResultRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: BsheelLayout.minTarget,
          ),
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BsheelType.titleSm,
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: BsheelType.monoSm,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
