import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/collab/data/collab_providers.dart';
import '../../features/comments/presentation/widgets/comments_section.dart';
import '../../features/feed/presentation/providers/feed_provider.dart';
import '../../features/follows/data/follows_providers.dart';
import '../../features/leaderboard/presentation/providers/leaderboard_provider.dart';
import '../../features/notifications/presentation/providers/notifications_provider.dart';
import '../../features/quests/data/quest_providers.dart';
import '../../features/reactions/presentation/providers/reaction_controller.dart';
import '../../features/search/presentation/providers/search_provider.dart';
import '../../features/submissions/data/submission_providers.dart';
import '../providers/auth_repository_provider.dart';
import '../providers/profile_repository_provider.dart';
import 'mobile_nest_backend.dart';

/// Repository overrides for the Nest canary composition root.
///
/// Keeping these in one list makes the dependency boundary reviewable and
/// guarantees every feature shares the same [NestRepositoryBundle].
List<Override> mobileNestRepositoryOverrides() {
  final repositories = MobileNestBackend.repositories;
  return [
    authRepositoryProvider.overrideWithValue(repositories.auth),
    profileRepositoryProvider.overrideWithValue(repositories.profiles),
    collabRepositoryProvider.overrideWithValue(repositories.collab),
    commentsRepositoryProvider.overrideWithValue(repositories.comments),
    feedRepositoryProvider.overrideWithValue(repositories.feed),
    followsRepositoryProvider.overrideWithValue(repositories.follows),
    leaderboardRepositoryProvider.overrideWithValue(repositories.leaderboard),
    notificationsRepositoryProvider
        .overrideWithValue(repositories.notifications),
    questsRepositoryProvider.overrideWithValue(repositories.quests),
    savedQuestsRepositoryProvider.overrideWithValue(repositories.savedQuests),
    reactionsRepositoryProvider.overrideWithValue(repositories.reactions),
    savedPostsRepositoryProvider.overrideWithValue(repositories.savedPosts),
    searchRepositoryProvider.overrideWithValue(repositories.search),
    submissionsRepositoryProvider.overrideWithValue(repositories.submissions),
  ];
}
