import 'dart:async';

import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_repositories/nest_api_repositories.dart'
    show AdminRoleEnum;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_provider.dart';
import '../backend/admin_nest_backend.dart';
import '../backend/backend_config.dart';

/// Live admin sidebar badge counts.
///
/// One round-trip per badge — kept cheap with `count: CountOption.exact`
/// (no row data returned). Refreshed on every page navigation via the
/// shell's `Consumer` watch, plus invalidated by the realtime channel
/// in [adminCountsRealtimeProvider] when a row changes upstream.
class AdminCounts {
  final int pending;
  final int appeals;
  final int reports;

  const AdminCounts({
    required this.pending,
    required this.appeals,
    required this.reports,
  });

  const AdminCounts.zero() : pending = 0, appeals = 0, reports = 0;
}

final adminCountsProvider = FutureProvider<AdminCounts>((ref) async {
  if (BackendConfig.usesNest) {
    final stats = await AdminNestBackend.repositories.admin.stats();
    return AdminCounts(
      pending: (stats['pending'] as num?)?.toInt() ?? 0,
      appeals: (stats['appeals'] as num?)?.toInt() ?? 0,
      reports: (stats['pendingReports'] as num?)?.toInt() ?? 0,
    );
  }
  final client = ref.watch(supabaseClientProvider);

  final pending = await client
      .from(Tables.submissions)
      .select()
      .eq(SubmissionColumns.status, SubmissionStatus.pending)
      .count(CountOption.exact);
  final appeals = await client
      .from(Tables.submissions)
      .select()
      .eq(SubmissionColumns.status, SubmissionStatus.pending)
      .eq(SubmissionColumns.appealed, true)
      .count(CountOption.exact);
  final reports = await client
      .from(Tables.reports)
      .select()
      .eq('status', 'pending')
      .count(CountOption.exact);

  return AdminCounts(
    pending: pending.count,
    appeals: appeals.count,
    reports: reports.count,
  );
});

/// Realtime: on any change to `submissions` or `reports`, invalidate
/// [adminCountsProvider] so the sidebar badges refresh without a manual
/// reload. Watch this from the shell.
final adminCountsRealtimeProvider = Provider.autoDispose<void>((ref) {
  if (BackendConfig.usesNest) {
    final realtime = AdminNestBackend.repositories.realtime;
    final subscription = realtime.events.where((event) {
      return event.type.startsWith('submission.') ||
          event.type.startsWith('report.');
    }).listen((_) => ref.invalidate(adminCountsProvider));
    unawaited(() async {
      try {
        await realtime.connect();
      } catch (error) {
        AppLogger.warning('[AdminRealtime] Connection failed: $error');
      }
    }());
    ref.onDispose(() => unawaited(subscription.cancel()));
    return;
  }
  final client = Supabase.instance.client;

  final channel = client.channel('admin_sidebar_counts')
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: Tables.submissions,
      callback: (_) => ref.invalidate(adminCountsProvider),
    )
    ..onPostgresChanges(
      event: PostgresChangeEvent.all,
      schema: 'public',
      table: Tables.reports,
      callback: (_) => ref.invalidate(adminCountsProvider),
    )
    ..subscribe();

  ref.onDispose(() {
    client.removeChannel(channel);
  });
});

/// The signed-in admin's profile row. Powers the sidebar footer (avatar
/// initial, display name, role label) so it's the real user — not the
/// hardcoded "Admin / SUPER ADMIN" placeholder it shipped with.
class AdminMeta {
  final String displayName;
  final String? avatarUrl;
  final String roleLabel;

  const AdminMeta({
    required this.displayName,
    required this.avatarUrl,
    required this.roleLabel,
  });
}

final adminMetaProvider = FutureProvider<AdminMeta>((ref) async {
  if (BackendConfig.usesNest) {
    final repositories = AdminNestBackend.repositories;
    final user = repositories.auth.currentUser;
    if (user == null) {
      return const AdminMeta(
        displayName: 'Admin',
        avatarUrl: null,
        roleLabel: 'ADMIN',
      );
    }
    final profile = await repositories.profile.getProfile(user.id);
    final role = await repositories.admin.getCurrentUserRole();
    final displayName = profile?.displayName.trim();
    final username = profile?.username.trim();
    return AdminMeta(
      displayName: displayName?.isNotEmpty == true
          ? displayName!
          : username?.isNotEmpty == true
              ? username!
              : user.email?.split('@').first ?? 'Admin',
      avatarUrl: profile?.avatarUrl,
      roleLabel: switch (role) {
        AdminRoleEnum.superAdmin => 'SUPER ADMIN',
        AdminRoleEnum.moderator => 'MODERATOR',
        null => 'ADMIN',
      },
    );
  }
  final client = ref.watch(supabaseClientProvider);
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) {
    return const AdminMeta(
      displayName: 'Admin',
      avatarUrl: null,
      roleLabel: 'ADMIN',
    );
  }

  // Profile row for the display name + avatar.
  final profile = await client
      .from(Tables.profiles)
      .select('${ProfileColumns.username}, '
          '${ProfileColumns.displayName}, '
          '${ProfileColumns.avatarUrl}')
      .eq(ProfileColumns.id, user.id)
      .maybeSingle();

  // Admin role for the label below the name.
  final adminRow = await client
      .from(Tables.admins)
      .select(AdminColumns.role)
      .eq(AdminColumns.userId, user.id)
      .maybeSingle();

  String name = (profile?[ProfileColumns.displayName] as String?)?.trim() ?? '';
  if (name.isEmpty) {
    name = (profile?[ProfileColumns.username] as String?)?.trim() ?? '';
  }
  if (name.isEmpty) {
    name = user.email?.split('@').first ?? 'Admin';
  }

  final role = (adminRow?[AdminColumns.role] as String?) ?? 'admin';
  final roleLabel = role.toUpperCase().replaceAll('_', ' ');

  return AdminMeta(
    displayName: name,
    avatarUrl: profile?[ProfileColumns.avatarUrl] as String?,
    roleLabel: roleLabel,
  );
});
