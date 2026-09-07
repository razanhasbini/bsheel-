import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

import '../../../../l10n/app_localizations.dart';

class TermsPage extends StatelessWidget {
  const TermsPage({super.key});

  @override
  Widget build(BuildContext context) {
    // UX-108: see the matching note in privacy_policy_page.dart. Body
    // remains English until translated.
    return Scaffold(
      backgroundColor: QuestColors.bg(context),
      appBar: AppBar(
        backgroundColor: QuestColors.bg(context),
        title: Text(
          AppLocalizations.of(context)!.termsOfService.toUpperCase(),
          style: QuestTypography.headlineSmall.copyWith(fontSize: 16),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(QuestSpacing.screenPadding),
        child: Text(
          '''TERMS OF SERVICE — BSHEEL

Last updated: March 2026

1. ACCEPTANCE
By using Bsheel, you agree to these terms. If you disagree, do not use the app.

2. THE SERVICE
Bsheel is a gamified quest app where users complete real-world challenges, submit proof, and earn XP. Quests are AI-generated and moderated by admins.

3. USER ACCOUNTS
- You must be 13+ to create an account
- You are responsible for your account security
- One account per person
- Accurate information required

4. USER CONTENT
- You retain ownership of photos/videos you upload
- By uploading, you grant us a license to display your content in the app
- Content must not be illegal, harmful, or violate others' rights
- We may remove content that violates these terms

5. QUEST RULES
- Quests must be completed honestly
- Submitting fake proof may result in account suspension
- Moderator decisions on quest approval are final
- XP and levels may be adjusted if manipulation is detected

6. PROHIBITED CONDUCT
- Cheating or manipulating the quest system
- Uploading inappropriate, illegal, or harmful content
- Harassing other users
- Creating multiple accounts
- Automated or bot-driven activity

7. TERMINATION
We may suspend or terminate accounts that violate these terms without prior notice.

8. DISCLAIMERS
- The app is provided "as is"
- We are not responsible for injuries from quest activities
- Complete quests at your own risk
- We do not guarantee uptime or availability

9. LIMITATION OF LIABILITY
To the maximum extent permitted by law, we are not liable for indirect, incidental, or consequential damages.

10. CHANGES
We may modify these terms at any time. Continued use constitutes acceptance.

11. CONTACT
For questions about these terms: legal@bitsheel.app
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
