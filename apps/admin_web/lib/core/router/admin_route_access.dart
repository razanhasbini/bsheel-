import 'package:app_repositories/app_repositories.dart' show AdminRoleEnum;

import 'admin_route_names.dart';

/// Which console destinations the API will actually serve to a moderator.
///
/// There are two admin roles and the backend enforces the difference with
/// `@Roles(...)` on its controllers. Most of the console is decorated
/// `@Roles('moderator', 'super_admin')`; a handful of areas are
/// `@Roles('super_admin')` alone, and a moderator who reached one of them
/// got a 403 on arrival — or, worse, a page that painted its chrome and
/// then failed the read behind it.
///
/// This is the single place that mapping is written down, so the router
/// and the sidebar cannot disagree about it. Each entry names the backend
/// endpoint that decides it:
///
/// | Destination | Endpoint | Decorator |
/// |---|---|---|
/// | `/quests` | `GET quests/admin/all` + the create/update/delete set | `@Roles('super_admin')` |
/// | `/destinations` | `GET/POST/PATCH map/admin/places` | `@Roles('super_admin')` |
/// | `/xp` | `GET admin/xp-audit`, `PATCH admin/users/:id/xp` | `@Roles('super_admin')` |
/// | `/settings` | `GET admin/config`, `PUT admin/config/:key` | `@Roles('super_admin')` |
/// | `/injection` | `POST admin/injections` is moderator-safe, but the quest picker reads `GET quests/admin/all` | `@Roles('super_admin')` |
///
/// Everything else — the moderation queue, appeals, history, feed, quest
/// of the day, users, announcements, auto notifications, reports, web
/// signups and quest suggestions — is served to either role, so it stays
/// visible to a moderator.
abstract final class AdminRouteAccess {
  /// Destinations whose backing endpoints are `@Roles('super_admin')`.
  static const Set<String> superAdminOnly = {
    AdminRoutePaths.questManagement,
    AdminRoutePaths.mapPlaces,
    AdminRoutePaths.xpManagement,
    AdminRoutePaths.settings,
    AdminRoutePaths.injection,
  };

  /// True when [path] — or anything nested under it — needs `super_admin`.
  ///
  /// Prefix-matched on a path segment boundary so a future `/quests/:id`
  /// is gated with `/quests` and `/quests-something-else` is not.
  static bool requiresSuperAdmin(String path) {
    for (final gated in superAdminOnly) {
      if (path == gated || path.startsWith('$gated/')) return true;
    }
    return false;
  }

  /// Whether an admin holding [role] may open [path].
  ///
  /// A null [role] is "not an admin, or not resolved yet" and is allowed
  /// nothing: the caller decides where to send them (the router bounces
  /// them to the login gate).
  static bool allows(String path, AdminRoleEnum? role) {
    if (role == null) return false;
    return role.isSuperAdmin || !requiresSuperAdmin(path);
  }
}
