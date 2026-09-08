import 'package:app_models/app_models.dart';
import 'package:app_contracts/app_contracts.dart';
import 'package:test/test.dart';

Map<String, dynamic> collabMemberRow({
  Map<String, dynamic> overrides = const {},
}) =>
    {
      'user_id': 'user-2',
      'username': 'grace',
      'display_name': 'Grace H.',
      'avatar_url': 'https://cdn.test/grace.jpg',
      'bio': 'compiles things',
      'submission_id': 'sub-2',
      'media_url': 'https://cdn.test/b.jpg',
      'media_type': MediaType.image,
      'submission_status': SubmissionStatus.approved,
      'caption': 'mine',
      'show_in_feed': true,
      'vote_count': 3,
      'viewer_voted': true,
      ...overrides,
    };

Map<String, dynamic> feedRow({Map<String, dynamic> overrides = const {}}) => {
      FeedRpcColumns.submissionId: 'sub-1',
      SubmissionColumns.mediaUrl: 'https://cdn.test/a.jpg',
      SubmissionColumns.mediaType: MediaType.image,
      SubmissionColumns.caption: 'first light',
      SubmissionColumns.submittedAt: '2026-05-03T12:00:00Z',
      FeedRpcColumns.userId: 'user-1',
      ProfileColumns.username: 'ada',
      ProfileColumns.displayName: 'Ada L.',
      ProfileColumns.avatarUrl: 'https://cdn.test/ada.jpg',
      ProfileColumns.bio: 'builds things',
      FeedRpcColumns.questId: 'quest-1',
      FeedRpcColumns.questTitle: 'Photo walk',
      FeedRpcColumns.questDescription: 'Shoot 3 frames.',
      FeedRpcColumns.questCategory: QuestCategory.creativity,
      FeedRpcColumns.xpReward: 150,
      FeedRpcColumns.upvoteCount: 12,
      FeedRpcColumns.downvoteCount: 2,
      FeedRpcColumns.netScore: 10,
      FeedRpcColumns.hotScore: 1.75,
      CollabFeedRpcColumns.isCollab: false,
      CollabFeedRpcColumns.collabGroupId: null,
      CollabFeedRpcColumns.collabMode: null,
      CollabFeedRpcColumns.collabMemberCount: 0,
      CollabFeedRpcColumns.collabMembers: null,
      'expires_at': '2026-05-03T16:00:00Z',
      ...overrides,
    };

FeedPostModel parse({Map<String, dynamic> overrides = const {}}) =>
    FeedPostModel.fromRpc(feedRow(overrides: overrides));

