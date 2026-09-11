import 'dart:async';

import 'package:app_core/app_core.dart' show AppLogger;
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/app_backend.dart';
import '../providers/auth_session_provider.dart';

/// Reports exposure events (#81 §28), batched and fire-and-forget.
///
/// Three rules, all of them about not making the app worse to use in order
/// to collect telemetry:
///
/// **Nothing awaits it.** `report` returns void. A screen that awaited a
/// telemetry call would stutter on a slow network for data nobody reads in
/// real time.
///
/// **A failure is dropped, silently and permanently.** No retry queue, no
/// disk spill. Losing an impression costs a business a rounding error;
/// retrying forever on a flaky connection costs the user battery, and a
/// queue that survives restarts eventually replays stale events into the
/// wrong day. The server's idempotency key means a *duplicate* is harmless,
/// but that is not a reason to manufacture duplicates.
///
/// **It reports nothing while signed out.** The endpoint requires auth and
/// attributes events to the caller, so an event with no session has nobody
/// to belong to.
class AnalyticsReporter {
  AnalyticsReporter(this._repository, this._session);

  final AnalyticsRepository _repository;
  final AuthUser? Function() _session;

  static const _batchSize = 25;
  static const _flushAfter = Duration(seconds: 10);

  final List<AnalyticsEvent> _pending = [];
  Timer? _timer;
  bool _flushing = false;

  /// Queues one event. Never throws, never blocks.
  void report({
    required String eventType,
    required String questId,
    required String surface,
  }) {
    if (_session() == null) return;
    _pending.add(AnalyticsEvent(
      // Per event, so a resend is idempotent rather than silently dropped.
      clientEventId: _uuid(),
      eventType: eventType,
      questId: questId,
      surface: surface,
      occurredAt: DateTime.now().toUtc(),
    ));
    if (_pending.length >= _batchSize) {
      unawaited(flush());
      return;
    }
    // Coalesces a burst — opening five quests in a row is one request.
    _timer ??= Timer(_flushAfter, () => unawaited(flush()));
  }

  /// Sends whatever is queued. Safe to call at any time, including twice.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    if (_flushing || _pending.isEmpty) return;
    // Taken before the await, so events queued during the request are not
    // lost and not sent twice.
    final batch = List<AnalyticsEvent>.of(_pending);
    _pending.clear();
    _flushing = true;
    try {
      await _repository.record(batch);
    } catch (error) {
      // Deliberately not requeued. See the class comment.
      AppLogger.info('[Analytics] dropped ${batch.length} events: $error');
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// A v4 UUID without pulling in a package for it.
  static String _uuid() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final bytes = List<int>.generate(16,
        (i) => (random >> (i % 8 * 8) ^ (i * 0x9E3779B1) ^ _counter++) & 0xFF);
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  static int _counter = 0;
}

/// Event type and surface names, so a typo is a compile error rather than a
/// 400 the user never sees.
abstract final class AnalyticsEvents {
  static const questDetailView = 'quest_detail_view';
  static const questBsheeel = 'quest_bsheeel';
  static const questShare = 'quest_share';

  /// Not emitted yet — see docs. Accurate impression counting needs
  /// visibility detection, and an over-counted impression is worse than an
  /// absent one because a business is shown it as a measurement.
  static const questImpression = 'quest_impression';
}

abstract final class AnalyticsSurfaces {
  static const feed = 'feed';
  static const map = 'map';
  static const home = 'home';
  static const search = 'search';
  static const country = 'country';
  static const questDetail = 'quest_detail';
}

final analyticsReporterProvider = Provider<AnalyticsReporter>((ref) {
  final reporter = AnalyticsReporter(
    AppBackend.repositories.analytics,
    () => ref.read(authSessionProvider),
  );
  ref.onDispose(reporter.dispose);
  return reporter;
});
