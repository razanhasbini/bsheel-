import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/providers/admin_role_provider.dart';
import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/theme/bsheel_design.dart';
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
  final client = ref.watch(supabaseClientProvider);
  final data = await client
      .from(Tables.profiles)
      .select(
        '${ProfileColumns.id}, ${ProfileColumns.username}, ${ProfileColumns.displayName}',
      )
      .order(ProfileColumns.username);
  return (data as List)
      .map((row) {
        final m = row as Map<String, dynamic>;
        return _UserOption(
          id: m[ProfileColumns.id] as String,
          username: (m[ProfileColumns.username] ?? '') as String,
          displayName: (m[ProfileColumns.displayName] ?? '') as String,
        );
      })
      .toList();
});

class _PendingInjection {
  final String id;
  final String questTitle;
  final String targetUsername;
  final DateTime createdAt;
  const _PendingInjection({
    required this.id,
    required this.questTitle,
    required this.targetUsername,
    required this.createdAt,
  });
}

final _pendingInjectionsProvider =
    FutureProvider.autoDispose<List<_PendingInjection>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final rows = await client
      .from(Tables.adminQuestInjections)
      .select('id, created_at, target_user_id, quest_id')
      .filter('consumed_at', 'is', null)
      .order('created_at', ascending: false) as List;

  if (rows.isEmpty) return [];

  final questIds = <String>{};
  final userIds = <String>{};
  for (final r in rows) {
    final m = r as Map<String, dynamic>;
    questIds.add(m['quest_id'] as String);
    userIds.add(m['target_user_id'] as String);
  }

  final quests = await client
      .from(Tables.quests)
      .select('${QuestColumns.id}, ${QuestColumns.title}')
      .inFilter(QuestColumns.id, questIds.toList()) as List;
  final questTitles = <String, String>{
    for (final q in quests)
      (q as Map<String, dynamic>)[QuestColumns.id] as String:
          (q[QuestColumns.title] ?? '') as String,
  };

  final profiles = await client
      .from(Tables.profiles)
      .select('${ProfileColumns.id}, ${ProfileColumns.username}')
      .inFilter(ProfileColumns.id, userIds.toList()) as List;
  final usernames = <String, String>{
    for (final p in profiles)
      (p as Map<String, dynamic>)[ProfileColumns.id] as String:
          (p[ProfileColumns.username] ?? '') as String,
  };

  return rows.map((r) {
    final m = r as Map<String, dynamic>;
    return _PendingInjection(
      id: m['id'] as String,
      questTitle: questTitles[m['quest_id']] ?? 'UNKNOWN',
      targetUsername: usernames[m['target_user_id']] ?? 'unknown',
      createdAt: DateTime.parse(m['created_at'] as String),
    );
  }).toList();
});

class QuestInjectionPage extends ConsumerStatefulWidget {
  const QuestInjectionPage({super.key});

  @override
  ConsumerState<QuestInjectionPage> createState() => _QuestInjectionPageState();
}