void main() {
  group('FeedPostModel.fromRpc', () {
    test('parses the full get_feed row', () {
      final post = parse();

      expect(post.id, 'sub-1');
      expect(post.mediaUrl, 'https://cdn.test/a.jpg');
      expect(post.mediaType, 'image');
      expect(post.caption, 'first light');
      expect(post.submittedAt, DateTime.utc(2026, 5, 3, 12));
      expect(post.userId, 'user-1');
      expect(post.username, 'ada');
      expect(post.displayName, 'Ada L.');
      expect(post.avatarUrl, 'https://cdn.test/ada.jpg');
      expect(post.bio, 'builds things');
      expect(post.questId, 'quest-1');
      expect(post.questTitle, 'Photo walk');
      expect(post.questDescription, 'Shoot 3 frames.');
      expect(post.questCategory, 'creativity');
      expect(post.xpReward, 150);
      expect(post.upvoteCount, 12);
      expect(post.downvoteCount, 2);
      expect(post.netScore, 10);
      expect(post.hotScore, 1.75);
      expect(post.isCollab, isFalse);
      expect(post.collabMembers, isEmpty);
      expect(post.expiresAt, DateTime.utc(2026, 5, 3, 16));
    });

    test('the id comes from submission_id, not from an "id" key', () {
      final row = feedRow(overrides: {'id': 'not-this-one'})
        ..remove(FeedRpcColumns.submissionId);

      expect(FeedPostModel.fromRpc(row).id, isEmpty);
    });

    test('missing text columns coerce to empty strings', () {
      final post = FeedPostModel.fromRpc({
        SubmissionColumns.submittedAt: '2026-05-03T12:00:00Z',
      });

      expect(post.id, isEmpty);
      expect(post.mediaUrl, isEmpty);
      expect(post.userId, isEmpty);
      expect(post.username, isEmpty);
      expect(post.displayName, isEmpty);
      expect(post.questId, isEmpty);
      expect(post.questTitle, isEmpty);
      expect(post.questDescription, isEmpty);
      expect(post.questCategory, isEmpty);
      expect(post.mediaType, MediaType.image);
      expect(post.caption, isNull);
      expect(post.avatarUrl, isNull);
      expect(post.expiresAt, isNull);
    });

    test('a missing or malformed submitted_at degrades to the epoch', () {
      // Regression guard. submitted_at used to be parsed with a hard cast,
      // so one malformed row threw a TypeError that took down the whole
      // page of the feed.
      final epoch = DateTime.utc(1970);

      expect(FeedPostModel.fromRpc({}).submittedAt, epoch);
      expect(
        parse(overrides: {SubmissionColumns.submittedAt: 'earlier'})
            .submittedAt,
        epoch,
      );
    });

    test('show_in_feed / visibility are never read from the RPC row', () {
      // ACTUAL behaviour: fromRpc has no mapping for these two columns, so
      // they are pinned at the constructor defaults even when the row says
      // otherwise. Feed-level hiding has to be enforced SQL-side.
      final post = parse(overrides: {
        SubmissionColumns.showInFeed: false,
        SubmissionColumns.visibility: SubmissionVisibility.hiddenFromFeed,
      });

      expect(post.showInFeed, isTrue);
      expect(post.visibility, SubmissionVisibility.visible);
    });

    group('vote-count coercion', () {
      test('numeric strings and doubles both land as ints', () {
        final post = parse(overrides: {
          FeedRpcColumns.upvoteCount: '12',
          FeedRpcColumns.downvoteCount: 2.9,
          FeedRpcColumns.netScore: '-5',
          FeedRpcColumns.xpReward: 150.0,
        });

        expect(post.upvoteCount, 12);
        expect(post.downvoteCount, 2);
        expect(post.netScore, -5);
        expect(post.xpReward, 150);
      });

      test('nulls and garbage fall back to 0', () {
        final post = parse(overrides: {
          FeedRpcColumns.upvoteCount: null,
          FeedRpcColumns.downvoteCount: 'two',
          FeedRpcColumns.netScore: null,
        });

        expect(post.upvoteCount, 0);
        expect(post.downvoteCount, 0);
        expect(post.netScore, 0);
      });
    });

    group('hot_score coercion', () {
      test('an int widens to double', () {
        expect(parse(overrides: {FeedRpcColumns.hotScore: 3}).hotScore, 3.0);
      });

      test('a numeric string parses (PostgREST sends numeric as text)', () {
        expect(
          parse(overrides: {FeedRpcColumns.hotScore: '2.5'}).hotScore,
          2.5,
        );
      });

      test('null and garbage fall back to 0.0', () {
        expect(parse(overrides: {FeedRpcColumns.hotScore: null}).hotScore, 0.0);
        expect(
            parse(overrides: {FeedRpcColumns.hotScore: 'hot'}).hotScore, 0.0);
      });
    });

    group('expires_at is parsed leniently', () {
      test('an unparseable timestamp yields null instead of throwing', () {
        // expires_at is optional, so it degrades to null — and every other
        // timestamp in the package is defensive now too, rather than this
        // being the one lenient outlier.
        expect(parse(overrides: {'expires_at': 'never'}).expiresAt, isNull);
      });

      test('a DateTime instance passes through', () {
        final at = DateTime.utc(2026, 9, 9, 9);
        expect(parse(overrides: {'expires_at': at}).expiresAt, at);
      });
    });

    group('collab members', () {
      test('a member array is parsed in order', () {
        final post = parse(overrides: {
          CollabFeedRpcColumns.isCollab: true,
          CollabFeedRpcColumns.collabGroupId: 'group-1',
          CollabFeedRpcColumns.collabMode: CollabMode.versus,
          CollabFeedRpcColumns.collabMemberCount: '2',
          CollabFeedRpcColumns.collabMembers: <dynamic>[
            collabMemberRow(),
            collabMemberRow(overrides: {'user_id': 'user-3'}),
          ],
        });

        expect(post.isCollab, isTrue);
        expect(post.collabGroupId, 'group-1');
        expect(post.collabMode, 'versus');
        expect(post.collabMemberCount, 2);
        expect(post.collabMembers, hasLength(2));
        expect(post.collabMembers.first.userId, 'user-2');
        expect(post.collabMembers.last.userId, 'user-3');
      });

      test('a non-list collab_members yields an empty list', () {
        expect(
          parse(overrides: {
            CollabFeedRpcColumns.collabMembers: 'not-a-list',
          }).collabMembers,
          isEmpty,
        );
      });

      test('an empty array yields an empty list', () {
        expect(
          parse(overrides: {
            CollabFeedRpcColumns.collabMembers: <dynamic>[],
          }).collabMembers,
          isEmpty,
        );
      });
    });
  });

  group('FeedPostModel.mediaUrls', () {
    test('a bare URL yields one element', () {
      expect(parse().mediaUrls, ['https://cdn.test/a.jpg']);
    });

    test('a JSON array yields every URL', () {
      expect(
        parse(overrides: {
          SubmissionColumns.mediaUrl: '["a.jpg","b.mp4","c.png"]',
        }).mediaUrls,
        ['a.jpg', 'b.mp4', 'c.png'],
      );
    });

    test('malformed JSON falls back to the raw value', () {
      expect(
        parse(overrides: {SubmissionColumns.mediaUrl: '[oops'}).mediaUrls,
        ['[oops'],
      );
    });

    test('an empty media_url yields an empty list', () {
      // Regression guard. This used to return [''], so a feed tile guarding
      // on `mediaUrls.isEmpty` rendered a blank image. All three mediaUrls
      // getters agree on [] now.
      expect(parse(overrides: {SubmissionColumns.mediaUrl: ''}).mediaUrls,
          isEmpty);
    });
  });

  group('FeedPostModel.copyWith', () {
    test('overrides the optimistic-update fields', () {
      final post = parse().copyWith(
        upvoteCount: 99,
        downvoteCount: 1,
        netScore: 98,
        mediaUrl: 'https://cdn.test/signed.jpg',
      );

      expect(post.upvoteCount, 99);
      expect(post.downvoteCount, 1);
      expect(post.netScore, 98);
      expect(post.mediaUrl, 'https://cdn.test/signed.jpg');
    });

    test('a no-arg copy preserves every field, including expires_at', () {
      // Regression guard. copyWith used to omit expiresAt, silently resetting
      // it to null, so any optimistic vote on a collab post lost the
      // timestamp the "WAITING FOR" -> "DIDN'T POST" flip depends on.
      final original = parse();
      final copy = original.copyWith();

      expect(original.expiresAt, DateTime.utc(2026, 5, 3, 16));
      expect(copy.expiresAt, original.expiresAt);

      expect(copy.id, original.id);
      expect(copy.mediaUrl, original.mediaUrl);
      expect(copy.mediaType, original.mediaType);
      expect(copy.caption, original.caption);
      expect(copy.submittedAt, original.submittedAt);
      expect(copy.userId, original.userId);
      expect(copy.username, original.username);
      expect(copy.displayName, original.displayName);
      expect(copy.avatarUrl, original.avatarUrl);
      expect(copy.bio, original.bio);
      expect(copy.questId, original.questId);
      expect(copy.questTitle, original.questTitle);
      expect(copy.questDescription, original.questDescription);
      expect(copy.questCategory, original.questCategory);
      expect(copy.xpReward, original.xpReward);
      expect(copy.hotScore, original.hotScore);
      expect(copy.showInFeed, original.showInFeed);
      expect(copy.visibility, original.visibility);
      expect(copy.isCollab, original.isCollab);
      expect(copy.collabGroupId, original.collabGroupId);
      expect(copy.collabMode, original.collabMode);
      expect(copy.collabMemberCount, original.collabMemberCount);
    });

    test('copyWith cannot clear avatarUrl (?? keeps the old value)', () {
      // ACTUAL behaviour: passing null is indistinguishable from omitting.
      expect(parse().copyWith(avatarUrl: null).avatarUrl,
          'https://cdn.test/ada.jpg');
    });

    test('replaces the collab member list wholesale', () {
      final original = parse(overrides: {
        CollabFeedRpcColumns.collabMembers: <dynamic>[collabMemberRow()],
      });
      final copy = original.copyWith(collabMembers: const []);

      expect(original.collabMembers, hasLength(1));
      expect(copy.collabMembers, isEmpty);
    });
  });

  group('CollabFeedMember', () {
    test('parses a full member row', () {
      final member = CollabFeedMember.fromJson(collabMemberRow());

      expect(member.userId, 'user-2');
      expect(member.username, 'grace');
      expect(member.displayName, 'Grace H.');
      expect(member.avatarUrl, 'https://cdn.test/grace.jpg');
      expect(member.bio, 'compiles things');
      expect(member.submissionId, 'sub-2');
      expect(member.mediaUrl, 'https://cdn.test/b.jpg');
      expect(member.mediaType, 'image');
      expect(member.submissionStatus, 'approved');
      expect(member.caption, 'mine');
      expect(member.showInFeed, isTrue);
      expect(member.voteCount, 3);
      expect(member.viewerVoted, isTrue);
    });

    test('user_id is required; everything else degrades', () {
      expect(
        () => CollabFeedMember.fromJson(const <String, dynamic>{}),
        throwsA(isA<TypeError>()),
      );

      final member = CollabFeedMember.fromJson(
        const <String, dynamic>{'user_id': 'user-9'},
      );
      expect(member.username, isEmpty);
      expect(member.displayName, isEmpty);
      expect(member.avatarUrl, isNull);
      expect(member.submissionId, isNull);
      expect(member.mediaUrl, isNull);
      expect(member.showInFeed, isTrue);
      expect(member.voteCount, 0);
      expect(member.viewerVoted, isFalse);
    });

    test('vote_count accepts a num and truncates', () {
      expect(
        CollabFeedMember.fromJson(collabMemberRow(overrides: {
          'vote_count': 3.9,
        })).voteCount,
        3,
      );
    });

    test('a null vote_count / viewer_voted falls back to 0 / false', () {
      final member = CollabFeedMember.fromJson(collabMemberRow(overrides: {
        'vote_count': null,
        'viewer_voted': null,
        'show_in_feed': null,
      }));

      expect(member.voteCount, 0);
      expect(member.viewerVoted, isFalse);
      expect(member.showInFeed, isTrue);
    });

    group('mediaUrls', () {
      test('a null media_url yields an empty list (no placeholder)', () {
        expect(
          CollabFeedMember.fromJson(collabMemberRow(overrides: {
            'media_url': null,
          })).mediaUrls,
          isEmpty,
        );
      });

      test('an empty media_url also yields an empty list', () {
        // This was the only one of the three mediaUrls getters that got it
        // right; SubmissionModel and FeedPostModel now agree with it, so a
        // "waiting for member" slot renders as truly empty everywhere.
        expect(
          CollabFeedMember.fromJson(collabMemberRow(overrides: {
            'media_url': '',
          })).mediaUrls,
          isEmpty,
        );
      });

      test('a JSON array yields every URL', () {
        expect(
          CollabFeedMember.fromJson(collabMemberRow(overrides: {
            'media_url': '["a.jpg","b.mp4"]',
          })).mediaUrls,
          ['a.jpg', 'b.mp4'],
        );
      });

      test('malformed JSON falls back to the raw value', () {
        expect(
          CollabFeedMember.fromJson(collabMemberRow(overrides: {
            'media_url': '["a.jpg"',
          })).mediaUrls,
          ['["a.jpg"'],
        );
      });
    });

    test('copyWith overrides only what it is given', () {
      final original = CollabFeedMember.fromJson(collabMemberRow());
      final copy = original.copyWith(voteCount: 10, viewerVoted: false);

      expect(copy.voteCount, 10);
      expect(copy.viewerVoted, isFalse);
      expect(copy.userId, original.userId);
      expect(copy.username, original.username);
      expect(copy.displayName, original.displayName);
      expect(copy.bio, original.bio);
      expect(copy.submissionId, original.submissionId);
      expect(copy.mediaType, original.mediaType);
      expect(copy.submissionStatus, original.submissionStatus);
      expect(copy.caption, original.caption);
      expect(copy.showInFeed, original.showInFeed);
    });

    test('copyWith cannot clear avatarUrl or mediaUrl', () {
      final original = CollabFeedMember.fromJson(collabMemberRow());
      final copy = original.copyWith(avatarUrl: null, mediaUrl: null);

      expect(copy.avatarUrl, original.avatarUrl);
      expect(copy.mediaUrl, original.mediaUrl);
    });

    test('a stringly-typed show_in_feed hides the member, "true" does not', () {
      // Same fail-closed rule as SubmissionModel.showInFeed.
      expect(
        CollabFeedMember.fromJson(collabMemberRow(overrides: {
          'show_in_feed': 'false',
        })).showInFeed,
        isFalse,
      );
      expect(
        CollabFeedMember.fromJson(collabMemberRow(overrides: {
          'show_in_feed': 'true',
        })).showInFeed,
        isTrue,
      );
      expect(
        CollabFeedMember.fromJson(collabMemberRow(overrides: {
          'show_in_feed': 7,
        })).showInFeed,
        isFalse,
      );
    });

    test('value equality compares every field', () {
      final a = CollabFeedMember.fromJson(collabMemberRow());
      final b = CollabFeedMember.fromJson(collabMemberRow());

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a.copyWith(voteCount: 4), isNot(a));
    });
  });

  group('FeedPostModel value equality', () {
    // Regression guard. Equality used to be identity, so every unchanged
    // feed re-fetch rebuilt every tile. This is the class where it matters
    // most; the collabMembers list is bounded by the party size, so
    // element-wise comparison stays cheap.
    test('two posts parsed from the same row are equal', () {
      expect(parse(), parse());
      expect(parse().hashCode, parse().hashCode);
    });

    test('a no-arg copyWith is equal to its original', () {
      final original = parse(overrides: {
        CollabFeedRpcColumns.collabMembers: <dynamic>[collabMemberRow()],
      });

      expect(original.copyWith(), original);
    });

    test('an optimistic vote makes it unequal', () {
      expect(parse().copyWith(upvoteCount: 13), isNot(parse()));
    });

    test('the collab member list participates in equality', () {
      final withMember = parse(overrides: {
        CollabFeedRpcColumns.collabMembers: <dynamic>[collabMemberRow()],
      });

      expect(
        withMember,
        parse(overrides: {
          CollabFeedRpcColumns.collabMembers: <dynamic>[collabMemberRow()],
        }),
      );
      expect(withMember.copyWith(collabMembers: const []), isNot(withMember));
    });
  });
}
