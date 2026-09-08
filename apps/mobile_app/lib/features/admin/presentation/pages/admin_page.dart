import 'package:app_core/app_core.dart';
import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import '../../../../core/backend/app_backend.dart';
import '../../../../core/providers/auth_session_provider.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/router/safe_back.dart';

/// Shared admin repo seam — same lookup the admin web uses (ARC-021).
final _adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AppBackend.repositories.admin;
});

/// Strongly-typed admin role for the current user.
final adminRoleEnumProvider = FutureProvider<AdminRoleEnum?>((ref) async {
  ref.watch(authSessionProvider); // re-evaluate on auth change
  return ref.watch(_adminRepositoryProvider).getCurrentUserRole();
});

/// Checks if current user is in the admins table.
final isAdminProvider = FutureProvider<bool>((ref) async {
  final role = await ref.watch(adminRoleEnumProvider.future);
  return role != null;
});

/// Mobile-side super-admin gate. Use this to hide destructive admin
/// actions from moderators (mobile previously had no super-admin
/// distinction at all — every admin saw every button).
final isSuperAdminProvider = FutureProvider<bool>((ref) async {
  final role = await ref.watch(adminRoleEnumProvider.future);
  return role?.isSuperAdmin ?? false;
});

// autoDispose so the cache drops when the admin tab is closed; watch
// authSessionProvider so a logout/account-switch re-evaluates the
// query against the new session instead of serving the previous
// admin's results.
final _deletedSubmissionsProvider =
    FutureProvider.autoDispose<List<SubmissionModel>>((ref) async {
  ref.watch(authSessionProvider);
  final rows = await AppBackend.repositories.moderation.listSubmissionsForAdmin(
    status: 'all',
    visibility: 'not_visible',
    order: 'desc',
  );
  return rows.map(SubmissionModel.fromJson).toList();
});

final _pendingSubmissionsProvider =
    FutureProvider.autoDispose<List<SubmissionModel>>((ref) async {
  ref.watch(authSessionProvider);
  final rows = await AppBackend.repositories.moderation
      .listSubmissionsForAdmin(status: 'pending', order: 'desc');
  return rows.map(SubmissionModel.fromJson).toList();
});

class AdminPage extends ConsumerStatefulWidget {
  const AdminPage({super.key});

