import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'package:app_core/app_core.dart';
import 'package:app_repositories/app_repositories.dart' show AdminRoleEnum;
import 'package:excel/excel.dart' as xl;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:app_contracts/app_contracts.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/router/admin_route_names.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

// ── Providers ────────────────────────────────────────────────────────────────

/// One request returns the profile fields, the account email/status and the
/// admin role together, with avatars already signed — the page previously
/// issued three separate calls to assemble the same rows.
final usersProvider = FutureProvider.autoDispose<List<_UserRow>>((ref) async {
  final rows = await AppBackend.repositories.admin.users(limit: 200);
  return rows.map((row) {
    return _UserRow(
      id: row['id']?.toString() ?? '',
      username: row['username']?.toString() ?? '',
      displayName: row['display_name']?.toString() ?? '',
      avatarUrl: row['avatar_url']?.toString(),
      bio: row['bio']?.toString(),
      email: row['email']?.toString(),
      accountStatus:
          row['account_status']?.toString() ?? _AccountStatus.active,
      xp: (row['xp'] as num?)?.toInt() ?? 0,
      level: (row['level'] as num?)?.toInt() ?? 1,
      questsCompleted: (row['quests_completed'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
      adminRole: row['admin_role']?.toString(),
    );
  }).toList();
});

/// Values of the `account_status` Postgres enum, as returned by
/// `admin/users`. `app_contracts` has no class for them yet, so they are
/// named once here instead of being repeated as literals at every call
/// site — see the report note.
abstract final class _AccountStatus {
  static const String active = 'active';
  static const String suspended = 'suspended';
  static const String banned = 'banned';
}

class _UserRow {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String? bio;
  final String? email;
  final String accountStatus;
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
    this.email,
    this.accountStatus = _AccountStatus.active,
    required this.xp,
    required this.level,
    required this.questsCompleted,
    this.createdAt,
    this.adminRole,
  });

  bool get isAdmin => adminRole != null;
  bool get isSuperAdmin => adminRole == AdminRole.superAdmin;
  bool get isModerator => adminRole == AdminRole.moderator;

  /// Suspended and banned accounts read as retired rows: muted table row,
  /// muted numerals, lavender avatar.
  bool get isRestricted => accountStatus != _AccountStatus.active;

  /// What the moderator searches by — the header hint promises both.
  String get haystack =>
      '$username $displayName ${email ?? ''}'.toLowerCase();
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
  /// The filter row: `all` plus the three account statuses.
  static const String _fAll = 'all';

  /// Below this the rail cannot sit beside the table, so the page stacks
  /// with the rail first — a selection has to stay visible.
  static const double _railBreakpoint = 1100;

  /// Five columns need this much room; narrower than that the table
  /// scrolls sideways inside the page rather than painting outside it.
  static const double _minTableWidth = 520;

  late final TextEditingController _searchCtrl =
      TextEditingController(text: widget.initialQuery ?? '');
  late String _search = (widget.initialQuery ?? '').toLowerCase();
  String _statusFilter = _fAll;
  String? _selectedId;

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
    final loaded = usersAsync.valueOrNull ?? const <_UserRow>[];

    return AdminPage(
      title: 'Users',
      actions: [
        BsheelSearchField(
          controller: _searchCtrl,
          hint: 'Search username or email…',
          width: 230,
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
        ),
      ],
      subheader: LayoutBuilder(
        builder: (context, c) {
          final chips = BsheelFilterChips(
            selected: _statusFilter,
            onChanged: (v) => setState(() => _statusFilter = v),
            filters: [
              BsheelFilter(
                _fAll,
                'All',
                count: loaded.length,
                ground: BsheelColors.card,
              ),
              BsheelFilter(
                _AccountStatus.active,
                'Active',
                count: _countOf(loaded, _AccountStatus.active),
                ground: BsheelColors.card,
              ),
              BsheelFilter(
                _AccountStatus.suspended,
                'Suspended',
                count: _countOf(loaded, _AccountStatus.suspended),
                ground: BsheelColors.accent,
              ),
              BsheelFilter(
                _AccountStatus.banned,
                'Banned',
                count: _countOf(loaded, _AccountStatus.banned),
                ground: BsheelColors.danger,
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BsheelButton.ghost(
                label: 'Export',
                icon: Icons.file_download_rounded,
                small: true,
                // Nothing to export until the list is on screen, and a
                // button that cannot act says so by losing its shadow.
                onPressed:
                    loaded.isEmpty ? null : () => _exportToExcel(loaded),
              ),
              BsheelButton.primary(
                label: 'Add user',
                icon: Icons.person_add_rounded,
                small: true,
                onPressed: () => _showCreateUserDialog(context),
              ),
            ],
          );
          if (c.maxWidth < 620) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                chips,
                const SizedBox(height: QuestSpacing.sm),
                actions,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: chips),
              const SizedBox(width: QuestSpacing.md),
              actions,
            ],
          );
        },
      ),
      child: usersAsync.when(
        loading: () => const BsheelLoadingList(rows: 6, rowHeight: 46),
        error: (e, _) => BsheelErrorState(
          title: 'Users didn’t load',
          message: 'The account list didn’t come back, so no account is on '
              'screen. Nothing was changed — this page only reads until you '
              'act on a row. $e',
          onRetry: () => ref.invalidate(usersProvider),
        ),
        data: (users) => _body(context, users),
      ),
    );
  }

  static int _countOf(List<_UserRow> users, String status) =>
      users.where((u) => u.accountStatus == status).length;

  // ── Body: table on the left, 300px detail rail on the right ─────────

  Widget _body(BuildContext context, List<_UserRow> users) {
    if (users.isEmpty) {
      return BsheelEmptyState(
        title: 'No accounts yet',
        message: 'Nobody has signed up, so there is nothing to moderate. '
            'Create the first account to get started.',
        actionLabel: 'Add a user',
        onAction: () => _showCreateUserDialog(context),
      );
    }

    final filtered = _visible(users);
    final selected = _selected(users);

    return LayoutBuilder(
      builder: (context, c) {
        final stacked = c.maxWidth < _railBreakpoint;
        // 300 rail + 18 gutter.
        final tableWidth = stacked ? c.maxWidth : c.maxWidth - 318;

        Widget tableSide;
        if (filtered.isEmpty) {
          tableSide = BsheelEmptyState(
            title: 'No match',
            message: 'No account matches this filter and search. Clear them '
                'both to see every account again.',
            actionLabel: 'Clear filters',
            onAction: () {
              _searchCtrl.clear();
              setState(() {
                _search = '';
                _statusFilter = _fAll;
              });
            },
          );
        } else {
          tableSide = _table(filtered);
          if (tableWidth < _minTableWidth) {
            tableSide = SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: _minTableWidth, child: tableSide),
            );
          }
        }

        final rail = _rail(context, selected);

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              rail,
              const SizedBox(height: QuestSpacing.lg),
              tableSide,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: tableSide),
            const SizedBox(width: QuestSpacing.lg),
            SizedBox(width: 300, child: rail),
          ],
        );
      },
    );
  }

  List<_UserRow> _visible(List<_UserRow> users) {
    return users.where((u) {
      if (_statusFilter != _fAll && u.accountStatus != _statusFilter) {
        return false;
      }
      if (_search.isEmpty) return true;
      return u.haystack.contains(_search);
    }).toList(growable: false);
  }

  /// Resolved against the whole list, not the filtered one, so changing a
  /// filter never silently drops the moderator's selection.
  _UserRow? _selected(List<_UserRow> users) {
    final id = _selectedId;
    if (id == null) return null;
    for (final u in users) {
      if (u.id == id) return u;
    }
    return null;
  }

  // ── Table ───────────────────────────────────────────────────────────

  Widget _table(List<_UserRow> rows) {
    return BsheelTable(
      depth: 5,
      columns: const [
        BsheelColumn('User'),
        BsheelColumn('Level', width: 74),
        BsheelColumn('XP', width: 92),
        BsheelColumn('Quests', width: 92),
        BsheelColumn('Status', width: 108),
      ],
      rows: [
        for (final u in rows)
          BsheelRow(
            [
              _userCell(u),
              BsheelCell.mono(
                '${u.level}',
                color: u.isRestricted ? BsheelColors.inkMuted : null,
              ),
              BsheelCell.mono(
                _grouped(u.xp),
                bold: false,
                color: u.isRestricted ? BsheelColors.inkMuted : null,
              ),
              BsheelCell.mono(
                _grouped(u.questsCompleted),
                bold: false,
                color: u.isRestricted ? BsheelColors.inkMuted : null,
              ),
              BsheelCell.pill(BsheelPill.status(u.accountStatus)),
            ],
            muted: u.isRestricted,
            onTap: () => setState(() => _selectedId = u.id),
          ),
      ],
    );
  }

  Widget _userCell(_UserRow u) {
    final name = u.username.isEmpty ? u.displayName : u.username;
    return Row(
      children: [
        BsheelAvatar(
          url: u.avatarUrl,
          initial: name.isEmpty ? '?' : name[0],
          size: 30,
          // Lavender is the system's retired tint; sky is informational.
          ground: u.isRestricted ? BsheelColors.lavender : BsheelColors.cool,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            name.isEmpty ? '—' : name,
            style: BsheelType.titleMd.copyWith(
              color: u.isRestricted ? BsheelColors.inkSoft : BsheelColors.ink,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ── Detail rail ─────────────────────────────────────────────────────

  Widget _rail(BuildContext context, _UserRow? user) {
    if (user == null) {
      return const BsheelEmptyState(
        title: 'No user picked',
        message: 'Pick a user in the table and their account opens here, '
            'with the two actions that change it.',
      );
    }

    final name = user.username.isEmpty ? user.displayName : user.username;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'SELECTED · $name',
          style: BsheelType.labelMd,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (user.adminRole != null) ...[
          const SizedBox(height: QuestSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: _RoleBadge(role: user.adminRole),
          ),
        ],
        const SizedBox(height: QuestSpacing.md),
        BsheelKeyValues(
          depth: 4,
          // The rail is the focus of this page, so it takes the one
          // coloured shadow on screen.
          shadowColor: BsheelColors.primary,
          entries: [
            BsheelKeyValue('Joined', _joinedLabel(user.createdAt)),
            // The admin user list carries no moderation counters yet, so
            // these three read as unknown rather than as zero.
            const BsheelKeyValue('Approval rate', '—'),
            const BsheelKeyValue('Reports against', '—'),
            const BsheelKeyValue('Blocks received', '—'),
          ],
        ),
        const SizedBox(height: QuestSpacing.md),
        BsheelButton.ghost(
          label: 'View submissions',
          small: true,
          expand: true,
          onPressed: () =>
              context.goNamed(AdminRouteNames.submissionHistory),
        ),
        const SizedBox(height: QuestSpacing.sm),
        BsheelButton.gold(
          label: 'Suspend',
          small: true,
          expand: true,
          onPressed: () => _confirmStatusChange(
            context,
            user,
            _AccountStatus.suspended,
          ),
        ),
        const SizedBox(height: QuestSpacing.sm),
        BsheelButton.coral(
          label: 'Ban account',
          small: true,
          expand: true,
          onPressed: () => _confirmStatusChange(
            context,
            user,
            _AccountStatus.banned,
          ),
        ),
        const SizedBox(height: QuestSpacing.sm),
        BsheelButton.ghost(
          label: 'More actions',
          small: true,
          expand: true,
          onPressed: () => _showMoreActions(context, user),
        ),
        const SizedBox(height: QuestSpacing.md),
        Text(
          'SUSPENDING HIDES THE QOTD TICKET AND BLOCKS NEW QUESTS. '
          'BOTH ACTIONS ARE AUDITED.',
          style: BsheelType.labelSm.copyWith(
            color: BsheelColors.inkMuted,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// Everything the row menu used to carry. The rail shows the two
  /// account-status actions the design draws; the rest live one tap away
  /// so no behaviour is lost.
  void _showMoreActions(BuildContext context, _UserRow user) {
    final name = user.username.isEmpty ? user.displayName : user.username;

    Widget action(String value, String label, IconData icon) => Padding(
          padding: const EdgeInsets.only(bottom: QuestSpacing.sm),
          child: BsheelButton.ghost(
            label: label,
            icon: icon,
            small: true,
            expand: true,
            onPressed: () {
              Navigator.pop(context);
              _handleAction(context, value, user);
            },
          ),
        );

    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Actions · $name',
        maxWidth: 360,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 380),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                action('view', 'View details', Icons.visibility_rounded),
                action('edit', 'Edit profile', Icons.edit_rounded),
                action(
                  'assign_quest',
                  'Assign quest',
                  Icons.assignment_rounded,
                ),
                action(
                  'send_notification',
                  'Send notification',
                  Icons.notifications_rounded,
                ),
                action('role', 'Manage role', Icons.shield_rounded),
                action(
                  'reset_pw',
                  'Reset password',
                  Icons.lock_reset_rounded,
                ),
                action(
                  'activate',
                  'Activate account',
                  Icons.check_circle_rounded,
                ),
                BsheelButton.coral(
                  label: 'Delete user',
                  icon: Icons.delete_rounded,
                  small: true,
                  expand: true,
                  onPressed: () {
                    Navigator.pop(ctx);
                    _handleAction(context, 'delete', user);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Close',
            small: true,
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
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
        _confirmStatusChange(context, user, _AccountStatus.suspended);
      case 'ban':
        _confirmStatusChange(context, user, _AccountStatus.banned);
      case 'activate':
        // Restorative action — no confirmation needed.
        _setAccountStatus(user.id, _AccountStatus.active, user.displayName);
      case 'delete':
        _confirmDelete(context, user);
    }
  }

  Future<void> _setAccountStatus(
      String userId, String status, String name) async {
    try {
      await AppBackend.repositories.admin.setAccountStatus(
        userId,
        status,
        'Changed from the admin users page',
      );
      ref.invalidate(usersProvider);
      if (mounted) {
        final label = status == _AccountStatus.active
            ? 'activated'
            : status == _AccountStatus.suspended
                ? 'suspended'
                : 'banned';
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
        title: user.displayName,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DetailRow('Username', '@${user.username}'),
                _DetailRow('Display name', user.displayName, mono: false),
                _DetailRow('Email', user.email ?? '—'),
                _DetailRow('Status', user.accountStatus),
                _DetailRow('User id', user.id),
                _DetailRow('XP', '${user.xp}'),
                _DetailRow('Level', '${user.level}'),
                _DetailRow('Quests completed', '${user.questsCompleted}'),
                _DetailRow('Bio', user.bio ?? '—', mono: false),
                _DetailRow('Role', user.adminRole ?? 'Regular user'),
                _DetailRow('Joined', _joinedLabel(user.createdAt)),
              ],
            ),
          ),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Close',
            small: true,
            onPressed: () => Navigator.pop(ctx),
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
        title: 'Edit ${user.displayName}',
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BsheelFormField(
                    controller: usernameCtrl,
                    label: 'Username',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: displayNameCtrl,
                    label: 'Display name',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: bioCtrl,
                    label: 'Bio',
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
                          label: 'Level',
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
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx),
          ),
          BsheelButton.primary(
            label: 'Save',
            small: true,
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
    try {
      // One audited request: a rename and an XP correction saved together
      // either both apply or neither does.
      await AppBackend.repositories.admin.updateUserProfile(
        userId,
        username: username,
        displayName: displayName,
        bio: bio,
        xp: xp,
        level: level,
        reason: 'Edited from the admin users page',
      );
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
          title: 'Manage role: ${user.displayName}',
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const BsheelLabel('Current role'),
                    const SizedBox(width: QuestSpacing.sm),
                    _RoleBadge(role: user.adminRole),
                  ],
                ),
                const SizedBox(height: QuestSpacing.md),
                RadioGroup<String?>(
                  groupValue: selectedRole,
                  onChanged: (v) => setDialogState(() => selectedRole = v),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _RoleRadioTile<String?>(
                        title: 'Regular user',
                        subtitle: 'No admin privileges',
                        value: null,
                      ),
                      _RoleRadioTile<String?>(
                        title: 'Moderator',
                        subtitle: 'Can review submissions',
                        value: AdminRole.moderator,
                      ),
                      _RoleRadioTile<String?>(
                        title: 'Super admin',
                        subtitle: 'Full admin access',
                        value: AdminRole.superAdmin,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: QuestSpacing.md),
                // The audit note: a role change is recorded against the
                // moderator who made it, and cannot be made quietly.
                const BsheelCallout(
                  'Granting or removing an admin role is written to the '
                  'audit log against your account.',
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
            BsheelButton.primary(
              label: 'Save',
              small: true,
              onPressed: () async {
                Navigator.pop(ctx);
                await _setRole(user.id, selectedRole);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setRole(String userId, String? role) async {
    try {
      await AppBackend.repositories.admin.setRole(
        userId,
        AdminRoleEnum.fromDbString(role),
      );
      ref.invalidate(usersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              role != null ? 'Role updated to $role.' : 'Admin role removed.',
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
        title: 'Reset password: ${user.displayName}',
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Form(
            key: formKey,
            child: BsheelFormField(
              controller: pwCtrl,
              label: 'New password',
              // SEC-010: mirror the policy used everywhere else
              // (≥10 chars, mix of upper/lower/digit, no banned
              // substrings). The edge function re-validates on
              // submit so this is purely a UX hint.
              validator: _validateAdminResetPassword,
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
            label: 'Reset',
            small: true,
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              await _resetPassword(user.id, pwCtrl.text);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _resetPassword(String userId, String newPassword) async {
    try {
      await AppBackend.repositories.admin
          .forceResetPassword(userId, newPassword);
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
      _AccountStatus.banned => (
          'Ban user',
          'ban',
          'They will be locked out of the app until reactivated.',
        ),
      _ => (
          'Suspend user',
          'suspend',
          'They will be temporarily locked out until reactivated.',
        ),
    };

    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: title,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Are you sure you want to $verb "${user.displayName}" '
              '(@${user.username})?',
              style: BsheelType.bodySm,
            ),
            const SizedBox(height: QuestSpacing.md),
            BsheelCallout.danger('$consequence This is audited.'),
          ],
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx),
          ),
          BsheelButton.coral(
            label: verb,
            small: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await _setAccountStatus(user.id, status, user.displayName);
            },
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, _UserRow user) {
    showDialog<void>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Delete user',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Are you sure you want to delete "${user.displayName}" '
              '(@${user.username})?',
              style: BsheelType.bodySm,
            ),
            const SizedBox(height: QuestSpacing.md),
            const BsheelCallout.danger(
              'This permanently removes their account, profile, quests and '
              'submissions. It cannot be undone.',
            ),
          ],
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
              await _deleteUser(user.id);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _deleteUser(String userId) async {
    try {
      await AppBackend.repositories.admin.deleteUser(userId);
      ref.invalidate(usersProvider);
      if (mounted) {
        setState(() {
          if (_selectedId == userId) _selectedId = null;
        });
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
    showDialog<void>(
      context: context,
      builder: (ctx) => _AssignQuestDialog(
        user: user,
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
        title: 'Notify ${user.displayName}',
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BsheelFormField(
                  controller: titleCtrl,
                  label: 'Title',
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: QuestSpacing.md),
                BsheelFormField(
                  controller: bodyCtrl,
                  label: 'Message',
                  maxLines: 3,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Required' : null,
                ),
              ],
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
            label: 'Send',
            small: true,
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx);
              await _sendNotification(
                user.id,
                titleCtrl.text.trim(),
                bodyCtrl.text.trim(),
              );
            },
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
    try {
      // The API writes the inbox row and enqueues push delivery to every
      // registered device in one transaction. The client no longer reads
      // device tokens — they are encrypted at rest and server-only.
      final devices = await AppBackend.repositories.admin.sendNotification(
        targetUserId: userId,
        title: title,
        body: body,
        type: 'announcement',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              devices > 0
                  ? 'Notification sent (push + in-app).'
                  : 'Notification stored (user has no registered device).',
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
        title: 'Create new user',
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BsheelFormField(
                    controller: emailCtrl,
                    label: 'Email',
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!v.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: passwordCtrl,
                    label: 'Password',
                    // Same SEC-010 policy as admin password resets:
                    // ≥10 chars + upper/lower/digit, no banned substrings.
                    validator: _validateAdminResetPassword,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: usernameCtrl,
                    label: 'Username',
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: QuestSpacing.md),
                  BsheelFormField(
                    controller: displayNameCtrl,
                    label: 'Display name (optional)',
                  ),
                ],
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
            label: 'Create',
            small: true,
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
    try {
      await AppBackend.repositories.admin.createUser(
        email: email,
        password: password,
        username: username,
        displayName: displayName.isEmpty ? username : displayName,
      );
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
      sheet.appendRow(
          headers.map<xl.CellValue>((h) => xl.TextCellValue(h)).toList());

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
      final stamp =
          '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}'
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
          SnackBar(
              content: Text('Exported ${users.length} users to $filename')),
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

// ── Formatting ───────────────────────────────────────────────────────────

const List<String> _monthLabels = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `04 Mar 25` — the rail's date shape.
String _joinedLabel(DateTime? dt) {
  if (dt == null) return '—';
  final d = dt.toLocal();
  return '${d.day.toString().padLeft(2, '0')} '
      '${_monthLabels[d.month - 1]} '
      '${(d.year % 100).toString().padLeft(2, '0')}';
}

/// Thousands separators, so `18420` reads as `18,420` in a mono column.
String _grouped(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}

// ── Password validator (SEC-010) ─────────────────────────────────────────
// Mirrors apps/mobile_app/lib/features/auth/presentation/password_policy.dart.
// Server-side validation in the admin_manage_user edge function is the
// authoritative gate; this is just a UX hint so admins don't submit a
// password the function will reject.
const _adminPwBanned = [
  'bsheel',
  'bitsheel',
  'password',
  'qwerty',
  '123456',
  'letmein',
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

/// Admin role as a status pill. Violet is the elevated privilege, sky is
/// the informational one; a regular account has no badge to draw.
class _RoleBadge extends StatelessWidget {
  final String? role;
  const _RoleBadge({this.role});

  @override
  Widget build(BuildContext context) {
    final role0 = role;
    if (role0 == null) {
      return Text(
        'Regular user',
        style: BsheelType.bodySm.copyWith(color: BsheelColors.inkMuted),
      );
    }
    final (BsheelPillTone tone, String label) = switch (role0) {
      AdminRole.superAdmin => (BsheelPillTone.violet, 'super admin'),
      AdminRole.moderator => (BsheelPillTone.sky, 'moderator'),
      _ => (BsheelPillTone.paper, role0.replaceAll('_', ' ')),
    };
    return BsheelPill(label, tone: tone);
  }
}

/// Dialog detail line: tracked mono key, selectable value. A user id is
/// long and has no break points, so the value wraps rather than running
/// past the dialog edge.
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final bool mono;

  const _DetailRow(this.label, this.value, {this.mono = true});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: QuestSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 140, child: BsheelLabel(label)),
          const SizedBox(width: QuestSpacing.sm),
          Expanded(
            child: SelectableText(
              value,
              style: mono ? BsheelType.monoMd : BsheelType.bodySm,
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleRadioTile<T> extends StatelessWidget {
  final String title;
  final String subtitle;
  final T value;

  const _RoleRadioTile({
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return RadioListTile<T>(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: BsheelType.bodySmMedium),
      subtitle: Text(
        subtitle,
        style: BsheelType.bodyXs,
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
    required this.onAssigned,
    required this.onError,
  });

  final _UserRow user;
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
      final quests = await AppBackend.repositories.quests.listAllQuestsAdmin();
      if (mounted) {
        setState(() {
          _quests = quests
              .where((quest) => quest.isActive)
              .map((quest) => {
                    'id': quest.id,
                    'title': quest.title,
                    'category': quest.category,
                    'xp_reward': quest.xpReward,
                  })
              .toList()
            ..sort((a, b) =>
                (a['title'] as String).compareTo(b['title'] as String));
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
      // One request: the API expires any in-flight quest and assigns the
      // new one in the same transaction.
      await AppBackend.repositories.quests.assignQuestToUser(
        widget.user.id,
        _selectedQuestId!,
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
      title: 'Assign quest to ${widget.user.displayName}',
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: _loading
            ? const BsheelLoadingList(rows: 4, rowHeight: 52)
            : _quests.isEmpty
                ? const BsheelEmptyState(
                    title: 'No active quests',
                    message: 'There is no active quest to assign. Activate '
                        'one in quest management first.',
                  )
                : SizedBox(
                    height: 320,
                    child: ListView.separated(
                      itemCount: _quests.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: QuestSpacing.sm),
                      itemBuilder: (_, i) {
                        final q = _quests[i];
                        final qId = q[QuestColumns.id].toString();
                        final isSelected = _selectedQuestId == qId;
                        final category =
                            (q[QuestColumns.category] ?? '').toString();
                        final xp = q[QuestColumns.xpReward] ?? 0;
                        return BsheelCard(
                          padding: const EdgeInsets.all(11),
                          // The violet shadow marks the one row that is
                          // selected; the rest sit flat.
                          depth: isSelected ? 3 : 0,
                          shadowColor: BsheelColors.primary,
                          color: isSelected
                              ? BsheelColors.card
                              : BsheelColors.surface,
                          onTap: () =>
                              setState(() => _selectedQuestId = qId),
                          child: Row(
                            children: [
                              Icon(
                                isSelected
                                    ? Icons.check_circle_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                size: 18,
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
                                      style: BsheelType.titleSm,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (category.isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      BsheelTag.category(category),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: QuestSpacing.sm),
                              Text(
                                '+$xp XP',
                                style: BsheelType.monoSm.copyWith(
                                  color: BsheelColors.accentText,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
      ),
      actions: [
        BsheelButton.ghost(
          label: 'Cancel',
          small: true,
          onPressed: () => Navigator.pop(context),
        ),
        BsheelButton.primary(
          label: 'Assign',
          small: true,
          loading: _assigning,
          onPressed: (_selectedQuestId == null || _assigning) ? null : _assign,
        ),
      ],
    );
  }
}
