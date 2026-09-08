import 'package:flutter/material.dart';
import 'package:app_core/app_core.dart';

import '../../core/theme/bsheel_design.dart';

class DeleteAccountPage extends StatefulWidget {
  const DeleteAccountPage({super.key});

  @override
  State<DeleteAccountPage> createState() => _DeleteAccountPageState();
}

class _DeleteAccountPageState extends State<DeleteAccountPage> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _submitted = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

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
            child: _submitted ? _buildConfirmation() : _buildForm(),
          ),
        ),
      ),
    );
  }

  Widget _buildConfirmation() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Icon(
          Icons.check_circle_outline,
          size: 80,
          color: BsheelColors.onCream(BsheelColors.success),
        ),
        const SizedBox(height: 24),
        Text(
          'REQUEST SUBMITTED',
          style: BsheelType.displaySm.copyWith(
            color: BsheelColors.ink,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Your account deletion request has been received.',
          style: BsheelType.bodyMd.copyWith(
            color: BsheelColors.inkSoft,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: QuestSpacing.lg,
            vertical: QuestSpacing.md,
          ),
          decoration: BoxDecoration(
            color: BsheelColors.accent.withAlpha(30),
            borderRadius: BorderRadius.circular(BsheelRadii.md),
            border: Border.all(color: BsheelColors.ink, width: 1),
          ),
          child: Text(
            'It can take up to 48 hours to delete your account.',
            style: BsheelType.bodyMd.copyWith(
              color: BsheelColors.ink,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'If you have any questions, contact us at laztayseer@gmail.com',
          style: BsheelType.bodySm.copyWith(
            color: BsheelColors.inkMuted,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 60),
        Center(
          child: Text(
            '© 2025 BSHEEL. All rights reserved.',
            style: BsheelType.labelSm.copyWith(
              color: BsheelColors.inkMuted,
              fontSize: 10,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DELETE YOUR ACCOUNT',
          style: BsheelType.displaySm.copyWith(
            color: BsheelColors.ink,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Last updated: April 2025',
          style: BsheelType.bodySm.copyWith(
            color: BsheelColors.inkMuted,
          ),
        ),
        const SizedBox(height: 32),
        const _Section(
          title: 'How to Delete Your Account',
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
          title: 'What Gets Deleted',
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
          title: 'Data Retention',
          content:
              'All personally identifiable data is deleted immediately upon account deletion. '
              'No data is retained after the deletion is confirmed. '
              'Anonymised aggregated statistics (e.g. total quest completions) may remain '
              'but cannot be linked back to you.',
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(QuestSpacing.lg),
          decoration: BoxDecoration(
            color: BsheelColors.paper,
            borderRadius: BorderRadius.circular(BsheelRadii.md),
            border: Border.all(
              color: BsheelColors.danger,
              width: BsheelBorders.thin,
            ),
          ),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REQUEST ACCOUNT DELETION',
                  style: BsheelType.displaySm.copyWith(
                    color: BsheelColors.onCream(BsheelColors.danger),
                    fontSize: 14,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Enter the email address associated with your account and we will process the deletion.',
                  style: BsheelType.bodySm.copyWith(
                    color: BsheelColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailController,
                  style: BsheelType.bodyMd,
                  decoration: InputDecoration(
                    hintText: 'your@email.com',
                    hintStyle: BsheelType.bodySm.copyWith(
                      color: BsheelColors.inkMuted,
                    ),
                    prefixIcon: const Icon(
                      Icons.email_outlined,
                      size: 18,
                      color: BsheelColors.inkMuted,
                    ),
                    filled: true,
                    fillColor: BsheelColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BsheelRadii.md),
                      borderSide: const BorderSide(
                        color: BsheelColors.ink,
                        width: 1,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BsheelRadii.md),
                      borderSide: const BorderSide(
                        color: BsheelColors.ink,
                        width: 1,
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BsheelRadii.md),
                      borderSide:
                          const BorderSide(color: BsheelColors.hot, width: 1),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(BsheelRadii.md),
                      borderSide:
                          const BorderSide(color: BsheelColors.hot, width: 1),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
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
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        setState(() => _submitted = true);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: BsheelColors.danger,
                      foregroundColor:
                          BsheelColors.onAccent(BsheelColors.danger),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(BsheelRadii.md),
                        side: const BorderSide(
                          color: BsheelColors.ink,
                          width: 1,
                        ),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'DELETE MY ACCOUNT',
                      style: BsheelType.labelLg.copyWith(
                        color: BsheelColors.onAccent(BsheelColors.danger),
                        fontSize: 14,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
