import 'package:app_models/app_models.dart';

/// Reads the discovery shelves Home renders.
///
/// The contract is deliberately narrow: the server decides which modules
/// exist, in what order, and what is eligible for this user. Anything wider
/// would invite the client to start filtering, and a client that filters is
/// a client that eventually shows a hidden quest or an expired event.
abstract class DiscoveryRepository {
  /// The modules Home should render, already ranked and already safe to show.
  Future<List<DiscoveryModule>> homeModules();

  /// Flagship destination quests, browsable from anywhere.
  Future<List<DiscoveryQuestCard>> worthTheTrip({int limit});

  /// Destination quests in one country. Presence is not required to browse.
  Future<List<DiscoveryQuestCard>> byCountry(String countryCode, {int limit});

  /// Countries the catalogue has quests for, for the EXPLORE picker.
  Future<List<DiscoveryCountry>> countries();

  /// One more quest from a shelf's pool, past what is already on screen.
  ///
  /// [exclude] is what the shelf is showing. Without it a small catalogue
  /// hands back a card the player is already looking at, which reads as
  /// broken rather than as a small catalogue.
  Future<DiscoveryQuestCard?> generate({
    required String channel,
    String? countryCode,
    List<String> exclude,
  });

  /// The milestone line for a multi-step quest, or null when it is not one.
  Future<QuestJourney?> journey(String questId);
}
