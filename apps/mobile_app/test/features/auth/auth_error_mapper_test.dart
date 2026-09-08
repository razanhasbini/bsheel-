import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/auth/presentation/auth_error_mapper.dart';
import 'package:mobile_app/features/auth/presentation/password_policy.dart';

void main() {
  group('mapAuthError', () {
    test('wrong credentials map to one generic message', () {
      for (final raw in [
        'AuthException: Invalid login credentials',
        'invalid_credentials',
        'Invalid email or password',
        'wrong password entered',
        'user not found',
      ]) {
        expect(mapAuthError(raw), 'Incorrect email or password.', reason: raw);
      }
    });

    test('unconfirmed email tells the user to confirm', () {
      expect(mapAuthError('AuthException: Email not confirmed'),
          'Please confirm your email before logging in.');
      expect(mapAuthError('email_not_confirmed'),
          'Please confirm your email before logging in.');
    });

    test('duplicate email/username maps to "already taken"', () {
      for (final raw in [
        'User already registered',
        'duplicate key value violates unique constraint "profiles_username_key"',
        'A user with this email address has already been registered',
      ]) {
        expect(mapAuthError(raw),
            'That username or email is already taken. Try another one.',
            reason: raw);
      }
    });

    test('invalid email format', () {
      expect(mapAuthError('email_address_invalid'),
          'Please use a valid email address.');
    });

    test('weak password references the real policy minimum', () {
      final msg = mapAuthError('Password is too weak');
      expect(msg, contains('$passwordMinLength characters'));
    });

    test('expired or missing recovery session explains the reset link died',
        () {
      for (final raw in [
        'AuthException: Auth session missing!',
        'AuthApiException: otp_expired',
        'Email link is invalid or has expired: token expired',
        'session_not_found',
      ]) {
        expect(
            mapAuthError(raw),
            'Your reset link has expired or was already used. '
            'Please request a new one.',
            reason: raw);
      }
    });

    test('rate limiting', () {
      expect(mapAuthError('Too many requests'),
          'Too many attempts. Please wait a moment.');
      expect(mapAuthError('status 429'),
          'Too many attempts. Please wait a moment.');
    });

    test('network problems', () {
      for (final raw in [
        'SocketException: Failed host lookup',
        'connection refused',
        'TimeoutException after 30s',
      ]) {
        expect(mapAuthError(raw),
            'No internet connection. Please check your network.',
            reason: raw);
      }
    });

    test('banned account', () {
      expect(
          mapAuthError('User is banned'), 'This account has been suspended.');
    });

    test('short unknown errors pass through with prefixes stripped', () {
      expect(mapAuthError('AuthException: Something odd occurred'),
          'Something odd occurred');
    });

    test('long unknown errors fall back to raw (never empty)', () {
      final out = mapAuthError('');
      expect(out.isNotEmpty, true);
    });
  });
}
