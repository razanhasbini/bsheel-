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
}
