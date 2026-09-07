import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../../../../core/providers/supabase_provider.dart';
import 'pending_submissions_provider.dart';

class ModerationController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Approves [submission]. Publishes progress through [state] so the UI's
  /// busy indicator and error banner (which watch this notifier) actually
  /// reflect what happened. Returns true on success, false on failure —
  /// the failure message is available via `state.error`.
  Future<bool> approve(PendingSubmission submission) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final client = ref.read(supabaseClientProvider);
      // Atomic: the RPC re-verifies admin status, asserts current state is
      // 'pending' under FOR UPDATE, performs the status update, and writes
      // an admin_audit_log entry — all in one transaction. Replaces the
      // previous direct table UPDATE that relied solely on RLS.
      try {
        await client.rpc(
          RpcNames.adminApproveSubmission,
          params: {'p_submission_id': submission.id},
        );
      } catch (e) {
        throw ModerationException(mapModerationError(e, action: 'approve'));
      }
      ref.invalidate(pendingSubmissionsProvider);
    });
    return !state.hasError;
  }

  /// Rejects [submission] with [note]. Same [state] contract as [approve]:
  /// loading while in flight, error state on failure, true/false result.
  Future<bool> deny(PendingSubmission submission, String note) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final rejectionNote = note.trim();
      if (rejectionNote.isEmpty) {
        throw ModerationException('At least one rejection reason is required.');
      }

      final client = ref.read(supabaseClientProvider);
      try {
        await client.rpc(
          RpcNames.adminRejectSubmission,
          params: {
            'p_submission_id': submission.id,
            'p_review_note': rejectionNote,
          },
        );
      } catch (e) {
        throw ModerationException(mapModerationError(e, action: 'reject'));
      }
      ref.invalidate(pendingSubmissionsProvider);
    });
    return !state.hasError;
  }
}

/// Translate raw Postgres / network errors from the admin moderation RPCs
/// into short admin-facing strings the UI can put into a SnackBar.
/// Delegates to the shared mapper in app_core, with one moderation-
/// specific override for the "rejection note required" case.
///
/// Shared by [ModerationController] and the submission review page.
String mapModerationError(Object error, {required String action}) {
  final msg = error.toString();
  if (msg.contains('22023') || msg.contains('Rejection note is required')) {
    return 'A rejection note is required.';
  }
  return mapDbError(error, action: '$action submission');
}

/// Thrown by [ModerationController] when a server-side check fails. The
/// message is already user-facing — surface it directly in a SnackBar.
class ModerationException implements Exception {
  final String message;
  ModerationException(this.message);
  @override
  String toString() => message;
}

final moderationControllerProvider =
    AsyncNotifierProvider.autoDispose<ModerationController, void>(
      ModerationController.new,
    );
