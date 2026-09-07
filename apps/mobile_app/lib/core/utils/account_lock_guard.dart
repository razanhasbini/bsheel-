import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/account_status_provider.dart';

/// Returns true if the current account is suspended or banned.
///
/// Read-only — does NOT show UI. Pair with [showAccountLockedSnackbar]
/// at action call sites, or use [guardAccountAction] for the common
/// "block + toast + return false" pattern.
bool isAccountLocked(WidgetRef ref) {
  final status = ref.read(accountStatusProvider).valueOrNull;
  return status == 'suspended' || status == 'banned';
}

/// Show a one-line "your account is locked" snackbar with the right copy
/// for `suspended` vs `banned`. Safe to call from any action handler.
void showAccountLockedSnackbar(BuildContext context, String? status) {
  final isBanned = status == 'banned';
  final msg = isBanned
      ? 'Your account is banned. This action is disabled.'
      : 'Your account is suspended. This action is paused until review.';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Combined check: if the account is locked, show the snackbar and
/// return true so the caller can early-return. Use at the very top of
/// every async action that mutates server state (post, vote, follow,
/// comment, accept quest, edit profile, join collab, mark read, etc.).
///
/// ```dart
/// Future<void> _onTap() async {
///   if (guardAccountAction(context, ref)) return;
///   await doTheThing();
/// }
/// ```
bool guardAccountAction(BuildContext context, WidgetRef ref) {
  final status = ref.read(accountStatusProvider).valueOrNull;
  if (status != 'suspended' && status != 'banned') return false;
  showAccountLockedSnackbar(context, status);
  return true;
}
