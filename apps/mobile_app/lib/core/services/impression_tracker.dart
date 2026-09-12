import 'dart:async';

/// Decides when a quest card has actually been *seen* (#81 §28).
///
/// Impressions were the one event in the store deliberately left unemitted,
/// and the reason was not effort: a business is shown this number as a
/// measurement, so an over-counted impression is worse than an absent one.
/// Counting every card the framework builds would have been exactly that —
/// `itemBuilder` runs for cards that are off screen, half built, or scrolled
/// past in the same frame.
///
/// So this counts a view only when two things are true, and the second one
/// is what a build count cannot tell you:
///
/// **It was the thing on screen.** The feed is a full-screen vertical
/// PageView: one post occupies the entire viewport, so "which post is the
/// user looking at" is not an estimate here, it is the settled page. That is
/// why the feed is the surface that emits and the list surfaces (map,
/// search, home) still do not — a row in a scrolling list needs real
/// visibility detection to make the same claim, and guessing would put an
/// unauditable number in front of somebody.
///
/// **It stayed there.** A flick through ten posts is not ten views. The
/// dwell is the difference between a card passing under the user's thumb and
/// a card being looked at.
///
/// Two further rules, both of them about not inflating the figure:
///
/// - **Once per quest per tracker.** A user who scrolls back up to a post
///   has not seen the quest for a second time in any sense a business is
///   asking about. The key is the *quest*, not the post: several
///   completions of one quest can sit in a feed, and counting each would
///   distort the impression → detail-view conversion by however many people
///   happened to post it.
/// - **Nothing counts while the app is not in front.** The dwell timer can
///   outlive the user's attention — backgrounding the app mid-dwell would
///   otherwise report a view of a screen nobody is looking at.
class ImpressionTracker {
  ImpressionTracker({
    required void Function(String questId, String? sourceSubmissionId)
        onImpression,
    Duration dwell = const Duration(seconds: 1),
    bool Function()? isForeground,
  })  : _onImpression = onImpression,
        _dwell = dwell,
        _isForeground = isForeground ?? (() => true);

  final void Function(String questId, String? sourceSubmissionId) _onImpression;
  final Duration _dwell;
  final bool Function() _isForeground;

  final Set<String> _counted = <String>{};
  Timer? _pending;
  String? _visible;

  /// The post through which the visible quest is being seen, if any. Carried
  /// through to the report so the post's author is credited with the exposure
  /// (virality attribution); it never affects whether a view counts.
  String? _visibleSource;

  /// The card now occupying the viewport. Safe to call repeatedly with the
  /// same id — a rebuild is not a new view, so the running dwell is left
  /// alone rather than restarted, which would let a widget that rebuilds
  /// every second postpone the impression forever.
  void onVisible(String questId, {String? sourceSubmissionId}) {
    if (_visible == questId) return;
    _visible = questId;
    _visibleSource = sourceSubmissionId;
    _pending?.cancel();
    if (_counted.contains(questId)) {
      _pending = null;
      return;
    }
    _pending = Timer(_dwell, () {
      _pending = null;
      // Re-checked at fire time, not at schedule time: both of these can
      // change during the dwell, and the question is whether the card was
      // on screen for the whole of it.
      if (_visible != questId) return;
      if (!_isForeground()) return;
      if (!_counted.add(questId)) return;
      _onImpression(questId, _visibleSource);
    });
  }

  /// Nothing is on screen any more — the feed was left, a route was pushed
  /// over it, or the app went to the background. A dwell in progress is
  /// abandoned rather than credited.
  void onHidden() {
    _pending?.cancel();
    _pending = null;
    _visible = null;
    _visibleSource = null;
  }

  void dispose() {
    _pending?.cancel();
    _pending = null;
  }
}
