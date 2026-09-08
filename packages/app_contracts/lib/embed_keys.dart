/// JSON keys for the nested objects the API embeds in a response.
///
/// `GET /submissions/:id` returns the author under `profiles` and the quest
/// under `quests`, for example. These are wire field names, not table names —
/// the clients do not speak SQL.
///
/// Only the embeds the clients actually read are declared. The rest of the
/// legacy table list went with the direct-database access that needed it.
abstract final class EmbedKeys {
  static const String profiles = 'profiles';
  static const String quests = 'quests';
  static const String userQuests = 'user_quests';
}
