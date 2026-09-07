import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/features/auth/presentation/password_policy.dart';

/// ARC-015: pin the password policy so a regression here doesn't quietly
/// allow a weaker password to slip through. The Supabase Auth dashboard
/// settings + the admin_manage_user edge function both mirror this rule
/// set, so changes need to land in three places at once.
void main() {
  group('validatePassword', () {
    test('accepts a strong password', () {
      expect(validatePassword('Str0ngPass123'), isNull);
    });

    test('rejects short passwords with a length hint', () {
      expect(validatePassword('Sh0rt'), contains('10 characters'));
    });

    test('rejects passwords missing uppercase', () {
      expect(validatePassword('lowercase123!'), contains('uppercase'));
    });

    test('rejects passwords missing lowercase', () {
      expect(validatePassword('UPPER12345!'), contains('lowercase'));
    });

    test('rejects passwords missing digits', () {
      expect(validatePassword('NoDigitsHere!'), contains('number'));
    });

    test('rejects passwords containing the username', () {
      expect(
        validatePassword('Tayseer-Pa55word', username: 'tayseer'),
        contains('name'),
      );
    });

    test('rejects passwords containing the email local-part', () {
      expect(
        validatePassword('Hello-tayseer-X1', emailLocalPart: 'tayseer'),
        contains('email'),
      );
    });

    test('rejects banned substrings even with otherwise-valid shape', () {
      expect(validatePassword('Bsheel123Pass'), contains('common'));
      expect(validatePassword('Qwerty111Z'), contains('common'));
    });

    test('short usernames (<4 chars) do not trigger the identity check', () {
      // A user named "Jo" should not be blocked from putting "jo" anywhere.
      expect(validatePassword('Joke12345Z', username: 'Jo'), isNull);
    });
  });
}
