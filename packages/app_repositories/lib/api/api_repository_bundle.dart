import '../account/api_account_repository.dart';
import '../admin/api_admin_repository.dart';
import '../auth/api_auth_repository.dart';
import '../collab/api_collab_repository.dart';
import '../comments/api_comments_repository.dart';
import '../feed/api_feed_repository.dart';
import '../follows/api_follows_repository.dart';
import '../leaderboard/api_leaderboard_repository.dart';
import '../moderation/api_moderation_repository.dart';
import '../notifications/api_notifications_repository.dart';
import '../profile/api_profile_repository.dart';
import '../public_config/api_public_config_repository.dart';
import '../quest_campaigns/api_quest_campaigns_repository.dart';
import '../quests/api_quests_repository.dart';
import '../quest_authoring/api_quest_authoring_repository.dart';
import '../journeys/api_journeys_repository.dart';
import '../discovery/api_discovery_repository.dart';
import '../reactions/api_reactions_repository.dart';
import '../realtime/api_realtime_client.dart';
import '../saved_posts/api_saved_posts_repository.dart';
import '../saved_quests/api_saved_quests_repository.dart';
import '../search/api_search_repository.dart';
import '../submissions/api_submissions_repository.dart';
import 'api_client.dart';
import '../map/map_repository.dart';

/// One composition object for the Flutter mobile and admin applications.
///
/// Constructing repositories here keeps their shared transport and rotating
/// token store singletons explicit. Riverpod providers should expose these
/// instances rather than constructing a client per feature.
class ApiRepositoryBundle {
  ApiRepositoryBundle({
    required Uri baseUrl,
    required ApiTokenStore tokenStore,
    String googleIosClientId = '',
    String googleWebClientId = '',
  })  : client = ApiClient(baseUrl: baseUrl, tokenStore: tokenStore),
        _tokenStore = tokenStore,
        _googleIosClientId = googleIosClientId,
        _googleWebClientId = googleWebClientId;

  final ApiClient client;
  final ApiTokenStore _tokenStore;
  final String _googleIosClientId;
  final String _googleWebClientId;

  late final ApiAuthRepository auth = ApiAuthRepository(
    client,
    _tokenStore,
    googleIosClientId: _googleIosClientId,
    googleWebClientId: _googleWebClientId,
  );
  late final ApiAccountRepository account = ApiAccountRepository(client);
  late final MapRepository map = ApiMapRepository(client);
  late final ApiAdminRepository admin = ApiAdminRepository(client);
  late final ApiCollabRepository collab = ApiCollabRepository(client);
  late final ApiCommentsRepository comments = ApiCommentsRepository(client);
  late final ApiFeedRepository feed = ApiFeedRepository(client);
  late final ApiFollowsRepository follows = ApiFollowsRepository(client);
  late final ApiLeaderboardRepository leaderboard =
      ApiLeaderboardRepository(client);
  late final ApiModerationRepository moderation =
      ApiModerationRepository(client);
  late final ApiNotificationsRepository notifications =
      ApiNotificationsRepository(client);
  late final ApiProfileRepository profiles = ApiProfileRepository(client);
  late final ApiPublicConfigRepository publicConfig =
      ApiPublicConfigRepository(client);
  late final ApiQuestsRepository quests = ApiQuestsRepository(client);
  late final ApiQuestAuthoringRepository questAuthoring =
      ApiQuestAuthoringRepository(client);
  late final ApiDiscoveryRepository discovery = ApiDiscoveryRepository(client);
  late final ApiJourneysRepository journeys = ApiJourneysRepository(client);
  late final ApiQuestCampaignsRepository questCampaigns =
      ApiQuestCampaignsRepository(client);
  late final ApiReactionsRepository reactions = ApiReactionsRepository(client);
  late final ApiRealtimeClient realtime = ApiRealtimeClient(client);
  late final ApiSavedPostsRepository savedPosts =
      ApiSavedPostsRepository(client);
  late final ApiSavedQuestsRepository savedQuests =
      ApiSavedQuestsRepository(client);
  late final ApiSearchRepository search = ApiSearchRepository(client);
  late final ApiSubmissionsRepository submissions =
      ApiSubmissionsRepository(client);

  Future<void> initialize() {
    // Wired here rather than in the constructor because `auth` is a late
    // field on this same object, and Dart will not let a field initializer
    // read `this`. From now on a refresh failure emits signedOut, the router
    // hears it, and the user is asked to sign in instead of being left on a
    // Home screen where nothing loads.
    client.onSessionExpired = auth.notifySessionExpired;
    return auth.restoreSession();
  }

  void close() {
    realtime.dispose();
    auth.dispose();
    client.close();
  }
}
