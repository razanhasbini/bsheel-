/// Nest API adapters used during the backend strangler migration.
///
/// The original `app_repositories.dart` remains byte-identical to the legacy
/// source. Composition roots can import this library and switch one verified
/// repository at a time without destroying the rollback baseline.
library nest_api_repositories;

export 'api/api_client.dart';
export 'api/nest_repository_bundle.dart';
export 'api/secure_api_token_store.dart';
export 'auth/auth_repository.dart';
export 'auth/api_auth_repository.dart';
export 'account/api_account_repository.dart';
export 'admin/admin_repository.dart';
export 'admin/api_admin_repository.dart';
export 'collab/collab_repository.dart';
export 'collab/api_collab_repository.dart';
export 'comments/comments_repository.dart';
export 'comments/api_comments_repository.dart';
export 'feed/feed_repository.dart';
export 'feed/api_feed_repository.dart';
export 'follows/follows_repository.dart';
export 'follows/api_follows_repository.dart';
export 'leaderboard/leaderboard_repository.dart';
export 'leaderboard/api_leaderboard_repository.dart';
export 'media/api_media_signer.dart';
export 'media/api_media_uploader.dart';
export 'moderation/moderation_repository.dart';
export 'moderation/api_moderation_repository.dart';
export 'notifications/notifications_repository.dart';
export 'notifications/api_notifications_repository.dart';
export 'profile/profile_repository.dart';
export 'profile/api_profile_repository.dart';
export 'public_config/api_public_config_repository.dart';
export 'quests/quests_repository.dart';
export 'quests/api_quests_repository.dart';
export 'reactions/reactions_repository.dart';
export 'reactions/api_reactions_repository.dart';
export 'realtime/api_realtime_client.dart';
export 'saved_posts/saved_posts_repository.dart';
export 'saved_posts/api_saved_posts_repository.dart';
export 'saved_quests/saved_quests_repository.dart';
export 'saved_quests/api_saved_quests_repository.dart';
export 'search/search_repository.dart';
export 'search/api_search_repository.dart';
export 'submissions/submissions_repository.dart';
export 'submissions/api_submissions_repository.dart';
