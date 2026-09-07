import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:app_core/app_core.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/providers/supabase_provider.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final usersProvider = FutureProvider.autoDispose<List<_UserRow>>((ref) async {
  final client = ref.watch(supabaseClientProvider);

  final profiles = await client
      .from(Tables.profiles)
      .select('*')
      .order(ProfileColumns.createdAt, ascending: false);

  final admins = await client
      .from(Tables.admins)
      .select('${AdminColumns.userId}, ${AdminColumns.role}');

  final adminMap = <String, String>{};
  for (final a in admins) {
    adminMap[a[AdminColumns.userId].toString()] =
        a[AdminColumns.role].toString();
  }

  final avatarRefs = (profiles as List)
      .map((p) => p[ProfileColumns.avatarUrl]?.toString())
      .whereType<String>();
  final signedAvatars = await SignedMediaUrls.signMany(client, avatarRefs);

  return profiles.map((p) {
    final id = p[ProfileColumns.id]?.toString() ?? '';
    final avatarUrl = p[ProfileColumns.avatarUrl]?.toString();
    return _UserRow(
      id: id,
      username: p[ProfileColumns.username]?.toString() ?? '',
      displayName: p[ProfileColumns.displayName]?.toString() ?? '',
      avatarUrl: avatarUrl == null ? null : signedAvatars[avatarUrl] ?? avatarUrl,
      bio: p[ProfileColumns.bio]?.toString(),
      xp: p[ProfileColumns.xp] ?? 0,
      level: p[ProfileColumns.level] ?? 1,
      questsCompleted: p[ProfileColumns.questsCompleted] ?? 0,
      createdAt:
          DateTime.tryParse(p[ProfileColumns.createdAt]?.toString() ?? ''),
      adminRole: adminMap[id],
    );
  }).toList();
});

class _UserRow {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final int xp;
  final int level;
  final int questsCompleted;
  final DateTime? createdAt;
  final String? adminRole;

  const _UserRow({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    this.bio,
    required this.xp,
    required this.level,
    required this.questsCompleted,
    this.createdAt,
    this.adminRole,
  });

  bool get isAdmin => adminRole != null;
  bool get isSuperAdmin => adminRole == AdminRole.superAdmin;
  bool get isModerator => adminRole == AdminRole.moderator;
}

