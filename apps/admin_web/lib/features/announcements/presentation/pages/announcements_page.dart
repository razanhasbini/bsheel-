import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/bsheel_design.dart';
import '../../../../shared/widgets/bsheel_widgets.dart';

class AnnouncementsPage extends ConsumerStatefulWidget {
  const AnnouncementsPage({super.key});

  @override
  ConsumerState<AnnouncementsPage> createState() => _AnnouncementsPageState();
}

class _AnnouncementsPageState extends ConsumerState<AnnouncementsPage> {
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: BsheelColors.paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(BsheelRadii.xl),
          side: const BorderSide(
              color: BsheelColors.line, width: BsheelBorders.thin,),
        ),
        title: const BsheelDisplay(
          'Send to {everyone?}',
          baseStyle: BsheelType.displaySm,
        ),
        content: const Text(
          "This pushes a notification to every user. There's no undo.",
          style: BsheelType.bodyMd,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'CANCEL',
              style: BsheelType.labelMd.copyWith(color: BsheelColors.inkMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'SEND',
              style: BsheelType.labelMd.copyWith(color: BsheelColors.hot),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isSending = true);
    try {
      await Supabase.instance.client.rpc(
        RpcNames.broadcastAnnouncement,
        params: {'p_title': title, 'p_body': body},
      );
      if (mounted) {
        setState(() {
          _sent.insert(
            0,
            _SentAnnouncement(
              title: title,
              body: body,
              sentAt: DateTime.now(),
            ),
          );
        });
        _titleCtrl.clear();
        _bodyCtrl.clear();
        _toast('Push sent to all users.');
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
            color: error ? BsheelColors.hot : BsheelColors.ink,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero
          BsheelCard(
            padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelEyebrow('Community · Announcements'),
                const SizedBox(height: 14),
                BsheelDisplay(
                  'Send a {broadcast.}',
                  baseStyle: BsheelType.displayXl.copyWith(fontSize: 44),
                ),
                const SizedBox(height: 12),
                Text(
                  'One push, every user. Use sparingly — overuse trains people '
                  'to mute the app.',
                  style: BsheelType.bodyMd.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Composer
          BsheelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const BsheelEyebrow('Compose'),
                const SizedBox(height: 14),
                _Field(
                  controller: _titleCtrl,
                  label: 'TITLE',
                  hint: 'e.g. New quests just dropped.',
                ),
                const SizedBox(height: 14),
                _Field(
                  controller: _bodyCtrl,
                  label: 'MESSAGE',
                  hint: 'Tell users what just happened. iOS truncates ~80 chars.',
                  maxLines: 4,
                ),
                const SizedBox(height: 18),
                BsheelButton.primary(
                  label: _isSending ? 'SENDING…' : 'SEND TO EVERYONE',
                  icon: _isSending ? null : Icons.campaign_rounded,
                  loading: _isSending,
                  onPressed: _isSending ? null : _send,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Sent (session)
          if (_sent.isNotEmpty) ...[
            const BsheelSectionHeader(title: 'Sent this', emphasis: 'session'),
            for (final a in _sent) ...[
              BsheelCard.flat(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: BsheelColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: BsheelColors.line,
                            width: BsheelBorders.thin,),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: BsheelColors.paper,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title, style: BsheelType.bodyMdBold),
                          const SizedBox(height: 4),
                          Text(a.body, style: BsheelType.bodySm),
                          const SizedBox(height: 6),
                          Text(
                            '${a.sentAt.hour.toString().padLeft(2, '0')}:'
                            '${a.sentAt.minute.toString().padLeft(2, '0')}',
                            style: BsheelType.labelSm,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _SentAnnouncement {
  const _SentAnnouncement({
    required this.title,
    required this.body,
    required this.sentAt,
  });
  final String title;
  final String body;
  final DateTime sentAt;
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
  });
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: BsheelType.labelSm),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: BsheelType.bodyMd,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                BsheelType.bodyMd.copyWith(color: BsheelColors.inkMuted),
            filled: true,
            fillColor: BsheelColors.paper,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              borderSide: const BorderSide(
                  color: BsheelColors.line, width: BsheelBorders.thin,),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              borderSide: const BorderSide(
                  color: BsheelColors.line, width: BsheelBorders.thin,),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(BsheelRadii.md),
              borderSide: const BorderSide(
                  color: BsheelColors.ink, width: BsheelBorders.thin,),
            ),
          ),
        ),
      ],
    );
  }
}
