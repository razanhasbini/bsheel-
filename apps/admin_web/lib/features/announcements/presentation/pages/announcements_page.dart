import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/backend/app_backend.dart';
import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/layout/admin_shell.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

/// Broadcast composer.
///
/// One write, no reads: `POST admin/notifications` without a target user
/// writes an inbox row for every *active* account and enqueues push fanout
/// in the same transaction, then returns the recipient count. There is no
/// announcement-history endpoint — `admin.notifications()` excludes
/// `type = 'announcement'` on purpose — so RECENTLY SENT is what this
/// session sent, carrying the count the API actually reported.
class AnnouncementsPage extends ConsumerStatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  ConsumerState<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends ConsumerState<AnnouncementsPage> {
  /// The design draws the message box 84px tall before a word is typed.
  /// [BsheelField] has no `minLines`/`minHeight`, so a zero-width spacer
  /// in its suffix slot holds the input row open at that height; the box
  /// adds its own 2px outline top and bottom.
  static const double _bodyRowHeight = 80;

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  bool _isSending = false;
  final _sent = <_SentAnnouncement>[];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final title = _titleCtrl.text.trim();
    final body = _bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _toast('Title and message are required.');
      return;
    }

    // Irreversible fanout to every active account: confirm first. The
    // page has always blocked on this, and the new system dresses it as
    // a BsheelDialog rather than an AlertDialog.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BsheelDialog(
        title: 'Send to everyone?',
        content: Text(
          'Every active account gets this notification — on the device and '
          'in the in-app inbox. Delivery starts the moment you confirm and '
          'cannot be recalled or edited.',
          style: BsheelType.bodySm.copyWith(color: BsheelColors.inkSoft),
        ),
        actions: [
          BsheelButton.ghost(
            label: 'Cancel',
            small: true,
            onPressed: () => Navigator.pop(ctx, false),
          ),
          BsheelButton.coral(
            label: 'Send broadcast',
            small: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSending = true);
    try {
      // No target user: the API writes one inbox row per active user and
      // enqueues push delivery in the same transaction.
      final recipients = await AppBackend.repositories.admin.sendNotification(
        title: title,
        body: body,
      );
      if (mounted) {
        setState(() {
          _sent.insert(
            0,
            _SentAnnouncement(
              title: title,
              sentAt: DateTime.now(),
              recipients: recipients,
            ),
          );
        });
        _titleCtrl.clear();
        _bodyCtrl.clear();
        _toast('Sent to ${_grouped(recipients)} accounts.');
      }
    } catch (e) {
      if (mounted) _toast('Failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: BsheelColors.paper,
        content: Text(
          msg,
          style: BsheelType.bodySm.copyWith(
            color: error ? BsheelColors.dangerText : BsheelColors.ink,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ready = _titleCtrl.text.trim().isNotEmpty &&
        _bodyCtrl.text.trim().isNotEmpty;

    return AdminPane(
      title: 'Announcements',
      meta: 'Sends to all users',
      metaColor: BsheelColors.dangerText,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BsheelField(
            controller: _titleCtrl,
            label: 'Notification title',
            hint: 'e.g. NEW QUESTS DROPPED',
            enabled: !_isSending,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 13),
          BsheelField(
            controller: _bodyCtrl,
            label: 'Message body',
            hint: 'What do you want to tell your players?',
            maxLines: 4,
            enabled: !_isSending,
            onChanged: (_) => setState(() {}),
            suffix: const SizedBox(height: _bodyRowHeight),
          ),
          const SizedBox(height: 13),
          // The API reports the recipient count only after the fact, and
          // there is no device-token count anywhere in the admin API, so
          // this states the reach without a number it cannot stand behind.
          const BsheelCallout.warning(
            'This fans out to every active account through the delivery '
            'queue. It cannot be recalled.',
          ),
          const SizedBox(height: 13),
          Align(
            alignment: Alignment.centerLeft,
            child: BsheelButton.primary(
              label: 'Send broadcast',
              loading: _isSending,
              onPressed: ready && !_isSending ? _send : null,
            ),
          ),
          const SizedBox(height: 17),
          const BsheelLabel('Recently sent'),
          const SizedBox(height: 8),
          if (_sent.isEmpty)
            const BsheelCard.muted(
              child: Text(
                'Nothing has gone out from this session. The API keeps no '
                'announcement history, so this list starts empty after a '
                'reload — the delivered counts above are the only record '
                'the console shows.',
                style: BsheelType.bodySm,
              ),
            )
          else
            BsheelCard.flat(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _sent.length; i++)
                    _SentRow(
                      entry: _sent[i],
                      last: i == _sent.length - 1,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── Recently sent ────────────────────────────────────────────────────────────

class _SentRow extends StatelessWidget {
  final _SentAnnouncement entry;
  final bool last;

  const _SentRow({required this.entry, required this.last});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: last
          ? null
          : const BoxDecoration(border: Border(bottom: BsheelBorders.rowSide)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.title,
            style: BsheelType.titleMd,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            entry.receipt,
            style: BsheelType.monoSm.copyWith(color: BsheelColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _SentAnnouncement {
  const _SentAnnouncement({
    required this.title,
    required this.sentAt,
    required this.recipients,
  });

  final String title;
  final DateTime sentAt;

  /// What the API reported: one inbox row per active account.
  final int recipients;

  /// `09 MAR · 8,390 DELIVERED`. Invalid-token counts come back from the
  /// push worker, which the admin API does not expose, so the line stops
  /// at what is known.
  String get receipt =>
      '${_date(sentAt)} · ${_grouped(recipients)} DELIVERED';
}

// ── Formatting ───────────────────────────────────────────────────────────────

const List<String> _months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// `09 MAR` — the form the design draws.
String _date(DateTime at) {
  final local = at.toLocal();
  return '${local.day.toString().padLeft(2, '0')} '
      '${_months[local.month - 1]}';
}

/// `8390` → `8,390`, so a five-figure delivery count reads at a glance.
String _grouped(int n) {
  final digits = n.abs().toString();
  final out = StringBuffer(n < 0 ? '−' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i != 0 && (digits.length - i) % 3 == 0) out.write(',');
    out.write(digits[i]);
  }
  return out.toString();
}
