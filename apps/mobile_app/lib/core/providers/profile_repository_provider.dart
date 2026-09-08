import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_repositories/app_repositories.dart';
import '../../core/backend/app_backend.dart';

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return AppBackend.repositories.profiles;
});
