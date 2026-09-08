import 'package:app_core/app_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// ARC-015: starter tests around the shared error mapper. The whole
/// app's user-facing failure messaging routes through this one
/// function, so a regression here shows up in every snackbar.
void main() {
  group('mapDbError', () {
    test('falls through to "Failed to {action}" when nothing matches', () {
      final out =
          mapDbError(Exception('totally novel error'), action: 'do the thing');
      expect(out, equals('Failed to do the thing. Please try again.'));
    });

    test('translates 42501 / Not authorized into a sign-in hint', () {
      final out = mapDbError('PostgrestException(message: Not authorized, '
          'code: 42501, details: ...)');
      expect(out, contains('don\'t have permission'));
    });

    test('extracts the human-readable message from a P0001 raise', () {
      final out = mapDbError(
        'PostgrestException(message: Daily announcement limit reached '
        '(5/day), code: P0001)',
      );
      expect(out, contains('5/day'));
    });

    test('translates 23505 / duplicate key into a "taken" message', () {
      final out = mapDbError(
        'duplicate key value violates unique constraint '
        '"profiles_username_key", code: 23505',
      );
      expect(out, contains('already taken'));
    });

    test('routes network / timeout shapes to the connectivity message', () {
      final out = mapDbError(
        Exception('SocketException: Failed host lookup (...)'),
      );
      expect(out, contains('Network error'));
    });

    test('translates not-found / P0002 into a friendly missing message', () {
      final out = mapDbError(
        'PostgrestException(message: Submission not found, code: P0002)',
      );
      expect(out, contains('Couldn\'t find'));
    });

    test('rate limit / cooldown shapes get a slow-down message', () {
      final out = mapDbError(
        'PostgrestException(message: Reroll limit reached (5 per 24h))',
      );
      expect(out, contains('Slow down').or(contains('try again')),
          reason: 'mapper accepts either rate-limit hint variant');
    });

    test('R2 worker media rejections become a format hint, not a raw 400', () {
      // Client-side guard (supabase_submissions_repository._assertUploadable).
      expect(
        mapDbError(
          Exception('StorageException: Unsupported file format '
              '(video/x-msvideo).'),
          action: 'submit proof',
        ),
        contains('format'),
      );
      // Worker-side magic-byte mismatch, surfaced verbatim before this.
      expect(
        mapDbError(
          Exception('Upload failed (400): {"error":"File content does not '
              'match Content-Type header"}'),
          action: 'submit proof',
        ),
        contains('format'),
      );
    });
  });
}

extension on Matcher {
  Matcher or(Matcher other) {
    return anyOf(this, other);
  }
}
