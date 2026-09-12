import 'package:app_models/app_models.dart';

import '../api/api_client.dart';

/// Multi-stage journeys.
///
/// Every method here is a thin read or action over the server's state. The
/// client never decides whether a checkpoint is open, whose it is, or
/// whether the unlock celebration is still owed — those are answers only the
/// backend has, and guessing any of them produces a button that fails when
/// pressed or a moment that plays twice.
class ApiJourneysRepository {
  ApiJourneysRepository(this._client);

  final ApiClient _client;

  /// Journeys this user is currently walking, hidden content already
  /// withheld by the server.
  Future<List<JourneyRun>> active() async {
    final data = apiObject(await _client.get('journeys/active'));
    return (data['runs'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(JourneyRun.fromJson)
        .toList(growable: false);
  }

  Future<JourneyRun> detail(String runId) async =>
      JourneyRun.fromJson(apiObject(await _client.get('journeys/$runId')));

  /// Starts the checkpoint that is open for this user.
  ///
  /// [questId] is only meaningful on an any-order journey, where several may
  /// be open at once and the player chooses. This is the call that starts
  /// the timer — nothing before it does.
  Future<void> continueJourney(String runId, {String? questId}) async {
    await _client.post(
      'journeys/$runId/continue',
      body: {if (questId != null) 'questId': questId},
    );
  }

  /// Records how this journey should reach the feed.
  ///
  /// Returns whether it applied. The server refuses once a checkpoint has
  /// been submitted, and that is a "no" rather than an error: the player may
  /// have submitted from another device while the sheet was open. The caller
  /// re-reads the run and shows what is actually true rather than insisting.
  Future<bool> chooseFeedMode(String runId,
      {required bool oneRoutePost}) async {
    final data = apiObject(await _client.post(
      'journeys/$runId/feed-mode',
      body: {'mode': oneRoutePost ? 'one_post' : 'per_stop'},
    ));
    return data['applied'] == true;
  }

  /// Marks the unlock seen, so the celebration plays exactly once.
  ///
  /// Called after the animation has actually been shown, never before: if
  /// the app dies mid-transition the server still owes the moment, which is
  /// the point of holding it server-side rather than in local storage.
  Future<void> acknowledgeUnlock(String runId) async {
    await _client.post('journeys/$runId/unlock-seen');
  }

  // ── Relay ──────────────────────────────────────────────────────────────

  Future<({String runId, String joinCode, String title})> createRelay(
    String chainId,
  ) async {
    final data = apiObject(
      await _client.post('journeys/runs', body: {'chainId': chainId}),
    );
    return (
      runId: data['runId'] as String,
      joinCode: data['joinCode'] as String,
      title: data['title'] as String? ?? '',
    );
  }

  /// Adds the CALLER to a forming relay. Nobody can be added by anyone else.
  Future<String> joinRelay(String joinCode) async {
    final data = apiObject(
      await _client.post('journeys/runs/join', body: {'joinCode': joinCode}),
    );
    return data['runId'] as String;
  }

  Future<List<({String userId, String username, int position})>> roster(
    String runId,
  ) async {
    final rows = apiObjectList(await _client.get('journeys/$runId/roster'));
    return rows
        .map((r) => (
              userId: r['user_id'] as String,
              username: r['username'] as String? ?? '',
              position: (r['position'] as num).toInt(),
            ))
        .toList(growable: false);
  }

  Future<void> startRelay(String runId) async {
    await _client.post('journeys/$runId/start');
  }
}
