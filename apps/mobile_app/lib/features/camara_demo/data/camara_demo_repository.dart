import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/app_backend.dart';
import 'camara_demo_models.dart';

/// Talks to the temporary CAMARA demo endpoints.
///
/// Built on the bundle's shared `ApiClient` rather than added to the bundle
/// itself, so the whole feature folder can be deleted after the hackathon
/// without unpicking the composition root.
class CamaraDemoRepository {
  CamaraDemoRepository(this._client);

  final ApiClient _client;

  /// What this deployment offers and whether this account may use it.
  ///
  /// Returns `unavailable` on any error rather than throwing: an ordinary
  /// build talking to an ordinary backend gets a 404 or a 403 here, and that
  /// is the normal answer, not a fault worth surfacing.
  Future<CamaraDemoAccess> access() async {
    try {
      return CamaraDemoAccess.fromJson(
          apiObject(await _client.get('agent/demo/personas')));
    } catch (_) {
      return CamaraDemoAccess.unavailable;
    }
  }

  /// Whether to offer the demo for this particular submission.
  ///
  /// Answers false for a quest with no destination: the four personas differ
  /// only in what the network says about location, so on a quest that is not
  /// location-based they would all produce the same answer. Those quests
  /// already verify correctly from the media alone and are left alone.
  ///
  /// Any error is "do not offer" — an ordinary build talking to an ordinary
  /// backend gets a 404 here, and that is the normal answer, not a fault.
  Future<CamaraDemoAccess> offerFor(String submissionId) async {
    try {
      return CamaraDemoAccess.fromJson(apiObject(
          await _client.get('agent/demo/submissions/$submissionId/offer')));
    } catch (_) {
      return CamaraDemoAccess.unavailable;
    }
  }

  /// Queues one evaluation. The agent runs in the worker, so this returns
  /// immediately and [result] is polled.
  ///
  /// [geofenceEvent] is separate from the persona on purpose: where the
  /// network says the device is, and whether it ever reported crossing the
  /// boundary, are different signals. Collapsing them would let the scenario
  /// decide the outcome instead of the policy.
  Future<void> evaluate({
    required String submissionId,
    required String personaId,
    String? geofenceEvent,
  }) async {
    await _client.post(
      'agent/demo/submissions/$submissionId/evaluate',
      body: {
        'personaId': personaId,
        if (geofenceEvent != null) 'geofenceEvent': geofenceEvent,
      },
    );
  }

  /// The finished run, or null while it is still going.
  Future<CamaraDemoResult?> result(String submissionId) async {
    final raw =
        await _client.get('agent/demo/submissions/$submissionId/result');
    if (raw == null) return null;
    final data = apiObject(raw);
    if (data.isEmpty || data['dossier'] == null) return null;
    return CamaraDemoResult.fromJson(data);
  }
}

final camaraDemoRepositoryProvider = Provider<CamaraDemoRepository>(
    (ref) => CamaraDemoRepository(AppBackend.repositories.client));

/// Whether to offer the demo for one submission. Keyed on the submission,
/// because the answer depends on whether its quest has a destination.
final camaraDemoOfferProvider = FutureProvider.family<CamaraDemoAccess, String>(
    (ref, submissionId) =>
        ref.read(camaraDemoRepositoryProvider).offerFor(submissionId));
