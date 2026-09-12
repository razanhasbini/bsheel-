library;

/// Shared JSON coercions.
///
/// Exported because they are not an app_models private concern: Postgres
/// sends `numeric` as TEXT, so anything reading this API has to parse it.
/// The admin console hit that with a hard `as num?` on a verification
/// confidence and crashed the page — a bug this file had already solved for
/// hot_score and simply could not be reached to reuse.
export 'src/json_coercions.dart'
    show
        coerceInt,
        coerceNullableInt,
        coerceDouble,
        coerceNullableDouble,
        coerceBool;

export 'journey_post_stop.dart';
export 'profile_model.dart';
export 'quest_model.dart';
export 'user_quest_model.dart';
export 'submission_model.dart';
export 'reaction_model.dart';
export 'notification_model.dart';
export 'leaderboard_user_model.dart';
export 'feed_post_model.dart';
export 'moderation_decision_model.dart';
export 'admin_model.dart';
export 'comment_model.dart';
export 'collab_invite_model.dart';
export 'collab_status_model.dart';
export 'collab_feed_member.dart';
export 'saved_post_model.dart';
export 'saved_post_with_quest_model.dart';
export 'quest_of_the_day_model.dart';
export 'map_models.dart';

export 'discovery/discovery_module.dart';
export 'discovery/quest_journey.dart';
export 'discovery/journey_run.dart';
export 'business_models.dart';
