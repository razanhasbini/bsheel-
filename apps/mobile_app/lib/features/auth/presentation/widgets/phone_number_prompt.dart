import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

import '../login_credentials.dart';
import 'auth_field.dart';

/// Nokia's simulator identities. Handy while the app talks to Nokia's
/// simulator rather than a live carrier: +99999991000 verifies true,
/// +99999991001 verifies false. Shown only in debug builds — a release
/// build must never advertise numbers that bypass nothing but confuse
/// everything.
const _simulatorHint =
    'Simulator: +99999991000 verifies, +99999991001 does not.';

/// Asks the user for the number they claim to control.
///
/// Returns the E.164 string, or null if they backed out. The number is only
/// ever a claim: the mobile network decides whether this device is actually
/// using it, and the backend refuses to mark anything verified until it says
/// yes. Collecting it here is what lets Number Verification V1 ask a
/// specific question instead of a general one.
Future<String?> promptForPhoneNumber(
  BuildContext context, {
  required String title,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _PhoneNumberDialog(title: title),
  );
}

class _PhoneNumberDialog extends StatefulWidget {
  const _PhoneNumberDialog({required this.title});

  final String title;

  @override
  State<_PhoneNumberDialog> createState() => _PhoneNumberDialogState();
}

class _PhoneNumberDialogState extends State<_PhoneNumberDialog> {
  final _controller = TextEditingController(text: '+');
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    // Strip the spaces and dashes people naturally type; everything else
    // has to be a real E.164 violation, so we surface it rather than
    // silently "fixing" a number the user did not intend.
    final value = _controller.text.replaceAll(RegExp(r'[\s\-()]'), '');
    if (!e164Pattern.hasMatch(value)) {
      setState(() => _error = 'Use international format, e.g. +96170123456');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: QuestColors.cardBg(context),
      title: Text(
        widget.title.toUpperCase(),
        style: QuestTypography.osLabelLarge.copyWith(
          color: QuestColors.text(context),
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your carrier confirms this number over mobile data — there is no '
            'code to type. Turn Wi-Fi off if verification keeps failing.',
            style: QuestTypography.osBodySmall.copyWith(
              fontSize: 12,
              height: 1.55,
              color: QuestColors.textDim(context),
            ),
          ),
          const SizedBox(height: 14),
          AuthField(
            controller: _controller,
            focusNode: _focus,
            label: 'PHONE NUMBER',
            hint: '+96170123456',
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.telephoneNumber],
            errorText: _error,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
          if (kDebugMode) ...[
            const SizedBox(height: 10),
            Text(
              _simulatorHint,
              style: QuestTypography.osBodySmall.copyWith(
                fontSize: 11,
                height: 1.5,
                color: QuestColors.textDim(context),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('CANCEL'),
        ),
        TextButton(onPressed: _submit, child: const Text('CONTINUE')),
      ],
    );
  }
}
