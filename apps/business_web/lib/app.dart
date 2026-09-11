import 'package:app_core/app_core.dart' show QuestTheme;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/business_router.dart';

/// The partner dashboard app.
///
/// Shares `QuestTheme.light` with the other two apps rather than inventing
/// a business skin: a partner should recognise the product their customers
/// use. Light only, like the rest of Bsheel — there is no dark theme.
class BusinessApp extends ConsumerWidget {
  const BusinessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Bsheel for Business',
      debugShowCheckedModeBanner: false,
      theme: QuestTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: ref.watch(businessRouterProvider),
    );
  }
}
