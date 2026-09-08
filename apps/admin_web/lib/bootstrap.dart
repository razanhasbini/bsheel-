import 'package:app_core/app_core.dart' show AppLogger;

import 'core/backend/app_backend.dart';

Future<void> bootstrap() async {
  await AppBackend.initialize();
  AppLogger.info('[Bootstrap] API backend initialized');
}
