/// Admin management of quest chains and collections (#56).
///
/// Rows stay as maps rather than models: these are admin-console tables that
/// render joined fields (step counts, place names, country names) which have
/// no life outside that screen, and `app_models` is for shapes the mobile
/// app also consumes.
abstract class QuestCampaignsRepository {
  /// Chains, newest first, each with its step count.
  Future<List<Map<String, dynamic>>> listChains();

  /// One chain with its steps in order, and enough about each quest to show
  /// the shape — which is the question an admin actually has.
  Future<Map<String, dynamic>> chainDetail(String id);

  Future<Map<String, dynamic>> createChain({
    required String name,
    String description,
    String mode,
    bool isActive,
  });

  Future<Map<String, dynamic>> updateChain(
    String id, {
    String? name,
    String? description,
    String? mode,
    bool? isActive,
  });

  Future<void> deleteChain(String id);

  /// Appends the quest as the next step. The position is decided by the
  /// server, so two admins appending at once cannot claim the same one.
  Future<int> appendStep(String chainId, String questId);

  /// Moves a step. `toOrder` is 1-based and clamped server-side to the
  /// chain's length.
  Future<void> reorderStep(String chainId, String questId, int toOrder);

  /// Removes a step and closes the gap. A hole in the sequence would leave
  /// every later step unreachable, so the server renumbers.
  Future<void> removeStep(String chainId, String questId);

  Future<List<Map<String, dynamic>>> listCollections();
  Future<Map<String, dynamic>> collectionDetail(String id);

  Future<Map<String, dynamic>> createCollection({
    required String name,
    String description,
    String? countryCode,
    bool isPublished,
  });

  /// Pass an empty string for [countryCode] to clear it; omit it to leave it
  /// alone.
  Future<Map<String, dynamic>> updateCollection(
    String id, {
    String? name,
    String? description,
    String? countryCode,
    bool? isPublished,
  });

  Future<void> deleteCollection(String id);
  Future<void> addToCollection(String collectionId, String questId);
  Future<void> removeFromCollection(String collectionId, String questId);

  /// Quests eligible to be added. `scope` of `chain` hides quests already in
  /// one, because a quest can only be a single step; `collection` does not,
  /// since membership there is many-to-many.
  Future<List<Map<String, dynamic>>> assignableQuests({
    String scope,
    String search,
  });
}
