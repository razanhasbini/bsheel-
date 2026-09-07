import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/auth/presentation/login_credentials.dart';

void main() {
  group('LoginCredentials', () {
    test('normalizeIdentifier trims whitespace and lower-cases', () {
      expect(
        LoginCredentials.normalizeIdentifier(' player@example.com '),
        'player@example.com',
      );
      // Signup lower-cases before calling Supabase; login must match or
      // `Foo@Bar.com` and `foo@bar.com` would act like different accounts.
      expect(
        LoginCredentials.normalizeIdentifier('Player@Example.COM'),
        'player@example.com',
      );
    });

    test('accepts email identifiers and rejects non-email usernames', () {
      expect(
        LoginCredentials.validateIdentifier('player@example.com'),
        isNull,
      );
      expect(
        LoginCredentials.validateIdentifier('admin'),
        'Please enter a valid email address.',
      );
      expect(
        LoginCredentials.validateIdentifier(''),
        'Email is required',
      );
    });
  });
}
