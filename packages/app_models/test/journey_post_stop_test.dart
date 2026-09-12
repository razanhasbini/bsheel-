import 'package:app_models/app_models.dart';
import 'package:test/test.dart';

/// A journey posted to the feed as one route (0047).
void main() {
  Map<String, dynamic> stop(int order, {String? media, String? place}) => {
        'submission_id': 'sub-$order',
        'step_order': order,
        'media_url': media ?? 'stops/$order.jpg',
        'media_type': 'image',
        'caption': 'stop $order',
        'quest_title': 'Checkpoint $order',
        'place_name': place,
        'submitted_at': '2026-09-11T10:00:00.000Z',
      };

  test('parses the stops a route post is made of, in order', () {
    final post = FeedPostModel.fromRpc({
      'submission_id': 'sub-3',
      'media_url': 'stops/3.jpg',
      'journey_title': 'United Arab Emirates in three stops',
      'journey_stops': [stop(1), stop(2), stop(3, place: 'Al Fahidi')],
    });

    expect(post.isJourneyPost, isTrue);
    expect(post.journeyTitle, 'United Arab Emirates in three stops');
    expect(post.journeyStops.map((s) => s.stepOrder), [1, 2, 3]);
    expect(post.journeyStops.last.placeName, 'Al Fahidi');
  });

  test('a stop carries every file of its own submission', () {
    final post = FeedPostModel.fromRpc({
      'submission_id': 'sub-1',
      'journey_stops': [
        stop(1, media: '["a.jpg","b.jpg"]'),
        stop(2),
      ],
    });
    expect(post.journeyStops.first.mediaUrls, ['a.jpg', 'b.jpg']);
    expect(post.journeyStops.last.mediaUrls, ['stops/2.jpg']);
  });

  // An ordinary post must not become a one-stop "route": the carousel keys
  // off this, and a single stop would relabel a normal proof with a route
  // title it does not have.
  test('an ordinary post is not a journey post', () {
    final plain = FeedPostModel.fromRpc({'submission_id': 's', 'media_url': 'a.jpg'});
    expect(plain.journeyStops, isEmpty);
    expect(plain.isJourneyPost, isFalse);

    final single = FeedPostModel.fromRpc({
      'submission_id': 's',
      'journey_stops': [stop(1)],
    });
    expect(single.isJourneyPost, isFalse);
  });

  // copyWith drops anything it does not forward, and an optimistic vote goes
  // through it on every tap. A route that lost its stops would redraw as a
  // single photograph under the route's title.
  test('an optimistic vote keeps the route intact', () {
    final post = FeedPostModel.fromRpc({
      'submission_id': 'sub-2',
      'journey_title': 'Two stops',
      'journey_stops': [stop(1), stop(2)],
    });
    final voted = post.copyWith(upvoteCount: 1);
    expect(voted.journeyStops, post.journeyStops);
    expect(voted.journeyTitle, 'Two stops');
    expect(voted.isJourneyPost, isTrue);
  });
}
