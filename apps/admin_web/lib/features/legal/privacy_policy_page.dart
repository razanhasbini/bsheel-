import 'package:flutter/material.dart';

import '../../core/theme/bsheel_design.dart';
import '../../shared/widgets/bsheel_widgets.dart';

/// Public privacy policy — reachable without signing in, so it renders
/// outside the shell and owns its own [Scaffold]. One framed, scrollable
/// sheet on cream: 2px ink outline, 14px radius, 8px hard shadow, with a
/// cream-gold header strip above the body.
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

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
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _FrameHeader(label: 'Privacy policy'),
                  Padding(
                    padding: EdgeInsets.fromLTRB(28, 22, 28, 28),
                    child: _Body(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('PRIVACY POLICY', style: BsheelType.displayMd),
        const SizedBox(height: 10),
        Text(
          'LAST UPDATED APRIL 2025',
          style: BsheelType.labelMd.copyWith(color: BsheelColors.inkMuted),
        ),
        const SizedBox(height: 14),
        const Text(
          'Bsheel stores the account details you give us, the quests you '
          'complete, and the photo or video proof you submit. Proof media is '
          'kept in private storage and served only through short-lived '
          'signed links.',
          style: BsheelType.bodyMd,
        ),
        const SizedBox(height: 14),
        Text(
          'BSHEEL ("we", "our", or "us") is committed to protecting your '
          'privacy. This Privacy Policy explains how we collect, use, and '
          'safeguard your information when you use the BSHEEL mobile '
          'application.',
          style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
        ),
        const SizedBox(height: 18),
        const _Section(
          title: 'WHAT MODERATORS SEE',
          content:
              'A moderator reviewing your submission sees your username, level, '
              'the proof and caption you submitted, and your prior approval '
              'history. They do not see your email address or device identifiers.',
        ),
        const _Section(
          title: 'DELETION',
          content:
              'You can delete your account from Settings or from the public '
              'deletion page. Removal completes within 48 hours and cannot be '
              'reversed.',
        ),
        const _Section(
          title: '1. INFORMATION WE COLLECT',
          content:
              '• Account information: username, display name, email address, and profile photo.\n'
              '• Quest activity: quest assignments, completion status, XP, and level.\n'
              '• User-generated content: photos and videos submitted as quest proof, captions, and comments.\n'
              "• Reactions and follows: interactions with other users' posts.\n"
              '• Device information: FCM token for push notifications.\n'
              '• Usage data: app activity timestamps used for streak tracking.',
        ),
        const _Section(
          title: '2. HOW WE USE IT',
          content: '• To provide and operate the BSHEEL app.\n'
              '• To display your profile, posts, and activity to other users.\n'
              '• To send push notifications about quest assignments, approvals, and social activity.\n'
              '• To calculate XP, levels, and leaderboard rankings.\n'
              '• To review submitted quest proof (photo/video) for approval.',
        ),
        const _Section(
          title: '3. USER-GENERATED CONTENT',
          content:
              'Photos and videos you submit as quest proof are visible to other users in the feed. '
              'Your username, display name, and avatar are publicly visible within the app. '
              'You can delete your account at any time, which permanently removes all your data.',
        ),
        const _Section(
          title: '4. DATA STORAGE',
          content:
              'Account, quest and social data are stored in a PostgreSQL database on '
              'infrastructure we operate. Photos and videos are stored in S3-compatible '
              'object storage and stay private, served only through short-lived signed '
              'URLs. Passwords are hashed with Argon2. Push notifications are delivered '
              'via Firebase Cloud Messaging.',
        ),
        const _Section(
          title: '5. DATA SHARING',
          content:
              'We do not sell your personal data. We do not share your data with third '
              'parties except as required to operate the service (our hosting and object '
              'storage providers, and Firebase for push notifications) or as required by '
              'law.',
        ),
        const _Section(
          title: "6. CHILDREN'S PRIVACY",
          content:
              'BSHEEL is not directed at children under 13. We do not knowingly collect '
              'personal information from children under 13. If you believe a child has '
              'provided us with personal information, please contact us immediately.',
        ),
        const _Section(
          title: '7. YOUR RIGHTS',
          content: '• Access your data: visible in your profile.\n'
              '• Delete your account: available in Settings → Delete Account.\n'
              '• Contact us: for any data requests or concerns, email us below.',
        ),
        const _Section(
          title: '8. CHANGES TO THIS POLICY',
          content: 'We may update this Privacy Policy from time to time. '
              'We will notify you of significant changes via push notification or in-app message.',
        ),
        const SizedBox(height: 4),
        BsheelCard.flat(
          color: BsheelColors.card,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SUPPORT', style: BsheelType.displayXs),
              const SizedBox(height: 8),
              Text(
                "Having issues with the app? We're here to help.",
                style: BsheelType.bodyMd.copyWith(color: BsheelColors.inkSoft),
              ),
              const SizedBox(height: 14),
              const _SupportRow(
                icon: Icons.email_outlined,
                label: 'Email',
                value: 'laztayseer@gmail.com',
              ),
              const SizedBox(height: 8),
              const _SupportRow(
                icon: Icons.language_outlined,
                label: 'Website',
                value: 'admin.bsheel.app',
              ),
              const SizedBox(height: 14),
              Text(
                'WE AIM TO RESPOND WITHIN 48 HOURS',
                style: BsheelType.labelSm.copyWith(
                  color: BsheelColors.inkMuted,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          '© 2025 BSHEEL. ALL RIGHTS RESERVED',
          style: BsheelType.labelSm.copyWith(color: BsheelColors.inkMuted),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 15),
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
      padding: const EdgeInsets.only(bottom: 18),
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

class _SupportRow extends StatelessWidget {
  const _SupportRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        Icon(icon, size: 16, color: BsheelColors.ink),
        BsheelLabel(label),
        SelectableText(value, style: BsheelType.monoLg),
      ],
    );
  }
}
