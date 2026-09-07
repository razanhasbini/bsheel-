/// Deep link configuration for Universal Links.
///
/// The domain must match the Associated Domains entitlement in
/// `ios/Runner/Runner.entitlements` and the AASA file hosted at
/// `https://<domain>/.well-known/apple-app-site-association`.
abstract final class DeepLinkConfig {
  /// The domain used for Universal Links (no scheme, no trailing slash).
  /// Served by the self-hosted admin server — a smart-link landing page that auto-opens
  /// the app or falls back to the App Store / Play Store.
  static const String domain = 'admin.bsheel.app';

  /// Build a shareable HTTPS link to a feed post.
  static String postLink(String postId) =>
      'https://$domain/post/$postId';

  /// Build a shareable HTTPS link to a user profile.
  static String profileLink(String userId) =>
      'https://$domain/user/$userId';

  /// Build a shareable HTTPS link to join a collab quest.
  static String collabInviteLink(String code) =>
      'https://$domain/join/$code';
}
