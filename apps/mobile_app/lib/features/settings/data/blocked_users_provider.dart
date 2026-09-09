import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/app_backend.dart';

/// One blocked-user record, flattened to what both surfaces need.
typedef BlockedUser = ({
  String userId,
  String username,
  String displayName,
  String? avatarUrl,
});

/// Everyone the signed-in user has blocked.
///
/// Shared rather than page-private because the settings screen prints the
/// count on the "Blocked users" row (`export/mobile/21-settings.jpg` shows
/// `2 ›`) and the blocked-users page lists the same rows.
final blockedUsersProvider =
    FutureProvider.autoDispose<List<BlockedUser>>((ref) async {
  final users = await AppBackend.repositories.account.blockedUsers();
  return users
      .map((user) => (
            userId: user.id,
            username: user.username,
            displayName: user.displayName,
            avatarUrl: user.avatarUrl,
          ))
      .toList(growable: false);
});
