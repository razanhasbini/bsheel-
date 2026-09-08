import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_repositories/app_repositories.dart';

import '../../core/backend/app_backend.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AppBackend.repositories.auth;
});
