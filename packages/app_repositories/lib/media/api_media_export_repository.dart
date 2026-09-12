import '../api/api_client.dart';

/// A server-side branded render of a video post (backend migration 0050).
class BrandedExport {
  const BrandedExport({
    required this.submissionId,
    required this.status,
    this.downloadUrl,
    this.error,
  });

  factory BrandedExport.fromJson(Map<String, dynamic> json) => BrandedExport(
        submissionId: '${json['submissionId']}',
        status: '${json['status']}',
        downloadUrl: json['downloadUrl'] as String?,
        error: json['error'] as String?,
      );

  final String submissionId;

  /// `queued` · `rendering` · `ready` · `failed`.
  final String status;

  /// Signed and short-lived; present only when [status] is `ready`.
  final String? downloadUrl;
  final String? error;

  bool get isReady => status == 'ready' && downloadUrl != null;
  bool get isFailed => status == 'failed';
}

/// Photos are branded on the phone; videos are branded on the worker, where
/// ffmpeg is. This asks for a render and reads it back.
class ApiMediaExportRepository {
  ApiMediaExportRepository(this._client);
  final ApiClient _client;

  /// Idempotent per post: a second request (from anyone) returns the same
  /// render, and a failed one is queued again.
  Future<BrandedExport> requestBranded(String submissionId) async =>
      BrandedExport.fromJson(apiObject(await _client.post(
        'media/branded-exports',
        body: {'submissionId': submissionId},
      )));

  Future<BrandedExport> brandedStatus(String submissionId) async =>
      BrandedExport.fromJson(
        apiObject(await _client.get('media/branded-exports/$submissionId')),
      );

  /// Polls until the render is ready or has failed, or [timeout] passes.
  /// Returns the last status seen either way, so the caller can say why.
  Future<BrandedExport> awaitBranded(
    String submissionId, {
    Duration timeout = const Duration(seconds: 90),
    Duration every = const Duration(seconds: 2),
  }) async {
    var latest = await requestBranded(submissionId);
    final deadline = DateTime.now().add(timeout);
    while (!latest.isReady &&
        !latest.isFailed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(every);
      latest = await brandedStatus(submissionId);
    }
    return latest;
  }
}
