import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../backend/app_backend.dart';
import 'session_providers.dart';

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => AppBackend.repositories.profiles);

final businessTeamProvider = FutureProvider.autoDispose
    .family<List<BusinessMember>, String>((ref, businessId) {
  return ref.watch(businessRepositoryProvider).members(businessId);
});

/// Outcome of trying to add somebody to the team, so the UI can say which
/// of several different things went wrong.
enum AddMemberOutcome {
  added,

  /// No account with that username. Distinct from a permission problem, and
  /// the only one the owner can fix themselves by checking the spelling.
  unknownUsername,

  /// Already on the team. Not an error worth alarming anyone about.
  alreadyMember,

  /// The server refused — not an owner, suspended, or the membership was
  /// revoked between loading the page and pressing the button.
  refused,

  failed,
}

/// Adds and removes team members.
///
/// Adding is by **username**, not user id: an owner has their colleague's
/// Bsheel handle, not a UUID. The lookup is a separate public read
/// (`profiles/by-username`), so a typo comes back as "no such account"
/// rather than as a failed write nobody can interpret.
class TeamController {
  TeamController(this._businesses, this._profiles);

  final BusinessRepository _businesses;
  final ProfileRepository _profiles;

  Future<AddMemberOutcome> add(
    String businessId,
    String username, {
    BusinessMemberRole role = BusinessMemberRole.manager,
    List<BusinessMember> existing = const [],
  }) async {
    final handle = username.trim().replaceFirst(RegExp(r'^@'), '');
    if (handle.isEmpty) return AddMemberOutcome.unknownUsername;
    try {
      final profile = await _profiles.getProfileByUsername(handle);
      if (profile == null) return AddMemberOutcome.unknownUsername;
      if (existing.any((member) => member.userId == profile.id)) {
        return AddMemberOutcome.alreadyMember;
      }
      await _businesses.addMember(businessId, profile.id, role: role);
      return AddMemberOutcome.added;
    } on ApiException catch (error) {
      // 403/404 from the write are authority, not a bad username: the
      // caller is not an owner, or their own membership just went away.
      if (error.statusCode == 403 || error.statusCode == 404) {
        return AddMemberOutcome.refused;
      }
      return AddMemberOutcome.failed;
    } catch (_) {
      return AddMemberOutcome.failed;
    }
  }

  Future<bool> remove(String businessId, String userId) async {
    try {
      await _businesses.removeMember(businessId, userId);
      return true;
    } catch (_) {
      return false;
    }
  }
}

final teamControllerProvider = Provider<TeamController>((ref) => TeamController(
      ref.watch(businessRepositoryProvider),
      ref.watch(profileRepositoryProvider),
    ));