  @override
  ConsumerState<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends ConsumerState<AdminPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);

    return isAdmin.when(
      loading: () => Scaffold(
        backgroundColor: QuestColors.bg(context),
        body: const Center(
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      // Distinguish "couldn't check" (network/timeout) from "not admin"
      // (data: false below). Showing ACCESS DENIED on a transient blip
      // would lock real admins out of the page they need.
      error: (e, _) => Scaffold(
        backgroundColor: QuestColors.bg(context),
        body: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded,
                    size: 48, color: QuestColors.textDim(context)),
                const SizedBox(height: QuestSpacing.md),
                Text("Couldn't verify admin access.",
                    style: QuestTypography.headlineSmall),
                const SizedBox(height: QuestSpacing.sm),
                Text('Check your connection and retry.',
                    style: QuestTypography.bodyMedium
                        .copyWith(color: QuestColors.textDim(context))),
                const SizedBox(height: QuestSpacing.lg),
                GestureDetector(
                  onTap: () => ref.invalidate(isAdminProvider),
                  child: Text('RETRY',
                      style: QuestTypography.labelSmall
                          .copyWith(color: QuestColors.accent(context))),
                ),
                const SizedBox(height: QuestSpacing.sm),
                GestureDetector(
                  onTap: () => safeBack(context),
                  child: Text('GO BACK',
                      style: QuestTypography.labelSmall
                          .copyWith(color: QuestColors.textDim(context))),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (admin) {
        if (!admin) {
          return Scaffold(
            backgroundColor: QuestColors.bg(context),
            body: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 48, color: QuestColors.softRed),
                    const SizedBox(height: QuestSpacing.md),
                    Text('ACCESS DENIED',
                        style: QuestTypography.headlineSmall
                            .copyWith(color: QuestColors.softRed)),
                    const SizedBox(height: QuestSpacing.sm),
                    Text(AppLocalizations.of(context)!.notAuthorized,
                        style: QuestTypography.bodyMedium
                            .copyWith(color: QuestColors.textDim(context))),
                    const SizedBox(height: QuestSpacing.lg),
                    GestureDetector(
                      onTap: () => safeBack(context),
                      child: Text(AppLocalizations.of(context)!.goBack,
                          style: QuestTypography.labelSmall
                              .copyWith(color: QuestColors.accent(context))),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return _buildAdminContent(context);
      },
    );
  }

  Widget _buildAdminContent(BuildContext context) {
    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                QuestSpacing.screenPadding,
                QuestSpacing.screenPadding,
                QuestSpacing.screenPadding,
                0,
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => safeBack(context),
                    child: Icon(Icons.arrow_back,
                        size: 20, color: QuestColors.text(context)),
                  ),
                  const SizedBox(width: QuestSpacing.md),
                  Text(AppLocalizations.of(context)!.admin,
                      style: QuestTypography.headlineLarge
                          .copyWith(fontSize: 20, letterSpacing: 2)),
                ],
              ),
            ),
            const SizedBox(height: QuestSpacing.sm),

            // ── Tabs ──────────────────────────────────────────
            TabBar(
              controller: _tabCtrl,
              labelColor: QuestColors.highlight(context),
              unselectedLabelColor: QuestColors.textMuted,
              indicatorColor: QuestColors.highlight(context),
              indicatorWeight: 2,
              labelStyle: QuestTypography.labelSmall
                  .copyWith(fontSize: 10, letterSpacing: 1.2),
              tabs: const [
                Tab(text: 'MODERATION'),
                Tab(text: 'PUSH NOTIFY'),
                Tab(text: 'DELETED'),
              ],
            ),

            // ── Tab content ───────────────────────────────────
            // Push broadcast + deleted-posts admin are super-admin only.
            // Any moderator could previously blast every user; gate
            // them here instead of relying on RLS hopefully rejecting.
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  final isSuper =
                      ref.watch(isSuperAdminProvider).valueOrNull ?? false;
                  return TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _ModerationTab(),
                      isSuper
                          ? _PushNotificationTab()
                          : const _SuperAdminGate(label: 'Push broadcast'),
                      isSuper
                          ? _DeletedPostsTab()
                          : const _SuperAdminGate(label: 'Deleted posts'),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuperAdminGate extends StatelessWidget {
  const _SuperAdminGate({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(QuestSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield_outlined,
                size: 48, color: QuestColors.softRed),
            const SizedBox(height: QuestSpacing.md),
            Text('SUPER-ADMIN ONLY',
                style: QuestTypography.headlineSmall
                    .copyWith(color: QuestColors.softRed)),
            const SizedBox(height: QuestSpacing.sm),
            Text('$label is restricted to super-admins.',
                textAlign: TextAlign.center,
                style: QuestTypography.bodyMedium
                    .copyWith(color: QuestColors.textDim(context))),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MODERATION TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _ModerationTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(_pendingSubmissionsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: QuestSpacing.screenPadding,
            vertical: QuestSpacing.sm,
          ),
          child: Row(
            children: [
              Text(AppLocalizations.of(context)!.pendingReview,
                  style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.textDim(context), letterSpacing: 1)),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.invalidate(_pendingSubmissionsProvider),
                child: Icon(Icons.refresh,
                    size: 16, color: QuestColors.textDim(context)),
              ),
            ],
          ),
        ),
        Expanded(
          child: pendingAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (e, _) => Center(
              child: Text('Error: $e',
                  style: QuestTypography.bodyMedium
                      .copyWith(color: QuestColors.softRed)),
            ),
            data: (submissions) {
              if (submissions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 48,
                          color: QuestColors.highlight(context).withAlpha(120)),
                      const SizedBox(height: QuestSpacing.md),
                      Text(AppLocalizations.of(context)!.allClear,
                          style: QuestTypography.headlineSmall),
                      const SizedBox(height: QuestSpacing.sm),
                      Text(AppLocalizations.of(context)!.noPendingSubmissions,
                          style: QuestTypography.bodyMedium
                              .copyWith(color: QuestColors.textDim(context))),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: QuestColors.highlight(context),
                backgroundColor: QuestColors.cardBg(context),
                onRefresh: () async =>
                    ref.invalidate(_pendingSubmissionsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.screenPadding),
                  itemCount: submissions.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: QuestSpacing.sm),
                  itemBuilder: (context, index) {
                    final s = submissions[index];
                    return _SubmissionCard(
                      submission: s,
                      onApprove: () => _approve(context, ref, s),
                      onReject: () => _reject(context, ref, s),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _approve(
      BuildContext context, WidgetRef ref, SubmissionModel s) async {
    // Guard concurrent taps on the same row so a double-tap or rapid
    // approve-then-reject can't fire two writes against the same id.
    if (_adminInflight.contains(s.id)) return;
    _adminInflight.add(s.id);
    try {
      // The API grants XP once, fires the submission_approved
      // notification, syncs user_quests.status and writes the audit row —
      // all in one transaction.
      await AppBackend.repositories.moderation.approveSubmission(s.id, '');
      ref.invalidate(_pendingSubmissionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
                content: Text(AppLocalizations.of(context)!.submissionApproved),
                backgroundColor: QuestColors.highlight(context)),
          );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(mapDbError(e, action: 'approve submission'))));
      }
    } finally {
      _adminInflight.remove(s.id);
    }
  }

  Future<void> _reject(
      BuildContext context, WidgetRef ref, SubmissionModel s) async {
    // Disposed in the finally below so we don't leak a controller per
    // reject dialog open. Previously this was orphaned on every open.
    final controller = TextEditingController();
    try {
      await _rejectInner(context, ref, s, controller);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _rejectInner(BuildContext context, WidgetRef ref,
      SubmissionModel s, TextEditingController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: QuestColors.cardBg(context),
        title: Text(AppLocalizations.of(context)!.rejectSubmission,
            style: QuestTypography.headlineSmall
                .copyWith(color: QuestColors.softRed)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(AppLocalizations.of(context)!.reasonOptional,
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.textDim(context))),
            const SizedBox(height: QuestSpacing.sm),
            TextField(
              controller: controller,
              style: QuestTypography.bodyMedium,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.rejectHint,
                hintStyle: QuestTypography.bodySmall
                    .copyWith(color: QuestColors.textMuted.withAlpha(80)),
                enabledBorder: OutlineInputBorder(
                  borderSide:
                      BorderSide(color: QuestColors.softRed.withAlpha(80)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: QuestColors.softRed),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('CANCEL',
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.textDim(context))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('REJECT',
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.softRed)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    if (_adminInflight.contains(s.id)) return;
    _adminInflight.add(s.id);
    try {
      // The API requires a non-empty note; the UI advertises the reason as
      // optional, so a blank one becomes an explicit placeholder.
      final note = controller.text.trim();
      await AppBackend.repositories.moderation.rejectSubmission(
        s.id,
        '',
        note: note.isEmpty ? 'No reason provided' : note,
      );
      ref.invalidate(_pendingSubmissionsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(
                content:
                    Text(AppLocalizations.of(context)!.submissionRejected)),
          );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
              content: Text(mapDbError(e, action: 'reject submission'))));
      }
    } finally {
      _adminInflight.remove(s.id);
    }
  }
}

