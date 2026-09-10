import 'package:app_repositories/app_repositories.dart' show ApiException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

/// The whole queue in one read. The server orders it unhandled-first,
/// oldest of those at the top, and caps the page at 200 — so the list
/// arrives already in the order an operator should work it.
final deletionRequestsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return AppBackend.repositories.admin.deletionRequests();
});

// ── Page ──────────────────────────────────────────────────────────────────────

/// The operator surface over `public_deletion_requests`.
///
/// Rows arrive from the signed-out compliance page at `/delete-account`,
/// which records the request and deliberately erases nothing — an
/// unauthenticated endpoint that deleted an account by email address
/// would let anyone erase anyone. Until this page existed there was no
/// way to see the queue at all, so GDPR/CCPA erasure requests landed in
/// a table nobody read and quietly missed their statutory deadline.
///
/// This page cannot erase an account either, and that is the point. It
/// tells the operator who is waiting, how long they have waited, and
/// whether the address matches an account; the erasure itself runs
/// through the authenticated account flow, which needs the account
/// holder's own session.
class DeletionRequestsPage extends ConsumerStatefulWidget {
  const DeletionRequestsPage({super.key});

  @override
  ConsumerState<DeletionRequestsPage> createState() =>
      _DeletionRequestsPageState();
}

class _DeletionRequestsPageState extends ConsumerState<DeletionRequestsPage> {
  /// The row currently being marked handled, so only its own button
  /// shows a spinner instead of the whole table locking up.
  String? _working;

  Future<void> _markHandled(Map<String, dynamic> row) async {
    final email = _email(row);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BsheelColors.paper,
        title: const Text(
          'MARK AS HANDLED?',
          style: TextStyle(color: BsheelColors.ink, letterSpacing: 1.5),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                email,
                style: BsheelType.monoMd.copyWith(color: BsheelColors.ink),
              ),
              const SizedBox(height: 12),
              // Said plainly, because the button does not do what its
              // name suggests to someone who has not read the table's
              // comment. Marking handled is a signature, not an action.
              const Text(
                'This records that you verified the requester and took the '
                'request on. It does not delete anything — run the erasure '
                'through the account holder’s own signed-in flow, then come '
                'back and mark this handled.',
                style: TextStyle(color: BsheelColors.inkSoft),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your name and the time are stored on the row and appended to '
                'the audit log.',
                style: TextStyle(color: BsheelColors.inkSoft),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: BsheelColors.ink,
              foregroundColor: BsheelColors.paper,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('MARK HANDLED'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _working = row['id']?.toString());
    try {
      await AppBackend.repositories.admin
          .markDeletionRequestHandled(row['id'].toString());
      ref.invalidate(deletionRequestsProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Marked handled: $email')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nothing was recorded: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deletionRequestsProvider);
    final rows = async.valueOrNull;
    final pending = rows?.where(_isPending).length;

    return AdminPage(
      title: 'Deletion requests',
      meta: pending == null ? 'Erasure queue' : '$pending waiting',
      metaColor:
          (pending ?? 0) > 0 ? BsheelColors.dangerText : BsheelColors.inkSoft,
      child: async.when(
        loading: () => const BsheelLoadingList(rows: 6, rowHeight: 44),
        error: (e, _) => _errorState(e),
        data: (data) {
          if (data.isEmpty) {
            return BsheelEmptyState.allClear(
              message: 'Nobody has asked to be erased from the public '
                  'delete-account page. Requests appear here the moment they '
                  'are submitted.',
              actionLabel: 'Reload',
              onAction: () => ref.invalidate(deletionRequestsProvider),
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const BsheelCallout.warning(
                'These are statutory erasure requests. Verify the requester’s '
                'identity, run the deletion through their signed-in account, '
                'then mark the row handled. Nothing on this page deletes an '
                'account — it cannot, because anyone can type any address '
                'into the public form.',
              ),
              const SizedBox(height: 14),
              BsheelTable(
                depth: 4,
                columns: const [
                  BsheelColumn('Email'),
                  BsheelColumn('Account', width: 150),
                  BsheelColumn('Requested', width: 108),
                  BsheelColumn('Status', width: 108),
                  BsheelColumn('Handled by', width: 170),
                  BsheelColumn('', width: 132),
                ],
                rows: [
                  for (final row in data)
                    BsheelRow(
                      [
                        BsheelCell.mono(_email(row)),
                        _accountCell(row),
                        BsheelCell.meta(_waiting(row)),
                        BsheelCell.pill(
                          BsheelPill.status(
                            _isPending(row) ? 'pending' : 'handled',
                          ),
                        ),
                        BsheelCell.meta(_handledBy(row)),
                        _actionCell(row),
                      ],
                      muted: !_isPending(row),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _errorState(Object error) {
    // A moderator who reaches this page gets a 403 from the server. Say
    // so, rather than showing them a red panel that reads like an
    // outage: this list is personal data about people who may not even
    // have an account, so super_admin only is deliberate.
    if (error is ApiException && error.statusCode == 403) {
      return const BsheelEmptyState(
        title: 'Super admins only',
        message: 'This queue holds the email addresses of people asking to be '
            'erased, so it is restricted to super admins. Ask one of them to '
            'work the queue.',
      );
    }
    return BsheelErrorState(
      title: 'Queue didn’t load',
      message: 'The erasure queue didn’t come back, so nothing is shown '
          'rather than a stale list. No request was lost and none was marked '
          'handled. $error',
      onRetry: () => ref.invalidate(deletionRequestsProvider),
    );
  }

  /// Whether the address matched an account when the request arrived.
  ///
  /// The distinction is the operator's first question: a matched row has
  /// data to erase, an unmatched one is usually a typo or an address that
  /// was never registered, and answering it here saves a lookup per row.
  Widget _accountCell(Map<String, dynamic> row) {
    final username = row['matched_username']?.toString();
    if (row['matched_user_id'] == null) {
      return BsheelCell.pill(const BsheelPill.muted('no account'));
    }
    return BsheelCell.mono(
      username == null || username.isEmpty ? 'matched' : '@$username',
      color: BsheelColors.ink,
    );
  }

  Widget _actionCell(Map<String, dynamic> row) {
    if (!_isPending(row)) {
      return BsheelCell.label('done');
    }
    if (_working == row['id']?.toString()) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: BsheelButton.positive(
        label: 'Mark handled',
        small: true,
        onPressed: () => _markHandled(row),
      ),
    );
  }

  static bool _isPending(Map<String, dynamic> row) => row['handled_at'] == null;

  static String _email(Map<String, dynamic> row) =>
      (row['email'] ?? '').toString();

  static String _handledBy(Map<String, dynamic> row) {
    if (_isPending(row)) return '—';
    final who = row['handled_by_email']?.toString();
    // `handled_by` is ON DELETE SET NULL, so an operator whose own account
    // was later removed leaves a handled row with no name on it. The audit
    // log still has the actor; say the row cannot answer rather than
    // implying nobody signed for it.
    if (who == null || who.isEmpty) return 'account removed';
    return who;
  }

  /// How long the requester has been waiting, or when it was closed.
  ///
  /// Age rather than a date, because the only thing an operator needs from
  /// this column is how overdue the request is.
  static String _waiting(Map<String, dynamic> row) {
    final created = DateTime.tryParse((row['created_at'] ?? '').toString());
    if (created == null) return '—';
    final days = DateTime.now().toUtc().difference(created.toUtc()).inDays;
    if (days >= 1) return '${days}d ago';
    final hours = DateTime.now().toUtc().difference(created.toUtc()).inHours;
    if (hours >= 1) return '${hours}h ago';
    return 'just now';
  }
}
