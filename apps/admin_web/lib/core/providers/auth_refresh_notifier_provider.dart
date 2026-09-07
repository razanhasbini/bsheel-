import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_refresh_notifier.dart';
import 'repository_providers.dart';

final authRefreshNotifierProvider = Provider<AuthRefreshNotifier>((ref) {
  final notifier = AuthRefreshNotifier(ref.watch(authRepositoryProvider));
  ref.onDispose(notifier.dispose);
  return notifier;
});
