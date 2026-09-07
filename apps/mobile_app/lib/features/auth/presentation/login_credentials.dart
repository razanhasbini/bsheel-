/// Shared email regex used across login, signup, and forgot-password pages.
final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

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
