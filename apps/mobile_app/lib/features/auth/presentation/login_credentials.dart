/// Shared email regex used across login, signup, and forgot-password pages.
final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// E.164 — the only shape CAMARA Number Verification accepts: a leading
/// '+', a non-zero country code, then digits. Mirrors the backend check in
/// auth.dto.ts; the client copy exists to fail fast with a useful message,
/// not as a security boundary.
final e164Pattern = RegExp(r'^\+[1-9]\d{6,14}$');

abstract final class LoginCredentials {
  /// Trim + lower-case so `Foo@Bar.com` resolves to the same account the
  /// signup page created (signup lower-cases before calling Supabase).
  static String normalizeIdentifier(String value) {
    return value.trim().toLowerCase();
  }

  static String? validateIdentifier(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return 'Email is required';
    }
    if (!emailPattern.hasMatch(trimmed)) {
      return 'Please enter a valid email address.';
    }
    return null;
  }
}