class _QuestInjectionPageState extends ConsumerState<QuestInjectionPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // Shared user picker state
  _UserOption? _selectedUser;
  String _userSearch = '';

  // Quest form state
  final _questFormKey = GlobalKey<FormState>();
  final _questTitleCtrl = TextEditingController();
  final _questDescCtrl = TextEditingController();
  final _questXpCtrl = TextEditingController(text: '50');
  final _questDurationCtrl = TextEditingController(text: '4');
  String _questCategory = QuestCategory.fitness;
  String _questDifficulty = QuestDifficulty.easy;
  bool _injectingQuest = false;

  // Notification form state
  final _notifFormKey = GlobalKey<FormState>();
  final _notifTitleCtrl = TextEditingController();
  final _notifBodyCtrl = TextEditingController();
  bool _sendingNotif = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    _questTitleCtrl.dispose();
    _questDescCtrl.dispose();
    _questXpCtrl.dispose();
    _questDurationCtrl.dispose();
    _notifTitleCtrl.dispose();
    _notifBodyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin =
        ref.watch(isSuperAdminProvider).valueOrNull ?? false;
    if (!isSuperAdmin) {
      return Padding(
        padding: const EdgeInsets.all(QuestSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'INJECT',
              style:
                  BsheelType.displaySm.copyWith(color: BsheelColors.ink),
            ),
            const SizedBox(height: QuestSpacing.lg),
            Container(
              padding: const EdgeInsets.all(QuestSpacing.lg),
              decoration: BoxDecoration(
                color: BsheelColors.paper,
                border: Border.all(color: BsheelColors.ink, width: 1),
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline,
                      color: BsheelColors.hot, size: 20,),
                  const SizedBox(width: QuestSpacing.sm),
                  Expanded(
                    child: Text(
                      'Quest injection and admin notifications require '
                      'super-admin role.',
                      style: BsheelType.bodySm
                          .copyWith(color: BsheelColors.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BsheelCard(
          padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const BsheelEyebrow('Content · Injection'),
              const SizedBox(height: 14),
              BsheelDisplay(
                'Inject a {quest.}',
                baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
              ),
              const SizedBox(height: 12),
              Text(
                'Push a custom quest or notification to one specific user. '
                'Use sparingly — surfaces only on their next pull.',
                style: BsheelType.bodyMd
                    .copyWith(color: BsheelColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildUserPicker(),
          const SizedBox(height: QuestSpacing.md),
          Container(
            decoration: BoxDecoration(
              color: BsheelColors.paper,
              border: Border.all(color: BsheelColors.ink, width: 1),
              borderRadius: BorderRadius.circular(BsheelRadii.sm),
            ),
            child: TabBar(
              controller: _tab,
              indicatorColor: BsheelColors.primary,
              labelColor: BsheelColors.primary,
              unselectedLabelColor: BsheelColors.inkMuted,
              labelStyle: BsheelType.labelSm,
              tabs: const [
                Tab(text: 'QUEST'),
                Tab(text: 'NOTIFICATION'),
              ],
            ),
          ),
          const SizedBox(height: QuestSpacing.md),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _buildQuestForm(),
                _buildNotificationForm(),
              ],
            ),
          ),
      ],
    );
  }

  // ── User picker ────────────────────────────────────────────

  Widget _buildUserPicker() {
    final usersAsync = ref.watch(_usersProvider);
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
              Text(
                'TARGET USER',
                style: BsheelType.labelSm
                    .copyWith(color: BsheelColors.inkMuted),
              ),
              const Spacer(),
              if (_selectedUser != null)
                Text(
                  '@${_selectedUser!.username}',
                  style: BsheelType.labelSm
                      .copyWith(color: BsheelColors.primary),
                ),
            ],
          ),
          const SizedBox(height: QuestSpacing.sm),
          BsheelFormField(
            label: 'SEARCH BY USERNAME OR NAME',
            onChanged: (v) => setState(() => _userSearch = v.trim().toLowerCase()),
          ),
          const SizedBox(height: QuestSpacing.sm),
          SizedBox(
            height: 140,
            child: usersAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: BsheelColors.primary),
              ),
              error: (e, _) => Text(
                'Error: $e',
                style: const TextStyle(color: BsheelColors.hot),
              ),
              data: (users) {
                final filtered = _userSearch.isEmpty
                    ? users
                    : users
                        .where((u) =>
                            u.username.toLowerCase().contains(_userSearch) ||
                            u.displayName.toLowerCase().contains(_userSearch),)
                        .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'No users match',
                      style: BsheelType.bodySm
                          .copyWith(color: BsheelColors.inkMuted),
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final u = filtered[i];
                    final selected = _selectedUser?.id == u.id;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      selectedTileColor: BsheelColors.primary.withAlpha(25),
                      title: Text(
                        u.displayName.isNotEmpty ? u.displayName : u.username,
                        style: BsheelType.bodySm.copyWith(
                          color: selected
                              ? BsheelColors.primary
                              : BsheelColors.ink,
                        ),
                      ),
                      subtitle: Text(
                        '@${u.username}',
                        style: BsheelType.labelSm
                            .copyWith(color: BsheelColors.inkMuted),
                      ),
                      onTap: () => setState(() => _selectedUser = u),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Quest form ─────────────────────────────────────────────

  Widget _buildQuestForm() {
    final pendingAsync = ref.watch(_pendingInjectionsProvider);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Form(
            key: _questFormKey,
            child: Column(
              children: [
                BsheelFormField(
                  controller: _questTitleCtrl,
                  label: 'TITLE (3-100 CHARS)',
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.length < 3 || t.length > 100) return '3-100 chars';
                    return null;
                  },
                ),
                const SizedBox(height: QuestSpacing.md),
                BsheelFormField(
                  controller: _questDescCtrl,
                  label: 'DESCRIPTION (10-500 CHARS)',
                  maxLines: 3,
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.length < 10 || t.length > 500) return '10-500 chars';
                    return null;
                  },
                ),
                const SizedBox(height: QuestSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: BsheelDropdown<String>(
                        value: _questCategory,
                        label: 'CATEGORY',
                        items: const [
                          DropdownMenuItem(
                              value: QuestCategory.fitness,
                              child: Text('Fitness'),),
                          DropdownMenuItem(
                              value: QuestCategory.creativity,
                              child: Text('Creativity'),),
                          DropdownMenuItem(
                              value: QuestCategory.social,
                              child: Text('Social'),),
                          DropdownMenuItem(
                              value: QuestCategory.learning,
                              child: Text('Learning'),),
                          DropdownMenuItem(
                              value: QuestCategory.adventure,
                              child: Text('Adventure'),),
                        ],
                        onChanged: (v) =>
                            setState(() => _questCategory = v!),
                      ),
                    ),
                    const SizedBox(width: QuestSpacing.md),
                    Expanded(
                      child: BsheelDropdown<String>(
                        value: _questDifficulty,
                        label: 'DIFFICULTY',
                        items: const [
                          DropdownMenuItem(
                              value: QuestDifficulty.easy,
                              child: Text('Easy'),),
                          DropdownMenuItem(
                              value: QuestDifficulty.medium,
                              child: Text('Medium'),),
                          DropdownMenuItem(
                              value: QuestDifficulty.hard,
                              child: Text('Hard'),),
                        ],
                        onChanged: (v) =>
                            setState(() => _questDifficulty = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: QuestSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: BsheelFormField(
                        controller: _questXpCtrl,
                        label: 'XP REWARD (5-1000)',
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n < 5 || n > 1000) return '5-1000';
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: QuestSpacing.md),
                    Expanded(
                      child: BsheelFormField(
                        controller: _questDurationCtrl,
                        label: 'DURATION (HOURS)',
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          final n = int.tryParse((v ?? '').trim());
                          if (n == null || n < 1 || n > 168) return '1-168';
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: QuestSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    icon: _injectingQuest
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: BsheelColors.pureBlack,),
                          )
                        : const Icon(Icons.send, size: 16),
                    label: Text(
                      'INJECT QUEST',
                      style: BsheelType.labelSm
                          .copyWith(color: BsheelColors.pureBlack),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BsheelColors.primary,
                      foregroundColor: BsheelColors.pureBlack,
                      padding: const EdgeInsets.symmetric(
                          horizontal: QuestSpacing.lg,
                          vertical: QuestSpacing.sm,),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(BsheelRadii.sm),
                      ),
                    ),
                    onPressed: _injectingQuest ? null : _injectQuest,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: QuestSpacing.lg),
          Text(
            'PENDING INJECTIONS',
            style: BsheelType.labelSm
                .copyWith(color: BsheelColors.inkMuted),
          ),
          const SizedBox(height: QuestSpacing.sm),
          pendingAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(QuestSpacing.md),
              child: CircularProgressIndicator(color: BsheelColors.primary),
            ),
            error: (e, _) => Text(
              'Error: $e',
              style: const TextStyle(color: BsheelColors.hot),
            ),
            data: (rows) {
              if (rows.isEmpty) {
                return Text(
                  'No pending injections.',
                  style: BsheelType.bodySm
                      .copyWith(color: BsheelColors.inkMuted),
                );
              }
              return Column(
                children: rows
                    .map((r) => Container(
                          margin: const EdgeInsets.only(bottom: QuestSpacing.sm),
                          padding: const EdgeInsets.all(QuestSpacing.sm),
                          decoration: BoxDecoration(
                            color: BsheelColors.paper,
                            border: Border.all(color: BsheelColors.ink),
                            borderRadius:
                                BorderRadius.circular(BsheelRadii.sm),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.questTitle,
                                      style: BsheelType.bodySm
                                          .copyWith(color: BsheelColors.ink),
                                    ),
                                    Text(
                                      '→ @${r.targetUsername}',
                                      style: BsheelType.labelSm
                                          .copyWith(
                                              color: BsheelColors.inkMuted,),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Cancel injection',
                                icon: const Icon(Icons.delete_outline,
                                    color: BsheelColors.hot, size: 18,),
                                onPressed: () => _cancelInjection(r),
                              ),
                            ],
                          ),
                        ),)
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Future<void> _injectQuest() async {
    if (_selectedUser == null) {
      _snack('Pick a target user first.', isError: true);
      return;
    }
    if (!_questFormKey.currentState!.validate()) return;

    setState(() => _injectingQuest = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc(RpcNames.injectQuestForUser, params: {
        'p_target_user_id': _selectedUser!.id,
        'p_title': _questTitleCtrl.text.trim(),
        'p_description': _questDescCtrl.text.trim(),
        'p_category': _questCategory,
        'p_difficulty': _questDifficulty,
        'p_xp_reward': int.parse(_questXpCtrl.text.trim()),
        'p_duration_hours': int.parse(_questDurationCtrl.text.trim()),
      },);
      _snack('Quest injected for @${_selectedUser!.username}.');
      _questTitleCtrl.clear();
      _questDescCtrl.clear();
      ref.invalidate(_pendingInjectionsProvider);
    } catch (e) {
      _snack('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _injectingQuest = false);
    }
  }

  Future<void> _cancelInjection(_PendingInjection inj) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BsheelColors.paper,
        title: Text(
          'CANCEL INJECTION?',
          style: BsheelType.labelSm.copyWith(color: BsheelColors.ink),
        ),
        content: Text(
          'Cancel "${inj.questTitle}" for @${inj.targetUsername}? '
          'It will not surface on their next roll. The quest record stays '
          'in the database for audit and is excluded from the public random pool.',
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'KEEP',
              style: BsheelType.labelSm
                  .copyWith(color: BsheelColors.inkMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.hot,
              foregroundColor: BsheelColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
              ),
            ),
            child: Text(
              'CANCEL',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.ink),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final client = ref.read(supabaseClientProvider);
      // Mark consumed instead of deleting. Deleting the row would let the
      // orphaned quest leak into the public random pool (the isolation
      // check in assign_random_quest matches on EXISTS in this table).
      await client
          .from(Tables.adminQuestInjections)
          .update({'consumed_at': DateTime.now().toUtc().toIso8601String()})
          .eq('id', inj.id);
      ref.invalidate(_pendingInjectionsProvider);
      _snack('Injection cancelled.');
    } catch (e) {
      _snack('Failed: $e', isError: true);
    }
  }

  // ── Notification form ──────────────────────────────────────

  Widget _buildNotificationForm() {
    return SingleChildScrollView(
      child: Form(
        key: _notifFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BsheelFormField(
              controller: _notifTitleCtrl,
              label: 'TITLE',
              validator: _required,
            ),
            const SizedBox(height: QuestSpacing.md),
            BsheelFormField(
              controller: _notifBodyCtrl,
              label: 'BODY',
              maxLines: 4,
              validator: _required,
            ),
            const SizedBox(height: QuestSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                icon: _sendingNotif
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: BsheelColors.pureBlack,),
                      )
                    : const Icon(Icons.notifications_active, size: 16),
                label: Text(
                  'SEND NOTIFICATION',
                  style: BsheelType.labelSm
                      .copyWith(color: BsheelColors.pureBlack),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: BsheelColors.primary,
                  foregroundColor: BsheelColors.pureBlack,
                  padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.lg,
                      vertical: QuestSpacing.sm,),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(BsheelRadii.sm),
                  ),
                ),
                onPressed: _sendingNotif ? null : _sendNotification,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendNotification() async {
    if (_selectedUser == null) {
      _snack('Pick a target user first.', isError: true);
      return;
    }
    if (!_notifFormKey.currentState!.validate()) return;
    setState(() => _sendingNotif = true);
    try {
      final client = ref.read(supabaseClientProvider);
      await client.rpc(RpcNames.adminSendNotification, params: {
        'p_target_user_id': _selectedUser!.id,
        'p_title': _notifTitleCtrl.text.trim(),
        'p_body': _notifBodyCtrl.text.trim(),
        'p_type': NotificationType.announcement,
      },);
      _snack('Notification sent to @${_selectedUser!.username}.');
      _notifTitleCtrl.clear();
      _notifBodyCtrl.clear();
    } catch (e) {
      _snack('Failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _sendingNotif = false);
    }
  }

  // ── helpers ────────────────────────────────────────────────

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? BsheelColors.hot : BsheelColors.paper,
      ),
    );
  }
}
