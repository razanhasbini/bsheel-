import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

import '../../core/theme/bsheel_design.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    return Scaffold(
      backgroundColor: BsheelColors.bg,
      appBar: AppBar(
        backgroundColor: BsheelColors.bg,
        elevation: 0,
        title: Text(
          'BSHEEL',
          style: BsheelType.displaySm.copyWith(
            color: BsheelColors.primary,
            letterSpacing: 3,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: Container(height: 2, color: BsheelColors.ink),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? QuestSpacing.md : QuestSpacing.lg,
          vertical: QuestSpacing.xl,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Section(
                  title: 'Privacy Policy & Support',
                  content: 'Last updated: April 2025\n\n'
                      'BSHEEL ("we", "our", or "us") is committed to protecting your privacy. '
                      'This Privacy Policy explains how we collect, use, and safeguard your information '
                      'when you use the BSHEEL mobile application.',
                ),
                const _Section(
                  title: '1. Information We Collect',
                  content:
                      '• Account information: username, display name, email address, and profile photo.\n'
                      '• Quest activity: quest assignments, completion status, XP, and level.\n'
                      '• User-generated content: photos and videos submitted as quest proof, captions, and comments.\n'
                      '• Reactions and follows: interactions with other users\' posts.\n'
                      '• Device information: FCM token for push notifications.\n'
                      '• Usage data: app activity timestamps used for streak tracking.',
                ),
                const _Section(
                  title: '2. How We Use Your Information',
                  content: '• To provide and operate the BSHEEL app.\n'
                      '• To display your profile, posts, and activity to other users.\n'
                      '• To send push notifications about quest assignments, approvals, and social activity.\n'
                      '• To calculate XP, levels, and leaderboard rankings.\n'
                      '• To review submitted quest proof (photo/video) for approval.',
                ),
                const _Section(
                  title: '3. User-Generated Content',
                  content:
                      'Photos and videos you submit as quest proof are visible to other users in the feed. '
                      'Your username, display name, and avatar are publicly visible within the app. '
                      'You can delete your account at any time, which permanently removes all your data.',
                ),
                const _Section(
                  title: '4. Data Storage',
                  content:
                      'Your data is stored securely using Supabase (PostgreSQL database hosted on AWS). '
                      'Media files are stored on Cloudflare R2. '
                      'Push notifications are delivered via Firebase Cloud Messaging.',
                ),
                const _Section(
                  title: '5. Data Sharing',
                  content:
                      'We do not sell your personal data. We do not share your data with third parties '
                      'except as required to operate the service (Supabase, Cloudflare, Firebase) '
                      'or as required by law.',
                ),
                const _Section(
                  title: '6. Children\'s Privacy',
                  content:
                      'BSHEEL is not directed at children under 13. We do not knowingly collect '
                      'personal information from children under 13. If you believe a child has '
                      'provided us with personal information, please contact us immediately.',
                ),
                const _Section(
                  title: '7. Your Rights',
                  content: '• Access your data: visible in your profile.\n'
                      '• Delete your account: available in Settings → Delete Account.\n'
                      '• Contact us: for any data requests or concerns, email us below.',
                ),
                const _Section(
                  title: '8. Changes to This Policy',
                  content:
                      'We may update this Privacy Policy from time to time. '
                      'We will notify you of significant changes via push notification or in-app message.',
                ),
                const SizedBox(height: 32),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(QuestSpacing.lg),
                  decoration: BoxDecoration(
                    color: BsheelColors.paper,
                    borderRadius: BorderRadius.circular(BsheelRadii.md),
                    border: Border.all(
                      color: BsheelColors.ink,
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SUPPORT',
                        style: BsheelType.displaySm.copyWith(
                          color: BsheelColors.primary,
                          fontSize: 14,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Having issues with the app? We\'re here to help.',
                        style: BsheelType.bodySm.copyWith(
                          color: BsheelColors.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 16),
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
                      const SizedBox(height: 16),
                      Text(
                        'We aim to respond within 48 hours.',
                        style: BsheelType.labelSm.copyWith(
                          color: BsheelColors.inkMuted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
                Center(
                  child: Text(
                    '© 2025 BSHEEL. All rights reserved.',
                    style: BsheelType.labelSm.copyWith(
                      color: BsheelColors.inkMuted,
                      fontSize: 10,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.content});
  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: BsheelType.labelLg.copyWith(
              color: BsheelColors.ink,
              fontSize: 14,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: BsheelType.bodySm.copyWith(
              color: BsheelColors.inkSoft,
              height: 1.7,
            ),
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
      spacing: 4,
      children: [
        Icon(icon, size: 16, color: BsheelColors.primary),
        const SizedBox(width: 4),
        Text(
          '$label: ',
          style: BsheelType.labelSm.copyWith(
            color: BsheelColors.inkMuted,
            fontSize: 11,
          ),
        ),
        SelectableText(
          value,
          style: BsheelType.bodySm.copyWith(
            color: BsheelColors.ink,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
