/// Lightweight client-side caption flagging.
///
/// Returns short tags like "SPAM" or "INAPPROPRIATE" that the admin queue can
/// display as warning badges. False positives are acceptable — every flagged
/// submission is still reviewed by a human, the badge is only there to draw
/// the admin's eye to caption patterns that historically warrant rejection.
library;

class CaptionFlags {
  static const String spam = 'SPAM';
  static const String inappropriate = 'INAPPROPRIATE';

  /// Crude link / handle / promotional patterns. Tuned to catch the obvious
  /// cases (DM-me, follow-for-follow, OnlyFans, contact info in the caption)
  /// without going broad enough to flag every casual caption.
  static final RegExp _spamPatterns = RegExp(
    r'(https?://|www\.)'
    r'|(\bdm\s*me\b)'
    r'|(\bfollow\s*me\b)'
    r'|(\bclick\s*here\b)'
    r'|(\bfree\s*\$)'
    r'|(\bonly\s*fans\b)'
    r'|(\bof\s*link\b)'
    r'|(\bl4l\b)'
    r'|(\bf4f\b)'
    r'|(\blike\s*for\s*like\b)'
    r'|(\bfollow\s*back\b)'
    r'|(\b\d{3}[\s\-]?\d{3}[\s\-]?\d{4}\b)'
    r'|([A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,})',
    caseSensitive: false,
  );

  /// Inappropriate keyword list (kept conservative — slurs, explicit-content
  /// solicitations, hate-speech indicators). Casts a small net intentionally;
  /// anything subtler should be caught by the human reviewer, not this list.
  static final RegExp _inappropriatePatterns = RegExp(
    r'\b(nsfw|porn|xxx|sext|nude|nudes|onlyfans)\b'
    r'|\b(slut|whore|bitch|fag|faggot|retard)\b'
    r'|\b(kill\s+(yourself|urself)|kys)\b',
    caseSensitive: false,
  );

  /// Returns the set of flag tags applicable to [caption]. Empty list means no
  /// flags. Used by the pending-submissions card UI to render warning badges.
  static List<String> compute(String? caption) {
    if (caption == null) return const [];
    final trimmed = caption.trim();
    if (trimmed.isEmpty) return const [];

    final flags = <String>[];

    if (_isSpammy(trimmed)) flags.add(spam);
    if (_inappropriatePatterns.hasMatch(trimmed)) flags.add(inappropriate);

    return flags;
  }

  static bool _isSpammy(String text) {
    if (_spamPatterns.hasMatch(text)) return true;

    if (text.length >= 10) {
      final letters = text.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.length >= 10) {
        final caps = letters.replaceAll(RegExp(r'[^A-Z]'), '').length;
        if (caps / letters.length > 0.7) return true;
      }
    }

    if (RegExp(r'(.)\1{5,}').hasMatch(text)) return true;

    return false;
  }
}
