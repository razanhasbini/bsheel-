import 'password_policy.dart';

/// Maps raw Supabase/network errors to user-friendly messages.
///
/// Used across login, signup, complete-profile, onboarding, and
/// reset-password pages so error strings stay consistent.
String mapAuthError(String raw) {
  final msg = raw.toLowerCase();

  // ── CAMARA Number Verification ───────────────────────────────
  // The carrier's "no" is a different fact from the carrier being
  // unreachable: one means check the number, the other means try again.
  // Say which, rather than collapsing both into "sign-in failed".
  if (msg.contains('phone_number_not_verified')) {
    return 'We could not confirm that number belongs to this phone. '
        'Check the number, and make sure mobile data is on — your carrier '
        'verifies it over the cellular connection, not Wi-Fi.';
  }
  if (msg.contains('number_verification_unavailable')) {
    return 'Could not reach your carrier to check that number. '
        'Please try again in a moment.';
  }
  if (msg.contains('phone_signin_not_configured')) {
    return 'Phone verification is not available right now.';
  }
  if (msg.contains('invalid_phone_signin_state')) {
    return 'That verification link expired. Please start again.';
  }

  // ── Credentials ──────────────────────────────────────────────
  if (msg.contains('invalid login') ||
      msg.contains('invalid_credentials') ||
      msg.contains('invalid email or password') ||
      msg.contains('wrong password') ||
      msg.contains('user not found')) {
    return 'Incorrect email or password.';
  }

  // ── Email confirmation ───────────────────────────────────────
  if (msg.contains('email_not_confirmed') ||
      msg.contains('email not confirmed')) {
    return 'Please confirm your email before logging in.';
  }

  // ── Duplicate / already exists ───────────────────────────────
  if (msg.contains('duplicate') ||
      msg.contains('unique') ||
      msg.contains('already registered') ||
      msg.contains('already been registered') ||
      msg.contains('user already') ||
      msg.contains('email already')) {
    return 'That username or email is already taken. Try another one.';
  }

  // ── Email format ─────────────────────────────────────────────
  if (msg.contains('email_address_invalid') ||
      msg.contains('email address') && msg.contains('invalid')) {
    return 'Please use a valid email address.';
  }

  // ── Weak password ────────────────────────────────────────────
  if (msg.contains('password') &&
      (msg.contains('weak') ||
          msg.contains('short') ||
          msg.contains('strength'))) {
    return 'Password is too weak. Use at least $passwordMinLength characters '
        'with uppercase and numbers.';
  }

  // ── Expired / missing recovery session (reset-password link) ─
  if (msg.contains('session missing') ||
      msg.contains('session_not_found') ||
      msg.contains('otp_expired') ||
      (msg.contains('token') && msg.contains('expired'))) {
    return 'Your reset link has expired or was already used. '
        'Please request a new one.';
  }

  // ── Rate limiting ────────────────────────────────────────────
  if (msg.contains('rate limit') ||
      msg.contains('too many requests') ||
      msg.contains('429')) {
    return 'Too many attempts. Please wait a moment.';
  }

  // ── Network / connectivity ───────────────────────────────────
  if (msg.contains('network') ||
      msg.contains('socket') ||
      msg.contains('connection') ||
      msg.contains('timeout') ||
      msg.contains('no internet')) {
    return 'No internet connection. Please check your network.';
  }

  // ── Banned ───────────────────────────────────────────────────
  if (msg.contains('user is banned') || msg.contains('banned')) {
    return 'This account has been suspended.';
  }

  // ── Database / save errors ───────────────────────────────────
  if (msg.contains('database error') || msg.contains('error saving')) {
    return 'Something went wrong saving your data. Please try again.';
  }

  // ── Fallback: strip exception prefixes and show if short ─────
  final clean = raw
      .replaceAll('AuthException: ', '')
      .replaceAll('Exception: ', '')
      .replaceAll('PostgrestException: ', '');
  if (clean.isNotEmpty && clean.length < 120) return clean;
  return clean.isNotEmpty ? clean : 'Something went wrong. Please try again.';
}
