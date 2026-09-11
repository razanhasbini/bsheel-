import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_app/core/config/share_template.dart';

/// What a Bsheel share actually says.
///
/// These matter because a share is the one piece of Bsheel that lands in
/// front of people who have never opened it — in WhatsApp, next to a link
/// preview. If it reads badly, or names a country that is not the quest's,
/// that is the first and possibly only impression.
void main() {
  group('quest share', () {
    test('leads with BSHEEL, then the quest and where it is', () {
      final text = ShareTemplate.quest(
        postId: 'p1',
        questTitle: 'Fold a manoushe with the baker',
        country: 'Lebanon',
        caption: 'Did it before the bakery even opened.',
        username: 'razan',
      );
      expect(text.split('\n').first, 'BSHEEL');
      expect(text, contains('"Fold a manoushe with the baker" · Lebanon'));
      expect(text, contains('Did it before the bakery even opened.'));
      expect(text, contains('p1'));
    });

    test('omits the country rather than printing an empty separator', () {
      // Most quests can be done anywhere and have no destination at all.
      // "· " trailing a title reads like a bug.
      final text = ShareTemplate.quest(
        postId: 'p2',
        questTitle: 'Watch the sunrise',
        username: 'razan',
      );
      expect(text, contains('"Watch the sunrise"'));
      expect(text, isNot(contains('·')));
      expect(text, isNot(contains('null')));
    });

    test('treats a blank country the same as no country', () {
      final text = ShareTemplate.quest(
        postId: 'p3',
        questTitle: 'Watch the sunrise',
        country: '   ',
      );
      expect(text, isNot(contains('·')));
    });

    test('still reads sensibly when the quest title is missing', () {
      // A post whose title did not load should credit whoever did it
      // rather than sharing an empty pair of quotation marks.
      final text = ShareTemplate.quest(
        postId: 'p4',
        questTitle: '',
        username: 'razan',
      );
      expect(text, contains('A quest by @razan'));
      expect(text, isNot(contains('""')));
    });

    test('drops an empty caption instead of leaving a blank line', () {
      final text = ShareTemplate.quest(
        postId: 'p5',
        questTitle: 'Watch the sunrise',
        caption: '   ',
      );
      expect(text, isNot(contains('\n\n\n')));
    });

    test('always ends with the link, so the preview attaches', () {
      final text = ShareTemplate.quest(
        postId: 'p6',
        questTitle: 'Watch the sunrise',
        country: 'Qatar',
      );
      expect(text.trim().split('\n').last, contains('p6'));
    });
  });

  group('other shares use the same voice', () {
    test('a profile share', () {
      final text = ShareTemplate.profile(profileId: 'u1', username: 'razan');
      expect(text.split('\n').first, 'BSHEEL');
      expect(text, contains('@razan'));
      expect(text, contains('u1'));
    });

    test('a collab invite, with and without a quest title', () {
      final named = ShareTemplate.collabInvite(
        link: 'https://x/y',
        modeLabel: 'group',
        questTitle: 'Climb the steps',
      );
      expect(named.split('\n').first, 'BSHEEL');
      expect(named, contains('Join my group quest: "Climb the steps"'));

      final plain =
          ShareTemplate.collabInvite(link: 'https://x/y', modeLabel: 'versus');
      expect(plain, contains('Join my versus quest'));
      expect(plain, isNot(contains('""')));
    });
  });
}
