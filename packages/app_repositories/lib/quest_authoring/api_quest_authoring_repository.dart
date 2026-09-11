import '../api/api_client.dart';
import 'quest_authoring_models.dart';

/// The admin authoring surface.
///
/// Kept apart from `QuestsRepository` because that contract is implemented
/// by the mobile app too, and none of this belongs there: authoring is a
/// console concern, and every route behind it is `super_admin`.
class ApiQuestAuthoringRepository {
  ApiQuestAuthoringRepository(this._client);

  final ApiClient _client;

  /// Creates one quest with every dimension set at once.
  Future<AuthoredQuest> authorQuest(QuestDraft draft) async =>
      AuthoredQuest.fromJson(
        apiObject(
          await _client.post(
            'quests/authoring/quests',
            body: draft.toJson(),
          ),
        ),
      );

  /// Creates a whole multi-stage quest — every step and its unlock — in one
  /// server-side transaction.
  Future<ChainOverview> authorChain(ChainDraft draft) async =>
      ChainOverview.fromJson(
        apiObject(
          await _client.post(
            'quests/authoring/chains',
            body: draft.toJson(),
          ),
        ),
      );

  Future<List<AuthoredQuest>> catalogue(
          {int limit = 100, int offset = 0}) async =>
      apiObjectList(
        await _client.get(
          'quests/authoring/catalogue',
          query: {'limit': '$limit', 'offset': '$offset'},
        ),
      ).map(AuthoredQuest.fromJson).toList(growable: false);

  Future<List<ChainOverview>> chains() async =>
      apiObjectList(await _client.get('quests/authoring/chains'))
          .map(ChainOverview.fromJson)
          .toList(growable: false);
}
