import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

import '../../../../l10n/app_localizations.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    // UX-108: title is now localized. The body text is legal copy that
    // needs a professional translator before it can be served in
    // Lebanese Arabizi. For now, all locales see the English body.
    // TODO(legal): translate the policy body and load per-locale, OR
    // serve it from a Supabase `legal_documents` table keyed by version.
    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      appBar: AppBar(
        backgroundColor: QuestColors.bg(context),
        title: Text(
          AppLocalizations.of(context)!.privacyPolicy.toUpperCase(),
          style: QuestTypography.headlineSmall.copyWith(fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(QuestSpacing.screenPadding),
        child: Text(
          '''PRIVACY POLICY — BSHEEL

Last updated: June 2026

1. INFORMATION WE COLLECT
We collect information you provide when creating an account: email, username, display name, and profile picture. We also collect quest completion data, submissions (photos/videos), and (only if you explicitly opt in) anonymous usage analytics.

2. HOW WE USE YOUR INFORMATION
- To provide and maintain the app
- To process quest submissions and rewards
- To display your profile and activity in the feed
- To send notifications about quest status
- To route submissions to our human moderation team (see §4)

3. DATA STORAGE
Your data is stored on Supabase (Postgres + Auth + Storage, EU/US region). Media files are uploaded to Cloudflare R2 and served via signed URLs that expire within 15 minutes. Notification tokens are stored in a private database table accessible only by our backend.

4. DATA SHARING
We do not sell your personal data. The following SHARING happens by design:
   (a) Your quest submissions and profile are visible to other signed-in users via the in-app feed and leaderboard.
   (b) When you submit a quest, the submission caption, media URL, your username, and the quest title are forwarded to our private moderation team channel on Telegram so a human can approve or reject the submission within the SLA. The Telegram channel is private and not accessible to other users. When you delete a submission or your account, the corresponding moderation message is also removed.
   (c) Anonymous usage events are sent to Mixpanel ONLY after you tap "OK, SHARE" on the analytics consent prompt during onboarding. You can revoke at any time from Settings.

5. DATA RETENTION
Account data is retained until you delete your account. Upon deletion, all personal data is permanently removed within 30 days. The corresponding Telegram moderation messages are deleted at the same time. Media files in R2 are removed by a scheduled cleanup job.

6. YOUR RIGHTS
You can:
- Access your data through the app
- Update your profile information
- Delete your account and all associated data
- Request a copy of your data by contacting us

7. SECURITY
We use industry-standard encryption and security measures to protect your data.

8. CHILDREN'S PRIVACY
Bsheel is not intended for children under 13. We do not knowingly collect data from children.

9. CHANGES
We may update this policy. Continued use of the app constitutes acceptance of changes.

10. CONTACT
For privacy questions, contact: privacy@bitsheel.app
''',
          style: QuestTypography.bodyMedium.copyWith(
            color: QuestColors.textSub(context),
            height: 1.6,
          ),
        ),
      ),
    );
  }
}
