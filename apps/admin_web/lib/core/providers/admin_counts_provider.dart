import 'dart:async';

import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_repositories/app_repositories.dart' show AdminRoleEnum;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/app_backend.dart';

/// Live admin sidebar badge counts.
///
/// Served by one `/admin/stats` round-trip and invalidated by realtime
/// submission/report events so the badges refresh without a manual reload.
class AdminCounts {
  final int pending;
  final int appeals;
  final int reports;

  const AdminCounts({
    required this.pending,
    required this.appeals,
    required this.reports,
  });

  const AdminCounts.zero()
      : pending = 0,
        appeals = 0,
        reports = 0;
}

final adminCountsProvider = FutureProvider<AdminCounts>((ref) async {
  final stats = await AppBackend.repositories.admin.stats();
  return AdminCounts(
    pending: (stats['pending'] as num?)?.toInt() ?? 0,
    appeals: (stats['appeals'] as num?)?.toInt() ?? 0,
    reports: (stats['pendingReports'] as num?)?.toInt() ?? 0,
  );
});

/// Realtime: on any submission or report event, invalidate
/// [adminCountsProvider] so the sidebar badges refresh. Watch this from the
/// shell.
final adminCountsRealtimeProvider = Provider.autoDispose<void>((ref) {
  final realtime = AppBackend.repositories.realtime;
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
  final repositories = AppBackend.repositories;
  final user = repositories.auth.currentUser;
  if (user == null) {
    return const AdminMeta(
      displayName: 'Admin',
      avatarUrl: null,
      roleLabel: 'ADMIN',
    );
  }
  final profile = await repositories.profiles.getProfile(user.id);
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
});
