import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'bootstrap.dart';

void main() async {
  // Path URLs rather than hash, so the app works under the `/business`
  // base href it is deployed at.
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrap();
  runApp(const ProviderScope(child: BusinessApp()));
}
