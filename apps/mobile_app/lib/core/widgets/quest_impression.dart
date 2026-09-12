import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../services/analytics_reporter.dart';

/// Reports a `quest_impression` once this card has genuinely been seen.
///
/// "Seen" is at least half of the card on screen for a full second. Anything
/// looser over-counts: a list that scrolls past twenty cards in a flick drew
/// twenty cards, but nobody saw them, and a business reads impressions as a
/// measurement. This is the visibility detection whose absence kept
/// impressions deliberately unimplemented (CLAUDE.md, #81 §28) — the event
/// type and the aggregation already existed; only this was missing.
///
/// Dedup lives in the reporter, not here: a card rebuilt by a setState is a
/// new widget instance but the same impression.
class QuestImpression extends ConsumerStatefulWidget {
  const QuestImpression({
    super.key,
    required this.questId,
    required this.surface,
    required this.child,
    this.sourceSubmissionId,
  });

  final String questId;
  final String surface;

  /// The post this card IS, on surfaces where a quest is shown through a
  /// post (the feed). Lets a post's author be credited with the exposure.
  final String? sourceSubmissionId;
  final Widget child;

  /// How much of the card must be on screen, and for how long.
  static const double visibleFraction = 0.5;
  static const Duration dwell = Duration(seconds: 1);

  @override
  ConsumerState<QuestImpression> createState() => _QuestImpressionState();
}

class _QuestImpressionState extends ConsumerState<QuestImpression> {
  Timer? _dwell;
  bool _reported = false;

  @override
  void dispose() {
    _dwell?.cancel();
    super.dispose();
  }

  void _onVisibility(VisibilityInfo info) {
    if (_reported) return;
    if (info.visibleFraction >= QuestImpression.visibleFraction) {
      _dwell ??= Timer(QuestImpression.dwell, () {
        if (!mounted || _reported) return;
        _reported = true;
        // Telemetry is fire-and-forget and must never reach the user as an
        // error. The one way this can throw is a backend that was never
        // initialised — widget tests and previews — and a missing
        // impression there is the correct outcome, not a crash.
        try {
          ref.read(analyticsReporterProvider).impression(
                questId: widget.questId,
                surface: widget.surface,
                sourceSubmissionId: widget.sourceSubmissionId,
              );
        } catch (_) {
          // Nothing to report to.
        }
      });
    } else {
      // Scrolled away before the second was up: not seen.
      _dwell?.cancel();
      _dwell = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key(
        'impression:${widget.surface}:${widget.questId}:${widget.sourceSubmissionId ?? ''}',
      ),
      onVisibilityChanged: _onVisibility,
      child: widget.child,
    );
  }
}
