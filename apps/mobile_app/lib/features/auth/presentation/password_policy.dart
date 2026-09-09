/// Shared password policy used by signup and reset-password.
///
/// Keep this file as the *single source of truth*. Both pages call into
/// it so the rule set never drifts between forms. The matching server-
/// side enforcement lives in the Supabase project (Authentication →
/// Sign In/Up → Email → Password Strength + Leaked Password Protection)
/// — make sure those are at least as strict as the rules below or the
/// client validation can be bypassed by direct API calls.
library;

/// Minimum password length. NIST 800-63B treats length as the primary
/// strength signal, so we lean into that here.
const int passwordMinLength = 10;

/// Substrings that are never allowed in a password (case-insensitive),
/// regardless of how the rest of it is composed. Keep this list short —
/// it catches the trivially obvious "Bsheel123!"-style passwords without
/// becoming a denylist treadmill. The HIBP integration in Supabase Auth
/// (Leaked Password Protection) handles the long tail.
const List<String> _bannedSubstrings = [
  'bsheel',
  'bitsheel',
  'password',
  'qwerty',
  '123456',
  'letmein',
];

/// Validate a password against the project policy.
///
/// Returns `null` if valid, or a short user-facing error string. Passing
/// [username] / [emailLocalPart] enables additional checks that the
/// password isn't simply derived from the user's identity (e.g. you
/// can't sign up as `tayseer` with the password `Tayseer12345`).
String? validatePassword(
  String password, {
  String? username,
  String? emailLocalPart,
}) {
  if (password.length < passwordMinLength) {
    return 'At least $passwordMinLength characters.';
  }
  if (!RegExp(r'[A-Z]').hasMatch(password) ||
      !RegExp(r'[a-z]').hasMatch(password) ||
      !RegExp(r'[0-9]').hasMatch(password)) {
    return 'Mix uppercase, lowercase, and a number.';
  }

  final lower = password.toLowerCase();

  // Reject substrings of the user's own identity. Trim to ≥ 4 chars so
  // a user named "Jo" doesn't get blocked from using "jo" anywhere in
  // their password.
  bool containsIdentity(String? raw) {
    if (raw == null) return false;
    final needle = raw.toLowerCase().trim();
    if (needle.length < 4) return false;
    return lower.contains(needle);
  }

  if (containsIdentity(username) || containsIdentity(emailLocalPart)) {
    return 'Don\'t reuse your name or email in your password.';
  }

  for (final banned in _bannedSubstrings) {
    if (lower.contains(banned)) {
      return 'That password is too common — pick something less guessable.';
    }
  }

  return null;
}

/// How many of the signup frame's four strength segments to fill, 0-4.
///
/// Presentation only — [validatePassword] stays the gate. It lives here so
/// the meter and the validator read the same signals: length, mixed case,
/// a digit, and then real length as the fourth.
int passwordStrength(String password) {
  if (password.isEmpty) return 0;
  var score = 0;
  if (password.length >= 8) score++;
  if (RegExp(r'[A-Z]').hasMatch(password) &&
      RegExp(r'[a-z]').hasMatch(password)) {
    score++;
  }
  if (RegExp(r'[0-9]').hasMatch(password)) score++;
  if (password.length >= passwordMinLength &&
      RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    score++;
  }
  return score;
}
