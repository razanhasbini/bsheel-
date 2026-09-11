import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';
import 'package:shared_ui/shared_ui.dart';

/// Lets a player say where they are from — optional, and clearable.
///
/// This exists because #50's tourism analytics has no other source: there
/// was no country on a user anywhere in the schema, and the alternative
/// considered was inferring one from CAMARA network data, which would mean
/// deducing where somebody lives from telecom readings they gave us to
/// verify a quest.
///
/// So the field says what it is for, in one line, next to the control that
/// sets it. A country field in a quest app with no explanation invites the
/// reasonable guess that it is being sold.
class CountryPickerField extends StatelessWidget {
  const CountryPickerField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// ISO 3166-1 alpha-2, or null for "not saying".
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    // A short list rather than all 249 codes: these are where Bsheel is
    // actually played, and "Somewhere else" keeps the field honest for
    // everyone not on it instead of forcing a wrong answer.
    const options = <String, String>{
      'LB': 'Lebanon',
      'AE': 'United Arab Emirates',
      'SA': 'Saudi Arabia',
      'QA': 'Qatar',
      'KW': 'Kuwait',
      'BH': 'Bahrain',
      'OM': 'Oman',
      'JO': 'Jordan',
      'EG': 'Egypt',
      'IQ': 'Iraq',
      'SY': 'Syria',
      'TR': 'Türkiye',
      'FR': 'France',
      'DE': 'Germany',
      'GB': 'United Kingdom',
      'US': 'United States',
      'CA': 'Canada',
      'AU': 'Australia',
      'BR': 'Brazil',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('WHERE YOU ARE FROM', style: QuestTypography.osLabelSmall),
        const SizedBox(height: 6),
        ArcadeCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: options.containsKey(value) ? value : null,
              isExpanded: true,
              // Null is a real choice, not an absence of one, so it is the
              // first entry rather than a hint the user cannot get back to.
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Prefer not to say'),
                ),
                for (final entry in options.entries)
                  DropdownMenuItem<String?>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Optional. Places you visit see it only as part of a group total, '
          'and only if you have turned analytics on. It is never shown on '
          'your profile.',
          style: QuestTypography.osBodySmall
              .copyWith(color: QuestColors.textDim(context)),
        ),
      ],
    );
  }
}
