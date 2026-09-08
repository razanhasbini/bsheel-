import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> submissionRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      SubmissionColumns.id: 'sub-1',
      SubmissionColumns.userQuestId: 'uq-1',
      SubmissionColumns.userId: 'user-1',
      SubmissionColumns.mediaUrl: 'https://cdn.test/a.jpg',
      SubmissionColumns.mediaType: MediaType.image,
      SubmissionColumns.caption: 'first light',
      SubmissionColumns.status: SubmissionStatus.approved,
      SubmissionColumns.reviewedBy: 'admin-1',
      SubmissionColumns.reviewNote: 'looks good',
      SubmissionColumns.submittedAt: '2026-05-03T12:00:00Z',
      SubmissionColumns.reviewedAt: '2026-05-03T13:00:00Z',
      SubmissionColumns.appealNote: null,
      SubmissionColumns.appealed: false,
      SubmissionColumns.showInFeed: true,
      SubmissionColumns.visibility: SubmissionVisibility.visible,
      SubmissionColumns.deletedAt: null,
      ...overrides,
    };

SubmissionModel parse({Map<String, dynamic> overrides = const {}}) =>
    SubmissionModel.fromJson(submissionRow(overrides: overrides));

void main() {
  group('SubmissionModel.fromJson', () {
    test('parses the full wire row', () {
      final sub = parse();

      expect(sub.id, 'sub-1');
      expect(sub.userQuestId, 'uq-1');
      expect(sub.userId, 'user-1');
      expect(sub.mediaUrl, 'https://cdn.test/a.jpg');
      expect(sub.mediaType, 'image');
      expect(sub.caption, 'first light');
      expect(sub.status, 'approved');
      expect(sub.reviewedBy, 'admin-1');
      expect(sub.reviewNote, 'looks good');
      expect(sub.submittedAt, DateTime.utc(2026, 5, 3, 12));
      expect(sub.reviewedAt, DateTime.utc(2026, 5, 3, 13));
      expect(sub.appealNote, isNull);
      expect(sub.appealed, isFalse);
      expect(sub.showInFeed, isTrue);
      expect(sub.visibility, 'visible');
      expect(sub.deletedAt, isNull);
    });

    test('a minimal row (only submitted_at) falls back to every default', () {
      final sub = SubmissionModel.fromJson({
        SubmissionColumns.submittedAt: '2026-05-03T12:00:00Z',
      });

      expect(sub.id, isEmpty);
      expect(sub.userQuestId, isEmpty);
      expect(sub.userId, isEmpty);
      expect(sub.mediaUrl, isEmpty);
      expect(sub.mediaType, MediaType.image);
      expect(sub.status, SubmissionStatus.pending);
      expect(sub.visibility, SubmissionVisibility.visible);
      expect(sub.appealed, isFalse);
      expect(sub.showInFeed, isTrue);
      expect(sub.caption, isNull);
      expect(sub.reviewedAt, isNull);
      expect(sub.questTitle, isNull);
      expect(sub.authorUsername, isNull);
      expect(sub.authorDisplayName, isNull);
    });

    test('a missing or malformed submitted_at degrades to the epoch', () {
      // Regression guard. submitted_at used to be `DateTime.parse(x as
      // String)`, so a single row with a NULL/garbage timestamp threw a
      // TypeError that took down the whole page of submissions. A required
      // timestamp now degrades to the Unix epoch — one wrong date instead
      // of one dead list.
      final epoch = DateTime.utc(1970);

      expect(SubmissionModel.fromJson({}).submittedAt, epoch);
      expect(
        parse(overrides: {SubmissionColumns.submittedAt: null}).submittedAt,
        epoch,
      );
      expect(
        parse(overrides: {SubmissionColumns.submittedAt: 'lunchtime'})
            .submittedAt,
        epoch,
      );
    });

    test('an unparseable reviewed_at becomes null, never "now"', () {
      // Optional timestamps degrade to null so "not reviewed" stays
      // distinguishable from "reviewed at some fallback time".
      expect(
        parse(overrides: {SubmissionColumns.reviewedAt: 'soon'}).reviewedAt,
        isNull,
      );
    });

    test('numeric ids stringify instead of throwing', () {
      final sub = parse(overrides: {
        SubmissionColumns.id: 42,
        SubmissionColumns.userId: 7,
      });

      expect(sub.id, '42');
      expect(sub.userId, '7');
    });

    test('a non-string media_type throws (hard cast)', () {
      expect(
        () => parse(overrides: {SubmissionColumns.mediaType: 1}),
        throwsA(isA<TypeError>()),
      );
    });

    group('appealed coercion', () {
      test('a real boolean reads through', () {
        expect(parse(overrides: {SubmissionColumns.appealed: true}).appealed,
            isTrue);
        expect(parse(overrides: {SubmissionColumns.appealed: false}).appealed,
            isFalse);
      });

      test('a stringly-typed "true" now reads as appealed', () {
        // Regression guard. This was `json[...] == true`, which never
        // coerced — a backend that serialised the flag as the string 'true'
        // silently hid every appeal from the moderation queue.
        expect(parse(overrides: {SubmissionColumns.appealed: 'true'}).appealed,
            isTrue);
        expect(
          parse(overrides: {SubmissionColumns.appealed: ' TRUE '}).appealed,
          isTrue,
        );
        expect(parse(overrides: {SubmissionColumns.appealed: 'false'}).appealed,
            isFalse);
      });

      test('null / missing read as not-appealed (the DB column default)', () {
        // `appealed boolean not null default false` (migration 0048), and
        // an absent key only means this select did not ask for it.
        expect(parse(overrides: {SubmissionColumns.appealed: null}).appealed,
            isFalse);
        final row = submissionRow()..remove(SubmissionColumns.appealed);
        expect(SubmissionModel.fromJson(row).appealed, isFalse);
      });

      test('an unrecognisable value fails towards appealed', () {
        // The row DID carry a signal we could not read. Surfacing an appeal
        // that is not one costs a moderator a glance; dropping a real one
        // leaves the user with no recourse.
        expect(
            parse(overrides: {SubmissionColumns.appealed: 1}).appealed, isTrue);
        expect(parse(overrides: {SubmissionColumns.appealed: 'yes'}).appealed,
            isTrue);
      });
    });

    group('show_in_feed coercion', () {
      test('a real boolean reads through', () {
        expect(
          parse(overrides: {SubmissionColumns.showInFeed: false}).showInFeed,
          isFalse,
        );
        expect(
          parse(overrides: {SubmissionColumns.showInFeed: true}).showInFeed,
          isTrue,
        );
      });

      test('a stringly-typed "false" now hides the post', () {
        // Regression guard. This was `json[...] != false`, which failed
        // OPEN: the string 'false' left a moderator-hidden submission in
        // the feed.
        expect(
          parse(overrides: {SubmissionColumns.showInFeed: 'false'}).showInFeed,
          isFalse,
        );
        expect(
          parse(overrides: {SubmissionColumns.showInFeed: ' FALSE '})
              .showInFeed,
          isFalse,
        );
        expect(
          parse(overrides: {SubmissionColumns.showInFeed: 'true'}).showInFeed,
          isTrue,
        );
      });

      test('null / missing stay visible (the DB column default)', () {
        // `show_in_feed boolean not null default true` (migration 0049).
        // Absence means the select did not project the column, so it
        // carries no signal — defaulting it to hidden would blank the feed.
        expect(
          parse(overrides: {SubmissionColumns.showInFeed: null}).showInFeed,
          isTrue,
        );
        final row = submissionRow()..remove(SubmissionColumns.showInFeed);
        expect(SubmissionModel.fromJson(row).showInFeed, isTrue);
      });

      test('an unrecognisable value fails closed to hidden', () {
        // A visibility flag we cannot read must not be read as visible:
        // showing content meant to be hidden is the harmful direction.
        expect(
          parse(overrides: {SubmissionColumns.showInFeed: 1}).showInFeed,
          isFalse,
        );
        expect(
          parse(overrides: {SubmissionColumns.showInFeed: 'nope'}).showInFeed,
          isFalse,
        );
      });
    });

    test('deleted_at parses when present', () {
      expect(
        parse(overrides: {
          SubmissionColumns.deletedAt: '2026-06-01T00:00:00Z',
        }).deletedAt,
        DateTime.utc(2026, 6, 1),
      );
    });
  });

  group('SubmissionModel joined fields', () {
    test('reads quests.title through a nested object join', () {
      final sub = parse(overrides: {
        Tables.userQuests: <String, dynamic>{
          Tables.quests: <String, dynamic>{QuestColumns.title: 'Photo walk'},
        },
      });

      expect(sub.questTitle, 'Photo walk');
    });

    test('reads quests.title through an array-shaped join', () {
      final sub = parse(overrides: {
        Tables.userQuests: <String, dynamic>{
          Tables.quests: <dynamic>[
            <String, dynamic>{QuestColumns.title: 'Photo walk'},
          ],
        },
      });

      expect(sub.questTitle, 'Photo walk');
    });

    test('an empty array join yields null, not a crash', () {
      final sub = parse(overrides: {
        Tables.userQuests: <String, dynamic>{Tables.quests: <dynamic>[]},
      });

      expect(sub.questTitle, isNull);
    });

    test('a user_quests join with no quests child yields null', () {
      final sub = parse(overrides: {
        Tables.userQuests: <String, dynamic>{UserQuestColumns.id: 'uq-1'},
      });

      expect(sub.questTitle, isNull);
    });

    test('reads the author profile through an object join', () {
      final sub = parse(overrides: {
        Tables.profiles: <String, dynamic>{
          ProfileColumns.username: 'ada',
          ProfileColumns.displayName: 'Ada L.',
        },
      });

      expect(sub.authorUsername, 'ada');
      expect(sub.authorDisplayName, 'Ada L.');
    });

    test('reads the author profile through an array join', () {
      final sub = parse(overrides: {
        Tables.profiles: <dynamic>[
          <String, dynamic>{
            ProfileColumns.username: 'ada',
            ProfileColumns.displayName: 'Ada L.',
          },
        ],
      });

      expect(sub.authorUsername, 'ada');
      expect(sub.authorDisplayName, 'Ada L.');
    });

    test('a profile join missing display_name yields null for that field', () {
      final sub = parse(overrides: {
        Tables.profiles: <String, dynamic>{ProfileColumns.username: 'ada'},
      });

      expect(sub.authorUsername, 'ada');
      expect(sub.authorDisplayName, isNull);
    });
  });

  group('SubmissionModel.mediaUrls', () {
    test('a bare URL yields a single-element list', () {
      expect(
        parse(overrides: {
          SubmissionColumns.mediaUrl: 'https://cdn.test/a.jpg',
        }).mediaUrls,
        ['https://cdn.test/a.jpg'],
      );
    });

    test('a JSON-encoded array yields every URL in order', () {
      expect(
        parse(overrides: {
          SubmissionColumns.mediaUrl:
              '["https://cdn.test/a.jpg","https://cdn.test/b.mp4"]',
        }).mediaUrls,
        ['https://cdn.test/a.jpg', 'https://cdn.test/b.mp4'],
      );
    });

    test('surrounding whitespace still detects the array form', () {
      expect(
        parse(overrides: {
          SubmissionColumns.mediaUrl: '  ["https://cdn.test/a.jpg"]  ',
        }).mediaUrls,
        ['https://cdn.test/a.jpg'],
      );
    });

    test('an empty JSON array yields an empty list', () {
      expect(
        parse(overrides: {SubmissionColumns.mediaUrl: '[]'}).mediaUrls,
        isEmpty,
      );
    });

    test('malformed JSON falls back to the raw value', () {
      expect(
        parse(overrides: {
          SubmissionColumns.mediaUrl: '["https://cdn.test/a.jpg"',
        }).mediaUrls,
        ['["https://cdn.test/a.jpg"'],
      );
    });

    test('a JSON array of non-strings falls back to the raw value', () {
      expect(
        parse(overrides: {SubmissionColumns.mediaUrl: '[1,2]'}).mediaUrls,
        ['[1,2]'],
      );
    });

    test('an empty media_url yields an empty list', () {
      // Regression guard. This used to return [''], so a UI guarding on
      // `mediaUrls.isEmpty` rendered a blank image for a submission with
      // no media. All three mediaUrls getters agree on [] now.
      expect(
        parse(overrides: {SubmissionColumns.mediaUrl: ''}).mediaUrls,
        isEmpty,
      );
      expect(
        parse(overrides: {SubmissionColumns.mediaUrl: '   '}).mediaUrls,
        isEmpty,
      );
    });
  });

  group('SubmissionModel.effectiveMediaType', () {
    test('derives "mixed" from an image+video upload', () {
      // Regression guard. The getter was a bare pass-through of mediaType
      // despite documenting 'image' | 'video' | 'mixed', so a multi-file
      // submission stored before the writer learned to compute 'mixed'
      // (rows written as 'image') was never reported as mixed.
      final sub = parse(overrides: {
        SubmissionColumns.mediaType: MediaType.image,
        SubmissionColumns.mediaUrl: '["a.jpg","b.mp4"]',
      });

      expect(sub.effectiveMediaType, MediaType.mixed);
      expect(sub.mediaType, MediaType.image);
    });

    test('derives video / image from the extensions', () {
      expect(
        parse(overrides: {
          SubmissionColumns.mediaType: MediaType.image,
          SubmissionColumns.mediaUrl: '["a.mp4","b.mov"]',
        }).effectiveMediaType,
        MediaType.video,
      );
      expect(
        parse(overrides: {
          SubmissionColumns.mediaType: MediaType.video,
          SubmissionColumns.mediaUrl: '["a.jpg","b.png"]',
        }).effectiveMediaType,
        MediaType.image,
      );
    });

    test('a signed URL with a query string is still classified', () {
      expect(
        parse(overrides: {
          SubmissionColumns.mediaUrl:
              '["https://cdn.test/a.jpg?token=abc","https://cdn.test/b.mp4?x=1"]',
        }).effectiveMediaType,
        MediaType.mixed,
      );
    });

    test('an unclassifiable URL keeps the stored media_type', () {
      // Derivation only wins when EVERY URL can be classified; an
      // extension-less storage key must not be guessed at.
      expect(
        parse(overrides: {
          SubmissionColumns.mediaType: MediaType.video,
          SubmissionColumns.mediaUrl: '["a.jpg","user-1/opaque-key"]',
        }).effectiveMediaType,
        MediaType.video,
      );
    });

    test('an empty media_url falls back to the stored media_type', () {
      expect(
        parse(overrides: {
          SubmissionColumns.mediaType: MediaType.video,
          SubmissionColumns.mediaUrl: '',
        }).effectiveMediaType,
        MediaType.video,
      );
    });
  });

  group('SubmissionModel.toJson', () {
    test('emits every own column fromJson reads', () {
      // Regression guard. toJson used to emit only 11 columns, silently
      // dropping the moderation state (see the round-trip test below).
      final json = parse().toJson();

      expect(
        json.keys.toSet(),
        {
          SubmissionColumns.id,
          SubmissionColumns.userQuestId,
          SubmissionColumns.userId,
          SubmissionColumns.mediaUrl,
          SubmissionColumns.mediaType,
          SubmissionColumns.caption,
          SubmissionColumns.status,
          SubmissionColumns.reviewedBy,
          SubmissionColumns.reviewNote,
          SubmissionColumns.submittedAt,
          SubmissionColumns.reviewedAt,
          SubmissionColumns.appealNote,
          SubmissionColumns.appealed,
          SubmissionColumns.showInFeed,
          SubmissionColumns.visibility,
          SubmissionColumns.deletedAt,
        },
      );
      expect(json[SubmissionColumns.submittedAt], '2026-05-03T12:00:00.000Z');
      expect(json[SubmissionColumns.reviewedAt], '2026-05-03T13:00:00.000Z');
    });

    test('the joined quest/author fields are NOT emitted', () {
      // They belong to other tables — writing them back would be rejected
      // as unknown columns on `submissions`.
      final json = parse(overrides: {
        Tables.profiles: <String, dynamic>{ProfileColumns.username: 'ada'},
      }).toJson();

      expect(json.containsKey(ProfileColumns.username), isFalse);
      expect(json.containsKey(QuestColumns.title), isFalse);
    });

    test('a moderator takedown survives a read-modify-write', () {
      // Regression guard. appealed / appeal_note / show_in_feed /
      // visibility / deleted_at were read by fromJson but never written by
      // toJson, so a round-trip silently reset a takedown to visible.
      final original = parse(overrides: {
        SubmissionColumns.appealed: true,
        SubmissionColumns.appealNote: 'please reconsider',
        SubmissionColumns.showInFeed: false,
        SubmissionColumns.visibility: SubmissionVisibility.hiddenFromFeed,
        SubmissionColumns.deletedAt: '2026-06-01T00:00:00Z',
      });
      final json = original.toJson();
      final restored = SubmissionModel.fromJson(json);

      expect(json[SubmissionColumns.showInFeed], isFalse);
      expect(json[SubmissionColumns.appealed], isTrue);
      expect(json[SubmissionColumns.appealNote], 'please reconsider');
      expect(json[SubmissionColumns.visibility],
          SubmissionVisibility.hiddenFromFeed);
      expect(json[SubmissionColumns.deletedAt], '2026-06-01T00:00:00.000Z');

      expect(restored.showInFeed, isFalse);
      expect(restored.appealed, isTrue);
      expect(restored.appealNote, 'please reconsider');
      expect(restored.visibility, SubmissionVisibility.hiddenFromFeed);
      expect(restored.deletedAt, DateTime.utc(2026, 6, 1));
    });

    test('round-trips every own field without drift', () {
      final original = parse();
      final restored = SubmissionModel.fromJson(original.toJson());

      expect(restored, original);
    });

    test('a null reviewed_at serialises as null', () {
      final row = submissionRow()..remove(SubmissionColumns.reviewedAt);
      expect(
        SubmissionModel.fromJson(row).toJson()[SubmissionColumns.reviewedAt],
        isNull,
      );
    });
  });

  group('SubmissionModel value equality', () {
    // Regression guard. Equality used to be identity, so a re-fetch of an
    // unchanged submission still rebuilt every widget watching it.
    test('two submissions parsed from the same row are equal', () {
      expect(parse(), parse());
      expect(parse().hashCode, parse().hashCode);
    });

    test('a differing moderation flag breaks equality', () {
      expect(
        parse(overrides: {SubmissionColumns.showInFeed: false}),
        isNot(parse()),
      );
    });

    test('the joined fields participate in equality', () {
      expect(
        parse(overrides: {
          Tables.profiles: <String, dynamic>{ProfileColumns.username: 'ada'},
        }),
        isNot(parse()),
      );
    });
  });
}
