import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/admin_role_provider.dart';
import '../providers/repository_providers.dart';
import 'admin_nest_backend.dart';

/// Central Nest overrides for providers already expressed through contracts.
List<Override> adminNestRepositoryOverrides() {
  final repositories = AdminNestBackend.repositories;
  return [
    authRepositoryProvider.overrideWithValue(repositories.auth),
    adminRepositoryProvider.overrideWithValue(repositories.admin),
  ];
}
