import 'package:app_models/app_models.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../media/signed_media_urls.dart';
import 'search_repository.dart';

class SupabaseSearchRepository implements SearchRepository {
  final SupabaseClient _client;
  SupabaseSearchRepository(this._client);

  String _escape(String raw) =>
      raw.replaceAll('%', r'\%').replaceAll('_', r'\_');

  @override
  Future<List<ProfileModel>> searchUsers(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final pattern = '%${_escape(trimmed)}%';

    final rows = await _client
        .from(Tables.profiles)
        .select()
        .or(
          '${ProfileColumns.username}.ilike.$pattern,'
          '${ProfileColumns.displayName}.ilike.$pattern',
        )
        .order(ProfileColumns.xp, ascending: false)
        .limit(limit);

    final profiles = (rows as List<dynamic>)
        .map((row) => ProfileModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return Future.wait(profiles.map(_withSignedAvatar));
  }

  @override
  Future<List<QuestModel>> searchQuests(String query, {int limit = 20}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final pattern = '%${_escape(trimmed)}%';

    final rows = await _client
        .from(Tables.quests)
        .select()
        .eq(QuestColumns.isActive, true)
        .or(
          '${QuestColumns.title}.ilike.$pattern,'
          '${QuestColumns.description}.ilike.$pattern,'
          '${QuestColumns.category}.ilike.$pattern',
        )
        .order(QuestColumns.xpReward, ascending: false)
        .limit(limit);

    return (rows as List<dynamic>)
        .map((row) => QuestModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<List<SubmissionModel>> searchPosts(
    String query, {
    required String currentUserId,
    int limit = 24,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final pattern = '%${_escape(trimmed)}%';

    // 1) Find matching quest IDs.
    final questRows = await _client
        .from(Tables.quests)
        .select(QuestColumns.id)
        .eq(QuestColumns.isActive, true)
        .or(
          '${QuestColumns.title}.ilike.$pattern,'
          '${QuestColumns.description}.ilike.$pattern,'
          '${QuestColumns.category}.ilike.$pattern',
        )
        .limit(80);
    final questIds = (questRows as List<dynamic>)
        .map((r) => (r as Map<String, dynamic>)[QuestColumns.id] as String)
        .toList();

    // 2) Find user_quest IDs that reference those quests.
    final List<String> userQuestIds;
    if (questIds.isEmpty) {
      userQuestIds = const [];
    } else {
      final uqRows = await _client
          .from(Tables.userQuests)
          .select(UserQuestColumns.id)
          .inFilter(UserQuestColumns.questId, questIds)
          .limit(400);
      userQuestIds = (uqRows as List<dynamic>)
          .map(
            (r) => (r as Map<String, dynamic>)[UserQuestColumns.id] as String,
          )
          .toList();
    }

    // 3) Submissions: current user's own OR ones tied to a matching user_quest.
    // Approved and visible only. If the user's posts are empty AND no matching
    // user_quests exist, short-circuit to avoid an `or()` filter with one term.
    final filters = <String>[
      '${SubmissionColumns.userId}.eq.$currentUserId',
    ];
    if (userQuestIds.isNotEmpty) {
      filters.add(
        '${SubmissionColumns.userQuestId}.in.(${userQuestIds.join(",")})',
      );
    }

    // Pull joined quest + author fields so the post tile can show the
    // quest name and the user's display name without a second round-trip.
    //
    // FK hints are required: submissions has TWO FKs to profiles (user_id
    // and reviewed_by), so PostgREST refuses to pick one without a hint.
    // user_quests has a single FK from submissions.user_quest_id, hinted
    // here too just to keep the call explicit.
    const select = '*, '
        '${Tables.userQuests}!${SubmissionColumns.userQuestId}'
        '(${UserQuestColumns.questId}, '
        '${Tables.quests}(${QuestColumns.title})), '
        '${Tables.profiles}!${SubmissionColumns.userId}'
        '(${ProfileColumns.username}, ${ProfileColumns.displayName})';

    final rows = await _client
        .from(Tables.submissions)
        .select(select)
        .eq(SubmissionColumns.status, SubmissionStatus.approved)
        .eq(SubmissionColumns.visibility, SubmissionVisibility.visible)
        .or(filters.join(','))
        .order(SubmissionColumns.submittedAt, ascending: false)
        .limit(limit);

    final submissions = (rows as List<dynamic>)
        .map((row) => SubmissionModel.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    return Future.wait(submissions.map(_withSignedMedia));
  }

  Future<ProfileModel> _withSignedAvatar(ProfileModel profile) async {
    final avatarUrl = await SignedMediaUrls.signNullable(
      _client,
      profile.avatarUrl,
    );
    return profile.copyWith(avatarUrl: avatarUrl);
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
}
