import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';

import '../media/signed_media_urls.dart';
import 'submissions_repository.dart';

/// Worker URL for R2 uploads.
const _workerUrl = WorkerUrls.r2Upload;

class SupabaseSubmissionsRepository implements SubmissionsRepository {
  final SupabaseClient _client;
  SupabaseSubmissionsRepository(this._client);

  @override
  Future<SubmissionModel> createSubmission(SubmissionModel submission) async {
    final payload = {
      SubmissionColumns.userQuestId: submission.userQuestId,
      SubmissionColumns.userId: submission.userId,
      SubmissionColumns.mediaUrl: submission.mediaUrl,
      SubmissionColumns.mediaType: submission.mediaType,
      SubmissionColumns.caption: submission.caption,
      SubmissionColumns.showInFeed: submission.showInFeed,
    };

    final response = await _client
        .from(Tables.submissions)
        .insert(payload)
        .select()
        .single();

    return _withSignedMedia(
      SubmissionModel.fromJson(Map<String, dynamic>.from(response)),
    );
  }

  @override
  Future<String> uploadSubmissionMedia(
    String userId,
    String submissionId,
    Uint8List fileBytes,
    String fileName,
    String mediaType, {
    int index = 0,
  }) async {
    final contentType = _contentTypeFor(fileName, fileBytes, mediaType);
    _assertUploadable(contentType);
    final extension = _fileExtensionSuffix(fileName, contentType);
    // Include a millisecond timestamp so re-submits on the same
    // user_quest (e.g. after a rejected first attempt, or an appeal
    // resubmission) get unique keys instead of overwriting the prior
    // attempt's media. Without this the rejected submission's images
    // would silently disappear once the user uploaded replacements.
    //
    // NOTE: any submit failure leaves these files orphaned in R2. The
    // worker doesn't currently expose a DELETE; orphans need to be
    // swept server-side by the bucket lifecycle policy or a periodic
    // edge function. Tracked separately — keep the unique key so the
    // sweep can safely target one path at a time.
    final ts = DateTime.now().millisecondsSinceEpoch;
    final uploadPath =
        'submissions/$userId/${submissionId}_${ts}_$index$extension';

    final session = _client.auth.currentSession;
    if (session == null) {
      throw const StorageException('Missing auth session for upload.');
    }

    final uri = Uri.parse('$_workerUrl/$uploadPath');

    // Retry with exponential backoff (max 3 attempts)
    http.Response? response;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        response = await http.put(
          uri,
          headers: {
            'Authorization': 'Bearer ${session.accessToken}',
            'Content-Type': contentType,
          },
          body: fileBytes,
        );
        if (response.statusCode >= 200 && response.statusCode < 300) break;
        // Server error — retry; client error — don't
        if (response.statusCode < 500) break;
      } catch (_) {
        if (attempt == 2) rethrow;
      }
      await Future.delayed(Duration(seconds: 1 << attempt));
    }

    if (response == null ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw StorageException(
        'Upload failed (${response?.statusCode}): ${response?.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['url'] as String;
  }

  @override
  Future<SubmissionModel?> getSubmission(String submissionId) async {
    final response = await _client
        .from(Tables.submissions)
        .select()
        .eq(SubmissionColumns.id, submissionId)
        .limit(1);

    final rows = response as List<dynamic>;
    if (rows.isEmpty) return null;

    return _withSignedMedia(
      SubmissionModel.fromJson(Map<String, dynamic>.from(rows.first)),
    );
  }

  @override
  Future<List<SubmissionModel>> getUserSubmissions(String userId) async {
    // Filter deleted both by visibility flag AND by deleted_at timestamp
    // — covers half-set rows where one column was updated but not the
    // other, so a deleted post can never leak through into the profile.
    final response = await _client
        .from(Tables.submissions)
        .select()
        .eq(SubmissionColumns.userId, userId)
        .neq(SubmissionColumns.visibility, SubmissionVisibility.deleted)
        .filter(SubmissionColumns.deletedAt, 'is', null)
        .order(SubmissionColumns.submittedAt, ascending: false);

    final submissions = (response as List<dynamic>)
        .map((row) => SubmissionModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return Future.wait(submissions.map(_withSignedMedia));
  }

  Future<SubmissionModel> _withSignedMedia(SubmissionModel submission) async {
    final signedMediaUrl = await SignedMediaUrls.signJsonOrSingle(
      _client,
      submission.mediaUrl,
    );
    return SubmissionModel(
      id: submission.id,
      userQuestId: submission.userQuestId,
      userId: submission.userId,
      mediaUrl: signedMediaUrl,
      mediaType: submission.mediaType,
      caption: submission.caption,
      status: submission.status,
      reviewedBy: submission.reviewedBy,
      reviewNote: submission.reviewNote,
      submittedAt: submission.submittedAt,
      reviewedAt: submission.reviewedAt,
      appealNote: submission.appealNote,
      appealed: submission.appealed,
      showInFeed: submission.showInFeed,
      visibility: submission.visibility,
      deletedAt: submission.deletedAt,
      questTitle: submission.questTitle,
      authorUsername: submission.authorUsername,
      authorDisplayName: submission.authorDisplayName,
    );
  }

  String _fileExtensionSuffix(String fileName, String contentType) {
    final index = fileName.lastIndexOf('.');
    if (index != -1 && index < fileName.length - 1) {
      return fileName.substring(index);
    }
    return _extensionForContentType(contentType);
  }

  String _extensionForContentType(String contentType) {
    return switch (contentType) {
      'image/png' => '.png',
      'image/webp' => '.webp',
      'image/gif' => '.gif',
      'image/heic' => '.heic',
      'image/heif' => '.heif',
      'video/mp4' => '.mp4',
      'video/webm' => '.webm',
      'video/quicktime' => '.mov',
      'video/x-m4v' => '.m4v',
      _ => '.jpg',
    };
  }

  String _contentTypeFor(
    String fileName,
    Uint8List fileBytes,
    String mediaType,
  ) {
    final detected = lookupMimeType(
      fileName,
      headerBytes: fileBytes.take(32).toList(),
    );
    if (detected != null) {
      return _normalizeMimeType(detected, mediaType);
    }
    if (mediaType == MediaType.video) {
      return 'video/mp4';
    }
    return 'image/jpeg';
  }

  String _normalizeMimeType(String mimeType, String mediaType) {
    if (mediaType == MediaType.video) {
      // octet-stream means the picker gave us no usable type; the file
      // came from a video picker, so mp4 is the right guess and the
      // worker's magic-byte check is the backstop if it isn't.
      if (mimeType == 'application/octet-stream') return 'video/mp4';
      // NOTE: 'video/x-msvideo' (AVI) used to be relabelled as video/mp4
      // here. That produced the worst possible failure: the worker
      // accepted the Content-Type, then rejected the body because AVI
      // bytes ('RIFF....AVI ') don't carry the ISO-BMFF 'ftyp' box an
      // mp4 needs — surfacing as "File content does not match
      // Content-Type header". Pass the real type through and let
      // _assertUploadable reject it up front with an honest message.
      return mimeType;
    }
    if (mimeType == 'application/octet-stream') return 'image/jpeg';
    return mimeType;
  }

  /// Fail fast on containers the R2 worker will refuse, so the user gets
  /// "AVI isn't supported" rather than a raw 400 from the edge.
  void _assertUploadable(String contentType) {
    if (WorkerMediaTypes.isAllowed(contentType)) return;
    throw StorageException(
      'Unsupported file format ($contentType). '
      'Use JPEG, PNG, GIF or WebP for photos, or MP4, MOV or WebM for video.',
    );
  }

  @override
  Future<void> setSubmissionVisibility(
    String submissionId,
    SoftDeleteMode mode,
  ) async {
    // Single canonical write path — see SoftDeleteMode docs for what
    // each mode means semantically. The 0114 BEFORE-UPDATE guard
    // requires only `visibility`, `deleted_at`, `show_in_feed` to be
    // touched, so the payload below is whitelist-compatible.
    final Map<String, dynamic> payload;
    switch (mode) {
      case SoftDeleteMode.visible:
        payload = {
          SubmissionColumns.showInFeed: true,
          SubmissionColumns.visibility: SubmissionVisibility.visible,
          SubmissionColumns.deletedAt: null,
        };
        break;
      case SoftDeleteMode.hiddenFromFeed:
        payload = {
          SubmissionColumns.visibility: SubmissionVisibility.hiddenFromFeed,
          SubmissionColumns.deletedAt: DateTime.now().toIso8601String(),
        };
        break;
      case SoftDeleteMode.deleted:
        payload = {
          SubmissionColumns.visibility: SubmissionVisibility.deleted,
          SubmissionColumns.deletedAt: DateTime.now().toIso8601String(),
        };
        break;
    }
    await _client
        .from(Tables.submissions)
        .update(payload)
        .eq(SubmissionColumns.id, submissionId);
  }
}
