/// Repository contracts and their HTTP implementations against the
/// self-hosted Bsheel API.
///
/// Features depend on the abstract contract; the concrete `Api*Repository`
/// is wired once per application in its `AppBackend` composition root.
library;
export 'map/map_repository.dart';

// ── Transport and composition ────────────────────────────────────────────
export 'api/api_client.dart';
export 'api/api_repository_bundle.dart';
export 'api/secure_api_token_store.dart';

// ── Auth ─────────────────────────────────────────────────────────────────
export 'auth/auth_models.dart';
export 'auth/auth_repository.dart';
export 'auth/api_auth_repository.dart';

// ── Account ──────────────────────────────────────────────────────────────
export 'account/api_account_repository.dart';

// ── Profile ──────────────────────────────────────────────────────────────
export 'profile/profile_repository.dart';
export 'profile/api_profile_repository.dart';

// ── Quests ───────────────────────────────────────────────────────────────
export 'quests/quests_repository.dart';
export 'quests/api_quests_repository.dart';

// ── Submissions ──────────────────────────────────────────────────────────
export 'submissions/submissions_repository.dart';
export 'submissions/api_submissions_repository.dart';

// ── Feed ─────────────────────────────────────────────────────────────────
export 'feed/feed_repository.dart';
export 'feed/api_feed_repository.dart';

// ── Reactions ────────────────────────────────────────────────────────────
export 'reactions/reactions_repository.dart';
export 'reactions/api_reactions_repository.dart';

// ── Leaderboard ──────────────────────────────────────────────────────────
export 'leaderboard/leaderboard_repository.dart';
export 'leaderboard/api_leaderboard_repository.dart';

// ── Notifications ────────────────────────────────────────────────────────
export 'notifications/notifications_repository.dart';
export 'notifications/api_notifications_repository.dart';

// ── Moderation ───────────────────────────────────────────────────────────
export 'moderation/moderation_repository.dart';
export 'moderation/api_moderation_repository.dart';

// ── Comments ─────────────────────────────────────────────────────────────
export 'comments/comments_repository.dart';
export 'comments/api_comments_repository.dart';

// ── Follows ──────────────────────────────────────────────────────────────
export 'follows/follows_repository.dart';
export 'follows/api_follows_repository.dart';

// ── Saved posts ──────────────────────────────────────────────────────────
export 'saved_posts/saved_posts_repository.dart';
export 'saved_posts/api_saved_posts_repository.dart';

// ── Saved quests ─────────────────────────────────────────────────────────
export 'saved_quests/saved_quests_repository.dart';
export 'saved_quests/api_saved_quests_repository.dart';

// ── Collab ───────────────────────────────────────────────────────────────
export 'collab/collab_repository.dart';
export 'collab/api_collab_repository.dart';

// ── Search ───────────────────────────────────────────────────────────────
export 'search/search_repository.dart';
export 'search/api_search_repository.dart';

// ── Admin ────────────────────────────────────────────────────────────────
export 'admin/admin_repository.dart';
export 'admin/api_admin_repository.dart';

// ── Public config ────────────────────────────────────────────────────────
export 'public_config/api_public_config_repository.dart';

// ── Media ────────────────────────────────────────────────────────────────
export 'media/api_media_signer.dart';
export 'media/api_media_uploader.dart';

// ── Realtime ─────────────────────────────────────────────────────────────
export 'realtime/api_realtime_client.dart';
