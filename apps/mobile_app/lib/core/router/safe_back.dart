import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'route_names.dart';

/// UX-001: pops the current route if there's a stack to pop, otherwise
/// lands the user on `/home`.
///
/// Use this everywhere a top-of-stack page might be reached via deep
/// link / push notification cold-start — in those cases `context.pop()`
/// is a silent no-op (no Navigator history) and the user dead-ends on a
/// page with no escape. Wrapping the back button in `safeBack(context)`
/// closes that escape hatch.
///
/// `fallback` lets a caller route to a different shell tab when /home
/// isn't the right landing — e.g. profile-related pages can fall back
/// to /profile so the user lands somewhere relevant.
void safeBack(BuildContext context, {String? fallback}) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  context.goNamed(fallback ?? RouteNames.home);
}
