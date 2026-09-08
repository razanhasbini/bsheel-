import 'package:flutter/material.dart';

import '../../core/theme/bsheel_design.dart';
import '../../shared/widgets/bsheel_widgets.dart';

/// Public account-deletion page — reachable without signing in, so it
/// renders outside the shell and owns its own [Scaffold]. Drawn as one
/// framed sheet on cream: 2px ink outline, 14px radius, 8px hard shadow,
/// with a cream-gold header strip above the body.
class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  /// The word the person has to type out before the button arms.
  static const String _confirmWord = 'DELETE';

  final _emailController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  bool get _armed => _confirmController.text.trim() == _confirmWord;

  void _requestDeletion() {
    if (!_armed) return;
    if (_formKey.currentState!.validate()) {
      setState(() => _submitted = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BsheelColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 32, 40),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 640),
              decoration: BoxDecoration(
                color: BsheelColors.bg,
                borderRadius: BorderRadius.circular(BsheelRadii.lg),
                border: const Border.fromBorderSide(BsheelBorders.inkSide),
                boxShadow: BsheelShadows.frame,
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _FrameHeader(label: 'Delete account'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 24, 32, 28),
                    child: _submitted ? _confirmation() : _form(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Submitted ─────────────────────────────────────────────────────

  Widget _confirmation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: const BoxDecoration(
            color: BsheelColors.success,
            shape: BoxShape.circle,
            border: Border.fromBorderSide(BsheelBorders.inkSide),
            boxShadow: BsheelShadows.md,
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.check_rounded,
            size: 28,
            color: BsheelColors.onAccent(BsheelColors.success),
          ),
        ),
        const SizedBox(height: 16),
        const Text('REQUEST SUBMITTED', style: BsheelType.displayMd),
        const SizedBox(height: 14),
        Text(
          'Your account deletion request has been received.',
          textAlign: TextAlign.center,
          style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
        ),
        const SizedBox(height: 15),
        const BsheelCallout(
          'It can take up to 48 hours to delete your account.',
        ),
        const SizedBox(height: 15),
        Text.rich(
          const TextSpan(
            children: [
              TextSpan(text: 'If you have any questions, contact us at '),
              TextSpan(
                text: 'laztayseer@gmail.com',
                style: BsheelType.monoLg,
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
        ),
        const SizedBox(height: 22),
        const _Footnote('© 2025 BSHEEL. ALL RIGHTS RESERVED'),
      ],
    );
  }

  // ── Form ──────────────────────────────────────────────────────────

  Widget _form() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'DELETE YOUR BSHEEL ACCOUNT',
            style: BsheelType.displayMd,
          ),
          const SizedBox(height: 15),
          Text(
            'This will permanently delete your account and all data. This '
            'cannot be undone. Completed quests, posts, comments and XP are '
            'removed; deletion completes within 48 hours.',
            style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
          ),
          const SizedBox(height: 15),
          BsheelField(
            controller: _emailController,
            label: 'Email on your account',
            hint: 'your@email.com',
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email address';
              }
              final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
              if (!emailRegex.hasMatch(value.trim())) {
                return 'Please enter a valid email address';
              }
              return null;
            },
          ),
          const SizedBox(height: 15),
          SizedBox(
            width: 280,
            child: BsheelField(
              controller: _confirmController,
              label: 'Type DELETE to confirm:',
              hint: _confirmWord,
              style: BsheelType.monoLg.copyWith(letterSpacing: 1.8),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 15),
          BsheelButton.coral(
            label: 'DELETE ACCOUNT',
            height: 48,
            onPressed: _armed ? _requestDeletion : null,
          ),
          const SizedBox(height: 12),
          const _Footnote('DATA REMOVED WITHIN 48 HOURS'),
          const SizedBox(height: 26),
          const _Section(
            title: 'HOW TO DELETE',
            content:
                'You can delete your BSHEEL account directly from within the app. '
                'Follow the steps below:\n\n'
                '1. Open the BSHEEL app on your device.\n'
                '2. Go to your Profile tab.\n'
                '3. Tap the settings icon (top right).\n'
                '4. Scroll down and tap "Delete Account".\n'
                '5. Confirm the deletion when prompted.',
          ),
          const _Section(
            title: 'WHAT GETS DELETED',
            content:
                'When you delete your account, the following data is permanently removed:\n\n'
                '• Your profile: username, display name, bio, and avatar.\n'
                '• Your quest activity: all assigned quests, completions, XP, and level.\n'
                '• Your submissions: all photos and videos you uploaded as quest proof.\n'
                '• Your social data: reactions, comments, and follows.\n'
                '• Your notifications and push token.\n\n'
                'Deletion is permanent and cannot be undone.',
          ),
          const _Section(
            title: 'DATA RETENTION',
            content:
                'All personally identifiable data is deleted immediately upon account deletion. '
                'No data is retained after the deletion is confirmed. '
                'Anonymised aggregated statistics (e.g. total quest completions) may remain '
                'but cannot be linked back to you.',
          ),
          const _Footnote('© 2025 BSHEEL. ALL RIGHTS RESERVED'),
        ],
      ),
    );
  }
}

/// Cream-gold strip across the top of a public page frame.
class _FrameHeader extends StatelessWidget {
  const _FrameHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
      decoration: const BoxDecoration(
        color: BsheelColors.surface,
        border: Border(bottom: BsheelBorders.inkSide),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          const Text('BSHEEL', style: BsheelType.displaySm),
          const SizedBox(width: 10),
          Flexible(child: BsheelLabel(label)),
        ],
      ),
    );
  }
}

/// Syne section heading with its body copy.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: BsheelType.displayXs),
          const SizedBox(height: 8),
          Text(
            content,
            style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

/// 9px tracked mono footnote.
class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
    );
  }
}
