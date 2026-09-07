/// Single source of truth for external worker URLs.
abstract final class WorkerUrls {
  /// Cloudflare R2 upload worker URL.
  static const String r2Upload =
      'https://quest-media-upload.laythayache5.workers.dev';
}

/// Content types the R2 upload worker accepts, mirroring the
/// `allowedImageTypes` / `allowedVideoTypes` arrays in
/// `cloudflare/worker-r2-upload.js`.
///
/// The worker rejects anything outside these lists with a 400, and then
/// separately checks the body's magic bytes against the declared type.
/// Keeping the list here lets the client fail fast with a friendly
/// message instead of surfacing the worker's raw error. If you change
/// the worker's arrays, change these too.
abstract final class WorkerMediaTypes {
  static const Set<String> image = {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  };

  static const Set<String> video = {
    'video/mp4',
    'video/quicktime',
    'video/webm',
  };

  static bool isAllowed(String contentType) =>
      image.contains(contentType) || video.contains(contentType);
}

/// Single source of truth for Supabase Storage bucket names and path patterns.
abstract final class StorageBuckets {
  static const String avatars = 'avatars';
  static const String submissions = 'submissions';
}

abstract final class StoragePaths {
  /// Returns the storage path for a user's avatar.
  /// [ext] defaults to 'jpg' for backward-compatibility; pass the actual
  /// file extension (without leading dot) when uploading non-JPEG avatars.
  static String avatarPath(String userId, {String ext = 'jpg'}) =>
      'avatars/$userId/avatar.$ext';

  /// Returns the storage path for a submission media file.
  static String submissionPath(String userId, String submissionId) =>
      'submissions/$userId/$submissionId';
}