// ── Page ─────────────────────────────────────────────────────────────────────

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key, this.initialQuery});

  /// Optional search query handed over from the topbar search field
  /// (`/users?q=...`). Pre-fills and applies the page's search filter.
  final String? initialQuery;

  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  late final TextEditingController _searchCtrl =
      TextEditingController(text: widget.initialQuery ?? '');
  late String _search = (widget.initialQuery ?? '').toLowerCase();

  @override
  void didUpdateWidget(covariant UsersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-submitting from the topbar while already on /users rebuilds this
    // widget with a new query — mirror it into the local filter state.
    if (widget.initialQuery != oldWidget.initialQuery) {
      final q = widget.initialQuery ?? '';
      _searchCtrl.text = q;
      _search = q.toLowerCase();
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(usersProvider);

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
                    const BsheelEyebrow('Community · Users'),
                    const SizedBox(height: 14),
                    BsheelDisplay(
                      'Mind the {community.}',
                      baseStyle:
                          BsheelType.displayXl.copyWith(fontSize: 44),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Search, export, and moderate every user account.',
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
                  BsheelButton.ghost(
                    label: 'EXPORT',
                    icon: Icons.file_download_rounded,
                    small: true,
                    onPressed: usersAsync.maybeWhen(
                      data: (users) => () => _exportToExcel(users),
                      orElse: () => null,
                    ),
                  ),
                  BsheelButton.primary(
                    label: 'ADD USER',
                    icon: Icons.person_add_rounded,
                    small: true,
                    onPressed: () => _showCreateUserDialog(context),
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
            controller: _searchCtrl,
            style: BsheelType.bodySm,
            decoration: InputDecoration(
              hintText: 'Search by username or display name...',
              hintStyle: BsheelType.bodySm.copyWith(
                color: BsheelColors.inkMuted,
              ),
              prefixIcon: const Icon(Icons.search, color: BsheelColors.inkMuted),
              filled: true,
              fillColor: BsheelColors.paper,
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
                borderSide: const BorderSide(color: BsheelColors.ink),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
                borderSide: const BorderSide(color: BsheelColors.ink, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
                borderSide:
                    const BorderSide(color: BsheelColors.primary, width: 1),
              ),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        Expanded(
            child: usersAsync.when(
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
                final filtered = users.where((u) {
                  if (_search.isEmpty) return true;
                  return u.username.toLowerCase().contains(_search) ||
                      u.displayName.toLowerCase().contains(_search);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      'No users found.',
                      style: BsheelType.bodyMd.copyWith(
                        color: BsheelColors.inkMuted,
                      ),
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
                          color: BsheelColors.ink,
                          width: 1,
                        ),
                        borderRadius:
                            BorderRadius.circular(BsheelRadii.sm),
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
                            DataColumn(label: Text('USER')),
                            DataColumn(label: Text('XP'), numeric: true),
                            DataColumn(label: Text('LEVEL'), numeric: true),
                            DataColumn(label: Text('QUESTS'), numeric: true),
                            DataColumn(label: Text('ROLE')),
                            DataColumn(label: Text('JOINED')),
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

  Widget _buildMobileCard(BuildContext context, _UserRow user) {
    final createdAt = user.createdAt;
    return Container(
      padding: const EdgeInsets.all(QuestSpacing.md),
      decoration: BoxDecoration(
        color: BsheelColors.paper,
        border: Border.all(color: BsheelColors.ink, width: 1),
        borderRadius: BorderRadius.circular(BsheelRadii.sm),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: BsheelColors.cool.withAlpha(50),
            backgroundImage: user.avatarUrl != null
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null
                ? Text(
                    user.displayName.isNotEmpty
                        ? user.displayName[0].toUpperCase()
                        : '?',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.cool,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          const SizedBox(width: QuestSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: BsheelType.bodySm.copyWith(
                    fontWeight: FontWeight.w600,
                    color: BsheelColors.ink,
                  ),
                ),
                Text(
                  '@${user.username}',
                  style: BsheelType.labelSm.copyWith(
                    color: BsheelColors.inkMuted,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: QuestSpacing.xs),
                Wrap(
                  spacing: QuestSpacing.sm,
                  runSpacing: 4,
                  children: [
                    Text(
                      '${user.xp} XP',
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.accent,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      'LV${user.level}',
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.primary,
                        fontSize: 10,
                      ),
                    ),
                    Text(
                      '${user.questsCompleted} quests',
                      style: BsheelType.labelSm.copyWith(
                        color: BsheelColors.inkMuted,
                        fontSize: 10,
                      ),
                    ),
                    if (createdAt != null)
                      Text(
                        'Joined ${createdAt.year}-${createdAt.month.toString().padLeft(2, '0')}-${createdAt.day.toString().padLeft(2, '0')}',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.inkMuted,
                          fontSize: 10,
                        ),
                      ),
                    _RoleBadge(role: user.adminRole),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: BsheelColors.inkMuted),
            color: BsheelColors.paper,
            tooltip: 'Actions',
            onSelected: (action) => _handleAction(context, action, user),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'view',
                child: _MenuItem(Icons.visibility, 'View Details'),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: _MenuItem(Icons.edit, 'Edit Profile'),
              ),
              const PopupMenuItem(
                value: 'assign_quest',
                child: _MenuItem(Icons.assignment, 'Assign Quest'),
              ),
              const PopupMenuItem(
                value: 'send_notification',
                child: _MenuItem(Icons.notifications, 'Send Notification'),
              ),
              const PopupMenuItem(
                value: 'role',
                child: _MenuItem(Icons.shield, 'Manage Role'),
              ),
              const PopupMenuItem(
                value: 'reset_pw',
                child: _MenuItem(Icons.lock_reset, 'Reset Password'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'suspend',
                child: _MenuItem(Icons.pause_circle, 'Suspend User', isDestructive: true),
              ),
              const PopupMenuItem(
                value: 'ban',
                child: _MenuItem(Icons.block, 'Ban User', isDestructive: true),
              ),
              const PopupMenuItem(
                value: 'activate',
                child: _MenuItem(Icons.check_circle, 'Activate User'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: _MenuItem(
                  Icons.delete,
                  'Delete User',
                  isDestructive: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DataRow _buildRow(BuildContext context, _UserRow user, int index) {
    final createdAt = user.createdAt;
    final rowColor =
        index.isEven ? BsheelColors.paper : BsheelColors.surface;

    return DataRow(
      color: WidgetStateProperty.all(rowColor),
      cells: [
        DataCell(
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: BsheelColors.cool.withAlpha(50),
                backgroundImage: user.avatarUrl != null
                    ? NetworkImage(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? Text(
                        user.displayName.isNotEmpty
                            ? user.displayName[0].toUpperCase()
                            : '?',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.cool,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: QuestSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user.displayName,
                    style: BsheelType.bodySm.copyWith(
                      fontWeight: FontWeight.w500,
                      color: BsheelColors.ink,
                    ),
                  ),
                  Text(
                    '@${user.username}',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.inkMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        DataCell(
          Text(
            '${user.xp}',
            style: BsheelType.labelSm.copyWith(color: BsheelColors.accent),
          ),
        ),
        DataCell(
          Text(
            '${user.level}',
            style: BsheelType.labelSm.copyWith(
              color: BsheelColors.primary,
            ),
          ),
        ),
        DataCell(
          Text(
            '${user.questsCompleted}',
            style: BsheelType.bodySm.copyWith(color: BsheelColors.ink),
          ),
        ),
        DataCell(_RoleBadge(role: user.adminRole)),
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: BsheelColors.inkMuted),
            color: BsheelColors.paper,
            tooltip: 'Actions',
            onSelected: (action) => _handleAction(context, action, user),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'view',
                child: _MenuItem(Icons.visibility, 'View Details'),
              ),
              const PopupMenuItem(
                value: 'edit',
                child: _MenuItem(Icons.edit, 'Edit Profile'),
              ),
              const PopupMenuItem(
                value: 'assign_quest',
                child: _MenuItem(Icons.assignment, 'Assign Quest'),
              ),
              const PopupMenuItem(
                value: 'send_notification',
                child: _MenuItem(Icons.notifications, 'Send Notification'),
              ),
              const PopupMenuItem(
                value: 'role',
                child: _MenuItem(Icons.shield, 'Manage Role'),
              ),
              const PopupMenuItem(
                value: 'reset_pw',
                child: _MenuItem(Icons.lock_reset, 'Reset Password'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'suspend',
                child: _MenuItem(Icons.pause_circle, 'Suspend User', isDestructive: true),
              ),
              const PopupMenuItem(
                value: 'ban',
                child: _MenuItem(Icons.block, 'Ban User', isDestructive: true),
              ),
              const PopupMenuItem(
                value: 'activate',
                child: _MenuItem(Icons.check_circle, 'Activate User'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: _MenuItem(Icons.delete, 'Delete User', isDestructive: true),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleAction(BuildContext context, String action, _UserRow user) {
    switch (action) {
      case 'view':
        _showViewDialog(context, user);
      case 'edit':
        _showEditDialog(context, user);
      case 'assign_quest':
        _showAssignQuestDialog(context, user);
      case 'send_notification':
        _showSendNotificationDialog(context, user);
      case 'role':
        _showRoleDialog(context, user);
      case 'reset_pw':
        _showResetPasswordDialog(context, user);
      case 'suspend':
        _confirmStatusChange(context, user, 'suspended');
      case 'ban':
        _confirmStatusChange(context, user, 'banned');
      case 'activate':
        // Restorative action — no confirmation needed.
        _setAccountStatus(user.id, 'active', user.displayName);
      case 'delete':
        _confirmDelete(context, user);
    }
  }

  Future<void> _setAccountStatus(String userId, String status, String name) async {
    final client = ref.read(supabaseClientProvider);
    try {
      await client.rpc(RpcNames.setUserAccountStatus, params: {
        'p_user_id': userId,
        'p_status': status,
      },);
      ref.invalidate(usersProvider);
      if (mounted) {
        final label = status == 'active' ? 'activated' : status == 'suspended' ? 'suspended' : 'banned';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name has been $label.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update status: $e')),
        );
      }
    }
  }

  void _showViewDialog(BuildContext context, _UserRow user) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: user.displayName.toUpperCase(),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DetailRow('USERNAME', '@${user.username}'),
              _DetailRow('DISPLAY NAME', user.displayName),
              _DetailRow('USER ID', user.id),
              _DetailRow('XP', '${user.xp}'),
              _DetailRow('LEVEL', '${user.level}'),
              _DetailRow('QUESTS COMPLETED', '${user.questsCompleted}'),
              _DetailRow('BIO', user.bio ?? '-'),
              _DetailRow('ROLE', user.adminRole ?? 'User'),
              _DetailRow(
                'JOINED',
                user.createdAt != null
                    ? '${user.createdAt!.year}-${user.createdAt!.month.toString().padLeft(2, '0')}-${user.createdAt!.day.toString().padLeft(2, '0')}'
                    : '-',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'CLOSE',
              style: BsheelType.labelSm.copyWith(
                color: BsheelColors.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, _UserRow user) {
    final usernameCtrl = TextEditingController(text: user.username);
    final displayNameCtrl = TextEditingController(text: user.displayName);
    final bioCtrl = TextEditingController(text: user.bio ?? '');
    final xpCtrl = TextEditingController(text: '${user.xp}');
    final levelCtrl = TextEditingController(text: '${user.level}');
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'EDIT ${user.displayName.toUpperCase()}',
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BsheelFormField(
                    controller: usernameCtrl,
                    label: 'USERNAME',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: displayNameCtrl,
                    label: 'DISPLAY NAME',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: bioCtrl,
                    label: 'BIO',
                    maxLines: 2,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  Row(
                    children: [
                      Expanded(
                        child: BsheelFormField(
                          controller: xpCtrl,
                          label: 'XP',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 0 ? 'Invalid' : null;
                          },
                        ),
                      ),
                      const SizedBox(width: QuestSpacing.md),
                      Expanded(
                        child: BsheelFormField(
                          controller: levelCtrl,
                          label: 'LEVEL',
                          keyboardType: TextInputType.number,
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 1 ? 'Invalid' : null;
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              await _updateProfile(
                user.id,
                usernameCtrl.text.trim(),
                displayNameCtrl.text.trim(),
                bioCtrl.text.trim(),
                int.parse(xpCtrl.text.trim()),
                int.parse(levelCtrl.text.trim()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.primary,
              foregroundColor: BsheelColors.pureBlack,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
              ),
            ),
            child: Text(
              'SAVE',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.pureBlack),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _updateProfile(
    String userId,
    String username,
    String displayName,
    String bio,
    int xp,
    int level,
  ) async {
    final client = ref.read(supabaseClientProvider);
    try {
      await client.from(Tables.profiles).update({
        ProfileColumns.username: username,
        ProfileColumns.displayName: displayName,
        ProfileColumns.bio: bio.isEmpty ? null : bio,
        ProfileColumns.xp: xp,
        ProfileColumns.level: level,
      }).eq(ProfileColumns.id, userId);
      ref.invalidate(usersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update: $e')),
        );
      }
    }
  }

  void _showRoleDialog(BuildContext context, _UserRow user) {
    String? selectedRole = user.adminRole;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => BsheelDialog(
          title: 'MANAGE ROLE: ${user.displayName.toUpperCase()}',
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current role: ${user.adminRole ?? "Regular User"}',
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkMuted,
                  ),
                ),
                const SizedBox(height: QuestSpacing.md),
                RadioGroup<String?>(
                  groupValue: selectedRole,
                  onChanged: (v) => setDialogState(() => selectedRole = v),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _DarkRadioTile<String?>(
                        title: 'REGULAR USER',
                        subtitle: 'No admin privileges',
                        value: null,
                      ),
                      _DarkRadioTile<String?>(
                        title: 'MODERATOR',
                        subtitle: 'Can review submissions',
                        value: AdminRole.moderator,
                      ),
                      _DarkRadioTile<String?>(
                        title: 'SUPER ADMIN',
                        subtitle: 'Full admin access',
                        value: AdminRole.superAdmin,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
              onPressed: () async {
                Navigator.pop(ctx);
                await _setRole(user.id, selectedRole);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: BsheelColors.primary,
                foregroundColor: BsheelColors.pureBlack,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(BsheelRadii.sm),
                ),
              ),
              child: Text(
                'SAVE',
                style: BsheelType.labelSm.copyWith(color: BsheelColors.pureBlack),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setRole(String userId, String? role) async {
    final client = ref.read(supabaseClientProvider);
    try {
      await client.functions.invoke(
        EdgeFunctionNames.adminManageUser,
        body: {
          'action': 'set_admin_role',
          'user_id': userId,
          'role': role,
        },
      );
      ref.invalidate(usersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              role != null
                  ? 'Role updated to $role.'
                  : 'Admin role removed.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update role: $e')),
        );
      }
    }
  }

  void _showResetPasswordDialog(BuildContext context, _UserRow user) {
    final pwCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'RESET PASSWORD: ${user.displayName.toUpperCase()}',
        content: SizedBox(
          width: 360,
          child: Form(
            key: formKey,
            child: BsheelFormField(
              controller: pwCtrl,
              label: 'NEW PASSWORD',
              // SEC-010: mirror the policy used everywhere else
              // (≥10 chars, mix of upper/lower/digit, no banned
              // substrings). The edge function re-validates on
              // submit so this is purely a UX hint.
              validator: _validateAdminResetPassword,
            ),
          ),
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
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              await _resetPassword(user.id, pwCtrl.text);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.primary,
              foregroundColor: BsheelColors.pureBlack,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
              ),
            ),
            child: Text(
              'RESET',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.pureBlack),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(String userId, String newPassword) async {
    final client = ref.read(supabaseClientProvider);
    try {
      await client.functions.invoke(
        EdgeFunctionNames.adminManageUser,
        body: {
          'action': 'reset_password',
          'user_id': userId,
          'new_password': newPassword,
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password reset successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reset password: $e')),
        );
      }
    }
  }

  /// Confirmation gate for the destructive account-status actions
  /// (suspend / ban). Activate is restorative and stays unconfirmed.
  void _confirmStatusChange(
    BuildContext context,
    _UserRow user,
    String status,
  ) {
    final (String title, String verb, String consequence) = switch (status) {
      'banned' => (
          'BAN USER',
          'ban',
          'They will be locked out of the app until reactivated.',
        ),
      _ => (
          'SUSPEND USER',
          'suspend',
          'They will be temporarily locked out until reactivated.',
        ),
    };

    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: title,
        content: Text(
          'Are you sure you want to $verb "${user.displayName}" '
          '(@${user.username})?\n\n$consequence',
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
              foregroundColor: BsheelColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _setAccountStatus(user.id, status, user.displayName);
            },
            child: Text(
              verb.toUpperCase(),
              style: BsheelType.labelSm.copyWith(color: BsheelColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, _UserRow user) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'DELETE USER',
        content: Text(
          'Are you sure you want to delete "${user.displayName}" (@${user.username})?\n\n'
          'This will permanently remove their account, profile, quests, and submissions. '
          'This cannot be undone.',
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
              foregroundColor: BsheelColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
              ),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteUser(user.id);
            },
            child: Text(
              'DELETE',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(String userId) async {
    final client = ref.read(supabaseClientProvider);
    try {
      final res = await client.functions.invoke(
        EdgeFunctionNames.adminManageUser,
        body: {
          'action': 'delete_user',
          'user_id': userId,
        },
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }
      ref.invalidate(usersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User deleted.')),
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

  void _showAssignQuestDialog(BuildContext context, _UserRow user) {
    final client = ref.read(supabaseClientProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => _AssignQuestDialog(
        user: user,
        client: client,
        onAssigned: () {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Quest assigned to ${user.displayName}.')),
            );
          }
        },
        onError: (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to assign quest: $e')),
            );
          }
        },
      ),
    );
  }

  void _showSendNotificationDialog(BuildContext context, _UserRow user) {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'SEND NOTIFICATION TO ${user.displayName.toUpperCase()}',
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BsheelFormField(
                  controller: titleCtrl,
                  label: 'TITLE',
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: QuestSpacing.md),
                BsheelFormField(
                  controller: bodyCtrl,
                  label: 'MESSAGE',
                  maxLines: 3,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'CANCEL',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              await _sendNotification(
                user.id,
                titleCtrl.text.trim(),
                bodyCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.cool,
              foregroundColor: BsheelColors.ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
              ),
            ),
            child: Text(
              'SEND',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.ink),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sendNotification(
    String userId,
    String title,
    String body,
  ) async {
    final client = ref.read(supabaseClientProvider);
    try {
      // 1. Store in notifications table (in-app bell)
      await client.from(Tables.notifications).insert({
        NotificationColumns.userId: userId,
        NotificationColumns.title: title,
        NotificationColumns.body: body,
        NotificationColumns.type: 'announcement',
      });

      // 2. Get the user's FCM token for push delivery
      final profileData = await client
          .from(Tables.profiles)
          .select(ProfileColumns.fcmToken)
          .eq(ProfileColumns.id, userId)
          .maybeSingle();

      final fcmToken = profileData?[ProfileColumns.fcmToken] as String?;
      if (fcmToken != null && fcmToken.isNotEmpty) {
        await client.functions.invoke(
          EdgeFunctionNames.sendPush,
          body: {
            'token': fcmToken,
            'title': title,
            'body': body,
          },
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              fcmToken != null
                  ? 'Notification sent (push + in-app).'
                  : 'Notification stored (user has no FCM token).',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send notification: $e')),
        );
      }
    }
  }

  void _showCreateUserDialog(BuildContext context) {
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final displayNameCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'CREATE NEW USER',
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BsheelFormField(
                    controller: emailCtrl,
                    label: 'EMAIL',
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: passwordCtrl,
                    label: 'PASSWORD',
                    // Same SEC-010 policy as admin password resets:
                    // ≥10 chars + upper/lower/digit, no banned substrings.
                    validator: _validateAdminResetPassword,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: usernameCtrl,
                    label: 'USERNAME',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: displayNameCtrl,
                    label: 'DISPLAY NAME (OPTIONAL)',
                  ),
                ],
              ),
            ),
          ),
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
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              await _createUser(
                emailCtrl.text.trim(),
                passwordCtrl.text,
                usernameCtrl.text.trim(),
                displayNameCtrl.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.primary,
              foregroundColor: BsheelColors.pureBlack,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(BsheelRadii.sm),
              ),
            ),
            child: Text(
              'CREATE',
              style: BsheelType.labelSm.copyWith(color: BsheelColors.pureBlack),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _createUser(
    String email,
    String password,
    String username,
    String displayName,
  ) async {
    final client = ref.read(supabaseClientProvider);
    try {
      final res = await client.functions.invoke(
        EdgeFunctionNames.adminManageUser,
        body: {
          'action': 'create_user',
          'email': email,
          'password': password,
          'username': username,
          'display_name': displayName.isEmpty ? username : displayName,
        },
      );
      final data = res.data;
      if (data is Map && data['error'] != null) {
        throw Exception(data['error']);
      }
      ref.invalidate(usersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User created successfully.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create user: $e')),
        );
      }
    }
  }

  void _exportToExcel(List<_UserRow> users) {
    try {
      final book = xl.Excel.createExcel();
      final defaultSheetName = book.getDefaultSheet() ?? 'Sheet1';
      book.rename(defaultSheetName, 'Users');
      final sheet = book['Users'];

      const headers = [
        'User ID',
        'Username',
        'Display Name',
        'XP',
        'Level',
        'Quests Completed',
        'Role',
        'Bio',
        'Avatar URL',
        'Joined',
      ];
      sheet.appendRow(headers.map<xl.CellValue>((h) => xl.TextCellValue(h)).toList());

      for (final u in users) {
        final joined = u.createdAt;
        sheet.appendRow(<xl.CellValue>[
          xl.TextCellValue(u.id),
          xl.TextCellValue(u.username),
          xl.TextCellValue(u.displayName),
          xl.IntCellValue(u.xp),
          xl.IntCellValue(u.level),
          xl.IntCellValue(u.questsCompleted),
          xl.TextCellValue(u.adminRole ?? 'user'),
          xl.TextCellValue(u.bio ?? ''),
          xl.TextCellValue(u.avatarUrl ?? ''),
          xl.TextCellValue(
            joined != null
                ? '${joined.year}-${joined.month.toString().padLeft(2, '0')}-${joined.day.toString().padLeft(2, '0')} '
                    '${joined.hour.toString().padLeft(2, '0')}:${joined.minute.toString().padLeft(2, '0')}'
                : '',
          ),
        ]);
      }

      final bytes = book.save();
      if (bytes == null) {
        throw 'Failed to encode .xlsx';
      }

      final now = DateTime.now();
      final stamp = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
          '_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
      final filename = 'users_$stamp.xlsx';

      final blob = web.Blob(
        [Uint8List.fromList(bytes).toJS].toJS,
        web.BlobPropertyBag(
          type:
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        ),
      );
      final url = web.URL.createObjectURL(blob);
      final anchor = web.HTMLAnchorElement()
        ..href = url
        ..setAttribute('download', filename)
        ..style.display = 'none';
      web.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      web.URL.revokeObjectURL(url);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${users.length} users to $filename')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
        );
      }
    }
  }
}

// ── Password validator (SEC-010) ─────────────────────────────────────────
// Mirrors apps/mobile_app/lib/features/auth/presentation/password_policy.dart.
// Server-side validation in the admin_manage_user edge function is the
// authoritative gate; this is just a UX hint so admins don't submit a
// password the function will reject.
const _adminPwBanned = [
  'bsheel', 'bitsheel', 'password', 'qwerty', '123456', 'letmein',
];

String? _validateAdminResetPassword(String? v) {
  if (v == null || v.length < 10) return 'Min 10 characters';
  if (!RegExp(r'[A-Z]').hasMatch(v) ||
      !RegExp(r'[a-z]').hasMatch(v) ||
      !RegExp(r'[0-9]').hasMatch(v)) {
    return 'Mix uppercase, lowercase, and a digit';
  }
  final lower = v.toLowerCase();
  for (final banned in _adminPwBanned) {
    if (lower.contains(banned)) return 'Too common — pick something else';
  }
  return null;
}

// ── Helper Widgets ───────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final String? role;
  const _RoleBadge({this.role});

  @override
  Widget build(BuildContext context) {
    if (role == null) {
      return Text(
        'User',
        style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
      );
    }
    final (Color bg, Color fg, String label) = switch (role) {
      'super_admin' => (
        BsheelColors.hot.withAlpha(30),
        BsheelColors.hot,
        'SUPER ADMIN',
      ),
      'moderator' => (
        BsheelColors.cool.withAlpha(30),
        BsheelColors.cool,
        'MODERATOR',
      ),
      _ => (
        BsheelColors.inkMuted.withAlpha(30),
        BsheelColors.inkMuted,
        role!.toUpperCase(),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: QuestSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(BsheelRadii.full),
        border: Border.all(color: fg.withAlpha(80)),
      ),
      child: Text(
        label,
        style: BsheelType.labelSm.copyWith(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;

  const _MenuItem(this.icon, this.label, {this.isDestructive = false});

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? BsheelColors.hot : BsheelColors.pureWhite;
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: QuestSpacing.sm),
        Text(
          label,
          style: BsheelType.bodySm.copyWith(color: color),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: QuestSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: BsheelType.labelSm.copyWith(
                color: BsheelColors.inkMuted,
                letterSpacing: 1,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: BsheelType.bodySm.copyWith(color: BsheelColors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkRadioTile<T> extends StatelessWidget {
  final String title;
  final String subtitle;
  final T value;

  const _DarkRadioTile({
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<T>(
      title: Text(
        title,
        style: BsheelType.labelSm.copyWith(color: BsheelColors.ink),
      ),
      subtitle: Text(
        subtitle,
        style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
      ),
      value: value,
      activeColor: BsheelColors.primary,
    );
  }
}

// ── Assign Quest Dialog ───────────────────────────────────────────────────────

class _AssignQuestDialog extends StatefulWidget {
  const _AssignQuestDialog({
    required this.user,
    required this.client,
    required this.onAssigned,
    required this.onError,
  });

  final _UserRow user;
  final dynamic client;
  final VoidCallback onAssigned;
  final void Function(Object) onError;

  @override
  State<_AssignQuestDialog> createState() => _AssignQuestDialogState();
}

class _AssignQuestDialogState extends State<_AssignQuestDialog> {
  List<Map<String, dynamic>> _quests = [];
  String? _selectedQuestId;
  bool _loading = true;
  bool _assigning = false;

  @override
  void initState() {
    super.initState();
    _loadQuests();
  }

  Future<void> _loadQuests() async {
    try {
      final data = await widget.client
          .from(Tables.quests)
          .select('${QuestColumns.id}, ${QuestColumns.title}, ${QuestColumns.category}, ${QuestColumns.xpReward}')
          .eq(QuestColumns.isActive, true)
          .order(QuestColumns.title) as List<dynamic>;
      if (mounted) {
        setState(() {
          _quests = data.cast<Map<String, dynamic>>();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _assign() async {
    if (_selectedQuestId == null) return;
    setState(() => _assigning = true);
    try {
      // Force-expire any active quest so the RPC won't throw
      await widget.client
          .from(Tables.userQuests)
          .update({UserQuestColumns.status: 'expired'})
          .eq(UserQuestColumns.userId, widget.user.id)
          .inFilter(UserQuestColumns.status, ['assigned', 'submitted']);

      await widget.client.rpc(
        RpcNames.assignSpecificQuest,
        params: {
          'p_user_id': widget.user.id,
          'p_quest_id': _selectedQuestId,
        },
      );
      if (mounted) Navigator.pop(context);
      widget.onAssigned();
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        widget.onError(e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BsheelDialog(
      title: 'ASSIGN QUEST TO ${widget.user.displayName.toUpperCase()}',
      content: SizedBox(
        width: 460,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: BsheelColors.primary),
              )
            : _quests.isEmpty
                ? Text(
                    'No active quests available.',
                    style: BsheelType.bodySm
                        .copyWith(color: BsheelColors.inkMuted),
                  )
                : SizedBox(
                    height: 320,
                    child: ListView.separated(
                      itemCount: _quests.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: QuestSpacing.xs),
                      itemBuilder: (_, i) {
                        final q = _quests[i];
                        final qId = q[QuestColumns.id].toString();
                        final isSelected = _selectedQuestId == qId;
                        final category =
                            (q[QuestColumns.category] ?? '').toString();
                        final xp = q[QuestColumns.xpReward] ?? 0;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedQuestId = qId),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 120),
                            padding: const EdgeInsets.all(QuestSpacing.md),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? BsheelColors.primary.withAlpha(20)
                                  : BsheelColors.surface,
                              borderRadius:
                                  BorderRadius.circular(BsheelRadii.sm),
                              border: Border.all(
                                color: isSelected
                                    ? BsheelColors.primary
                                    : BsheelColors.ink,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  size: 16,
                                  color: isSelected
                                      ? BsheelColors.primary
                                      : BsheelColors.inkMuted,
                                ),
                                const SizedBox(width: QuestSpacing.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        q[QuestColumns.title].toString(),
                                        style:
                                            BsheelType.bodySm.copyWith(
                                          color: BsheelColors.ink,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        category.toUpperCase(),
                                        style:
                                            BsheelType.labelSm.copyWith(
                                          color: BsheelColors.inkMuted,
                                          fontSize: 9,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '+$xp XP',
                                  style: BsheelType.labelSm.copyWith(
                                    color: BsheelColors.accent,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'CANCEL',
            style: BsheelType.labelSm
                .copyWith(color: BsheelColors.inkMuted),
          ),
        ),
        ElevatedButton(
          onPressed: (_selectedQuestId == null || _assigning) ? null : _assign,
          style: ElevatedButton.styleFrom(
            backgroundColor: BsheelColors.primary,
            foregroundColor: BsheelColors.pureBlack,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.sm),
            ),
          ),
          child: _assigning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: BsheelColors.pureBlack,),
                )
              : Text(
                  'ASSIGN',
                  style:
                      BsheelType.labelSm.copyWith(color: BsheelColors.pureBlack),
                ),
        ),
      ],
    );
  }
}
