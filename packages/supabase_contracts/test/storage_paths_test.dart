import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('StorageBuckets', () {
    test('are exactly the 2 buckets, lowercase and distinct', () {
      expect(
        {StorageBuckets.avatars, StorageBuckets.submissions},
        {'avatars', 'submissions'},
      );
      expect(StorageBuckets.avatars, isNot(StorageBuckets.submissions));
      for (final bucket in [
        StorageBuckets.avatars,
        StorageBuckets.submissions,
      ]) {
        expect(bucket, isNotEmpty);
        expect(bucket, bucket.toLowerCase());
        expect(bucket.contains('/'), isFalse);
      }
    });
  });

  group('StoragePaths.avatarPath', () {
    test('defaults to a .jpg extension', () {
      expect(StoragePaths.avatarPath('user-1'), 'avatars/user-1/avatar.jpg');
    });

    test('honours an explicit extension without a leading dot', () {
      expect(
        StoragePaths.avatarPath('user-1', ext: 'png'),
        'avatars/user-1/avatar.png',
      );
      expect(
        StoragePaths.avatarPath('user-1', ext: 'webp'),
        'avatars/user-1/avatar.webp',
      );
    });

    test('is prefixed with the avatars bucket name', () {
      expect(
        StoragePaths.avatarPath('user-1'),
        startsWith('${StorageBuckets.avatars}/'),
      );
    });

    test('is stable per user — one avatar object, overwritten in place', () {
      // Two calls for the same user must collide, otherwise old avatars
      // accumulate in the bucket forever.
      expect(
        StoragePaths.avatarPath('user-1'),
        StoragePaths.avatarPath('user-1'),
      );
      expect(
        StoragePaths.avatarPath('user-1'),
        isNot(StoragePaths.avatarPath('user-2')),
      );
    });

    test('an extension already carrying a dot double-dots the path', () {
      // ACTUAL behaviour: the helper interpolates blindly. Callers must pass
      // the extension without the leading dot, as the doc comment says.
      expect(
        StoragePaths.avatarPath('user-1', ext: '.png'),
        'avatars/user-1/avatar..png',
      );
    });
  });

  group('StoragePaths.submissionPath', () {
    test('nests the submission under the owning user', () {
      expect(
        StoragePaths.submissionPath('user-1', 'sub-1'),
        'submissions/user-1/sub-1',
      );
    });

    test('is prefixed with the submissions bucket name', () {
      expect(
        StoragePaths.submissionPath('user-1', 'sub-1'),
        startsWith('${StorageBuckets.submissions}/'),
      );
    });

    test('carries no extension — the media type is stored out of band', () {
      expect(
        StoragePaths.submissionPath('user-1', 'sub-1').contains('.'),
        isFalse,
      );
    });

    test('the user segment comes first (RLS prefix matching depends on it)',
        () {
      // The storage policies match on the second path segment being the
      // caller's uid, so argument order here is security-relevant.
      expect(
        StoragePaths.submissionPath('user-1', 'sub-1').split('/'),
        ['submissions', 'user-1', 'sub-1'],
      );
    });
  });

  group('WorkerUrls', () {
    test('the R2 upload worker is an absolute https URL', () {
      final uri = Uri.parse(WorkerUrls.r2Upload);

      expect(uri.scheme, 'https');
      expect(uri.host, isNotEmpty);
      expect(uri.hasAuthority, isTrue);
    });

    test('has no trailing slash — callers append their own path', () {
      expect(WorkerUrls.r2Upload.endsWith('/'), isFalse);
    });
  });

  group('WorkerMediaTypes', () {
    test('the image set mirrors the worker allowlist exactly', () {
      expect(WorkerMediaTypes.image, {
        'image/jpeg',
        'image/png',
        'image/gif',
        'image/webp',
      });
    });

    test('the video set mirrors the worker allowlist exactly', () {
      expect(WorkerMediaTypes.video, {
        'video/mp4',
        'video/quicktime',
        'video/webm',
      });
    });

    test('every image entry is prefixed with the image MediaType', () {
      for (final type in WorkerMediaTypes.image) {
        expect(type, startsWith('${MediaType.image}/'));
      }
    });

    test('every video entry is prefixed with the video MediaType', () {
      for (final type in WorkerMediaTypes.video) {
        expect(type, startsWith('${MediaType.video}/'));
      }
    });

    test('the two sets are disjoint and lowercase', () {
      expect(
        WorkerMediaTypes.image.intersection(WorkerMediaTypes.video),
        isEmpty,
      );
      for (final type in {
        ...WorkerMediaTypes.image,
        ...WorkerMediaTypes.video
      }) {
        expect(type, type.toLowerCase());
        expect(type.split('/'), hasLength(2));
      }
    });

    group('isAllowed', () {
      test('accepts every declared image and video type', () {
        for (final type in {
          ...WorkerMediaTypes.image,
          ...WorkerMediaTypes.video,
        }) {
          expect(
            WorkerMediaTypes.isAllowed(type),
            isTrue,
            reason: '$type should be allowed',
          );
        }
      });

      test('rejects unlisted and malformed content types', () {
        for (final type in [
          '',
          'image/heic',
          'image/svg+xml',
          'video/avi',
          'application/pdf',
          'text/html',
          'image',
          'jpeg',
        ]) {
          expect(
            WorkerMediaTypes.isAllowed(type),
            isFalse,
            reason: '"$type" must not be allowed',
          );
        }
      });

      test('is case-sensitive and does not tolerate parameters', () {
        // The worker compares the raw header, so the client must normalise
        // before asking. Pinned so a future "helpful" trim/lowercase here
        // does not silently diverge from the worker.
        expect(WorkerMediaTypes.isAllowed('IMAGE/JPEG'), isFalse);
        expect(
            WorkerMediaTypes.isAllowed('image/jpeg; charset=binary'), isFalse);
        expect(WorkerMediaTypes.isAllowed(' image/jpeg'), isFalse);
      });

      test('does not allow the bare MediaType tokens', () {
        // MediaType.image is a DB enum value, not a MIME type.
        expect(WorkerMediaTypes.isAllowed(MediaType.image), isFalse);
        expect(WorkerMediaTypes.isAllowed(MediaType.video), isFalse);
        expect(WorkerMediaTypes.isAllowed(MediaType.mixed), isFalse);
      });
    });
  });
}