/// Module-scoped set of submission ids currently being approved/rejected.
/// Lives at module scope rather than inside a widget state because
/// `_ModerationTab` is a ConsumerWidget — converting to stateful just
/// for this guard would touch every callsite. Cleared naturally as
/// actions resolve; a hot reload also resets it.
final Set<String> _adminInflight = <String>{};

// ═══════════════════════════════════════════════════════════════════════════════
// PUSH NOTIFICATION TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _PushNotificationTab extends ConsumerStatefulWidget {
  @override
  ConsumerState<_PushNotificationTab> createState() =>
      _PushNotificationTabState();
}

class _PushNotificationTabState extends ConsumerState<_PushNotificationTab> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _isSending = false;
  final _history = <Map<String, String>>[];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendPush() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
              content:
                  Text(AppLocalizations.of(context)!.titleAndBodyRequired)),
        );
      return;
    }
    // UX-212: confirm before broadcasting to every user. The button used
    // to fire immediately on tap — one wrong tap blasts a draft to all
    // active accounts.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: QuestColors.cardBg(ctx),
        title: const Text('SEND TO ALL USERS?',
            style: TextStyle(fontWeight: FontWeight.w900)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Title', style: QuestTypography.labelSmall),
            const SizedBox(height: 4),
            Text(title, style: QuestTypography.bodyMedium),
            const SizedBox(height: 12),
            Text('Body', style: QuestTypography.labelSmall),
            const SizedBox(height: 4),
            Text(body, style: QuestTypography.bodyMedium),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('SEND',
                style: QuestTypography.labelSmall
                    .copyWith(color: QuestColors.softRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSending = true);

    try {
      // One request: the API inserts an inbox row per active user and
      // enqueues push delivery through the outbox worker, in the same
      // transaction. The old path fanned out client-side in 1000-row
      // chunks and could half-broadcast if a chunk failed.
      await AppBackend.repositories.admin.sendNotification(
        title: title,
        body: body,
      );

      if (!mounted) return;
      setState(() {
        _history.insert(0, {'title': title, 'body': body});
        // Cap local history so it doesn't grow unbounded across the session.
        if (_history.length > 100) {
          _history.removeRange(100, _history.length);
        }
        _titleCtrl.clear();
        _bodyCtrl.clear();
        _isSending = false;
      });
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.pushSent),
            backgroundColor: QuestColors.highlight(context),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSending = false);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(QuestSpacing.screenPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.campaign, size: 18, color: QuestColors.xpGold),
              const SizedBox(width: QuestSpacing.sm),
              Text(AppLocalizations.of(context)!.broadcastTitle,
                  style: QuestTypography.labelSmall.copyWith(
                    color: QuestColors.xpGold,
                    fontSize: 11,
                    letterSpacing: 1,
                  )),
            ],
          ),
          const SizedBox(height: QuestSpacing.lg),

          // ── Title field ─────────────────────────────────
          Text(AppLocalizations.of(context)!.notificationTitle,
              style: QuestTypography.labelSmall.copyWith(
                color: QuestColors.textDim(context),
                fontSize: 9,
                letterSpacing: 1,
              )),
          const SizedBox(height: QuestSpacing.xs),
          TextField(
            controller: _titleCtrl,
            style: QuestTypography.labelMedium
                .copyWith(color: QuestColors.text(context)),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.notificationTitleHint,
              hintStyle: QuestTypography.labelMedium
                  .copyWith(color: QuestColors.textMuted.withAlpha(80)),
              filled: true,
              fillColor: QuestColors.cardBg(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
                borderSide: BorderSide(
                    color: QuestColors.xpGold.withAlpha(80), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
                borderSide: BorderSide(
                    color: QuestColors.xpGold.withAlpha(60), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
                borderSide:
                    const BorderSide(color: QuestColors.xpGold, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: QuestSpacing.md),

          // ── Body field ──────────────────────────────────
          Text(AppLocalizations.of(context)!.messageBody,
              style: QuestTypography.labelSmall.copyWith(
                color: QuestColors.textDim(context),
                fontSize: 9,
                letterSpacing: 1,
              )),
          const SizedBox(height: QuestSpacing.xs),
          TextField(
            controller: _bodyCtrl,
            style: QuestTypography.bodyMedium
                .copyWith(color: QuestColors.text(context)),
            maxLines: 4,
            // UX-211: FCM truncates push bodies past ~240 chars on most
            // OS lock screens. Stop the user from typing past the cap +
            // surface a counter so they know the limit.
            maxLength: 240,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.messageBodyHint,
              hintStyle: QuestTypography.bodySmall
                  .copyWith(color: QuestColors.textMuted.withAlpha(80)),
              filled: true,
              fillColor: QuestColors.cardBg(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
                borderSide: BorderSide(
                    color: QuestColors.xpGold.withAlpha(80), width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
                borderSide: BorderSide(
                    color: QuestColors.xpGold.withAlpha(60), width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
                borderSide:
                    const BorderSide(color: QuestColors.xpGold, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: QuestSpacing.lg),

          // ── Send button ─────────────────────────────────
          GestureDetector(
            onTap: _isSending ? null : _sendPush,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: _isSending
                    ? QuestColors.textMuted.withAlpha(20)
                    : QuestColors.xpGold.withAlpha(20),
                borderRadius: BorderRadius.circular(QuestSpacing.radiusSm),
                border: Border.all(
                  color:
                      _isSending ? QuestColors.textMuted : QuestColors.xpGold,
                  width: 2,
                ),
                boxShadow: _isSending
                    ? null
                    : [
                        BoxShadow(
                          color: QuestColors.xpGold.withAlpha(40),
                          blurRadius: 8,
                        ),
                      ],
              ),
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.send,
                                  size: 16, color: QuestColors.xpGold),
                              const SizedBox(width: QuestSpacing.sm),
                              Text(
                                'SEND PUSH TO ALL USERS',
                                style: QuestTypography.labelMedium.copyWith(
                                  color: QuestColors.xpGold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: QuestSpacing.xl),

          // ── Recent sends ────────────────────────────────
          if (_history.isNotEmpty) ...[
            Text(AppLocalizations.of(context)!.recentlySent,
                style: QuestTypography.labelSmall.copyWith(
                  color: QuestColors.textDim(context),
                  fontSize: 9,
                  letterSpacing: 1,
                )),
            const SizedBox(height: QuestSpacing.sm),
            ...(_history.take(5).map((h) => Padding(
                  padding: const EdgeInsets.only(bottom: QuestSpacing.sm),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: QuestColors.cardBg(context),
                      borderRadius:
                          BorderRadius.circular(QuestSpacing.radiusSm),
                      border: Border.all(
                          color: QuestColors.borderC(context), width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(QuestSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h['title']!,
                              style: QuestTypography.labelMedium
                                  .copyWith(color: QuestColors.xpGold)),
                          const SizedBox(height: 2),
                          Text(h['body']!,
                              style: QuestTypography.bodySmall.copyWith(
                                  color: QuestColors.textDim(context))),
                        ],
                      ),
                    ),
                  ),
                ))),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// DELETED POSTS TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _DeletedPostsTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deletedAsync = ref.watch(_deletedSubmissionsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: QuestSpacing.screenPadding,
            vertical: QuestSpacing.sm,
          ),
          child: Row(
            children: [
              Text(AppLocalizations.of(context)!.deletedPosts,
                  style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.textDim(context), letterSpacing: 1)),
              const Spacer(),
              GestureDetector(
                onTap: () => ref.invalidate(_deletedSubmissionsProvider),
                child: Icon(Icons.refresh,
                    size: 16, color: QuestColors.textDim(context)),
              ),
            ],
          ),
        ),
        Expanded(
          child: deletedAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (e, _) => Center(
              child: Text('Error: $e',
                  style: QuestTypography.bodyMedium
                      .copyWith(color: QuestColors.softRed)),
            ),
            data: (submissions) {
              if (submissions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline,
                          size: 48,
                          color: QuestColors.textDim(context).withAlpha(120)),
                      const SizedBox(height: QuestSpacing.md),
                      Text(AppLocalizations.of(context)!.noDeletedPosts,
                          style: QuestTypography.headlineSmall),
                      const SizedBox(height: QuestSpacing.sm),
                      Text(AppLocalizations.of(context)!.noDeletedPostsDesc,
                          style: QuestTypography.bodyMedium
                              .copyWith(color: QuestColors.textDim(context))),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                color: QuestColors.highlight(context),
                backgroundColor: QuestColors.cardBg(context),
                onRefresh: () async =>
                    ref.invalidate(_deletedSubmissionsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: QuestSpacing.screenPadding),
                  itemCount: submissions.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: QuestSpacing.sm),
                  itemBuilder: (context, index) {
                    final s = submissions[index];
                    final isHiddenFromFeed =
                        s.visibility == SubmissionVisibility.hiddenFromFeed;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        color: QuestColors.cardBg(context),
                        borderRadius:
                            BorderRadius.circular(QuestSpacing.radiusMd),
                        border: Border.all(
                          color: isHiddenFromFeed
                              ? QuestColors.accentYellow.withAlpha(60)
                              : QuestColors.softRed.withAlpha(60),
                          width: 1,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(QuestSpacing.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Status badge
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: QuestSpacing.sm,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isHiddenFromFeed
                                        ? QuestColors.accentYellow.withAlpha(26)
                                        : QuestColors.softRed.withAlpha(26),
                                    borderRadius: BorderRadius.circular(
                                        QuestSpacing.radiusSm),
                                    border: Border.all(
                                      color: isHiddenFromFeed
                                          ? QuestColors.accentYellow
                                              .withAlpha(77)
                                          : QuestColors.softRed.withAlpha(77),
                                    ),
                                  ),
                                  child: Text(
                                    isHiddenFromFeed
                                        ? AppLocalizations.of(context)!
                                            .hiddenFromFeed
                                        : AppLocalizations.of(context)!
                                            .deletedFromProfile,
                                    style: QuestTypography.labelSmall.copyWith(
                                      color: isHiddenFromFeed
                                          ? QuestColors.accentYellow
                                          : QuestColors.softRed,
                                      fontSize: 9,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                if (s.deletedAt != null)
                                  Text(
                                    timeAgoLong(s.deletedAt!),
                                    style: QuestTypography.labelSmall.copyWith(
                                      color: QuestColors.textDim(context),
                                      fontSize: 9,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: QuestSpacing.sm),
                            // Media thumbnail
                            if (s.mediaUrls.isNotEmpty)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Image.network(
                                    s.mediaUrls.first,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => DecoratedBox(
                                      decoration: BoxDecoration(
                                          color:
                                              QuestColors.surfaceBg(context)),
                                      child: Center(
                                        child: Icon(Icons.image_outlined,
                                            color: QuestColors.textDim(context),
                                            size: 32),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: QuestSpacing.sm),
                            if (s.caption?.isNotEmpty == true)
                              Text(
                                s.caption!,
                                style: QuestTypography.bodyMedium
                                    .copyWith(color: QuestColors.text(context)),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: QuestSpacing.xs),
                            Text(
                              'ID: ${s.id.substring(0, 8)}... | User: ${s.userId.substring(0, 8)}...',
                              style: QuestTypography.labelSmall.copyWith(
                                  color: QuestColors.textDim(context),
                                  fontSize: 9),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// SUBMISSION CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({
    required this.submission,
    required this.onApprove,
    required this.onReject,
  });
  final SubmissionModel submission;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: QuestColors.cardBg(context),
        borderRadius: BorderRadius.circular(QuestSpacing.radiusMd),
        border: Border.all(color: QuestColors.borderC(context), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(QuestSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (submission.mediaUrls.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Image.network(
                    submission.mediaUrls.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration:
                          BoxDecoration(color: QuestColors.surfaceBg(context)),
                      child: Center(
                        child: Icon(Icons.image_outlined,
                            color: QuestColors.textDim(context), size: 32),
                      ),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: QuestSpacing.sm),
            if (submission.caption?.isNotEmpty == true)
              Text(
                submission.caption!,
                style: QuestTypography.bodyMedium
                    .copyWith(color: QuestColors.text(context)),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: QuestSpacing.sm),
            // UX-208: tap-to-copy the full UUID. Admins occasionally need it
            // for SQL queries; the truncation is purely visual.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: submission.id));
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(
                    content: Text('ID copied: ${submission.id}'),
                    duration: const Duration(seconds: 2),
                  ));
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'ID: ${submission.id.substring(0, 8)}…',
                    style: QuestTypography.labelSmall.copyWith(
                      color: QuestColors.textDim(context),
                      fontSize: 9,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.copy_rounded,
                      size: 11, color: QuestColors.textDim(context)),
                ],
              ),
            ),
            const SizedBox(height: QuestSpacing.md),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onApprove,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: QuestColors.highlightBg(context),
                        borderRadius:
                            BorderRadius.circular(QuestSpacing.radiusSm),
                        border: Border.all(
                            color: QuestColors.highlight(context), width: 1.5),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: Text('APPROVE',
                              style: TextStyle(
                                  color: QuestColors.highlight(context),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 1)),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: QuestSpacing.sm),
                Expanded(
                  child: GestureDetector(
                    onTap: onReject,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: QuestColors.softRed.withAlpha(20),
                        borderRadius:
                            BorderRadius.circular(QuestSpacing.radiusSm),
                        border:
                            Border.all(color: QuestColors.softRed, width: 1.5),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Center(
                          child: Text('REJECT',
                              style: TextStyle(
                                  color: QuestColors.softRed,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  letterSpacing: 1)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
