import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_web/core/providers/team_controller.dart';

/// Adding somebody to the team.
///
/// The point of these cases is that the four failures are *told apart*. An
/// owner who mistyped a handle, an owner who already added that person, an
/// owner whose own membership was revoked, and a dropped connection all
/// need different next actions, and a single "could not add member" would
/// serve none of them.
void main() {
  ProfileModel profile(String id, String username) => ProfileModel(
        id: id,
        username: username,
        displayName: username,
        createdAt: DateTime.utc(2026, 1, 1),
      );

  BusinessMember member(String id, String username) => BusinessMember(
        userId: id,
        username: username,
        displayName: username,
        role: BusinessMemberRole.manager,
      );

  TeamController controllerWith({
    ProfileModel? found,
    Object? addThrows,
  }) =>
      TeamController(
        _FakeBusinesses(addThrows: addThrows),
        _FakeProfiles(found),
      );

  test('adds a member found by username', () async {
    final businesses = _FakeBusinesses();
    final controller =
        TeamController(businesses, _FakeProfiles(profile('u2', 'colleague')));

    final outcome = await controller.add('b1', 'colleague');

    expect(outcome, AddMemberOutcome.added);
    expect(businesses.added, [('b1', 'u2', BusinessMemberRole.manager)]);
  });

  test('tolerates a leading @ and surrounding space', () async {
    final profiles = _FakeProfiles(profile('u2', 'colleague'));
    final controller = TeamController(_FakeBusinesses(), profiles);

    await controller.add('b1', '  @colleague ');

    // The handle is what gets looked up, not the decoration around it.
    expect(profiles.asked, ['colleague']);
  });

  // A typo is the likeliest failure and the only one the owner can fix
  // alone, so it must not look like a server problem.
  test('reports an unknown username without attempting a write', () async {
    final businesses = _FakeBusinesses();
    final controller = TeamController(businesses, _FakeProfiles(null));

    final outcome = await controller.add('b1', 'nobody');

    expect(outcome, AddMemberOutcome.unknownUsername);
    expect(businesses.added, isEmpty);
  });

  test('treats an empty handle as an unknown username', () async {
    final businesses = _FakeBusinesses();
    final controller = TeamController(businesses, _FakeProfiles(null));

    expect(await controller.add('b1', '   '), AddMemberOutcome.unknownUsername);
    expect(businesses.added, isEmpty);
  });

  // Not an error worth alarming anyone about, and not a write worth making.
  test('recognises somebody already on the team', () async {
    final businesses = _FakeBusinesses();
    final controller =
        TeamController(businesses, _FakeProfiles(profile('u2', 'colleague')));

    final outcome = await controller
        .add('b1', 'colleague', existing: [member('u2', 'colleague')]);

    expect(outcome, AddMemberOutcome.alreadyMember);
    expect(businesses.added, isEmpty);
  });

  /// The authority cases. 403 and 404 from the *write* mean the caller is
  /// not an owner, or their own membership went away between loading the
  /// page and pressing the button — never that the username was wrong.
  test('separates a refusal from a bad username', () async {
    for (final status in [403, 404]) {
      final controller = controllerWith(
        found: profile('u2', 'colleague'),
        addThrows: ApiException(
            statusCode: status, code: 'REFUSED', message: 'refused'),
      );

      expect(await controller.add('b1', 'colleague'), AddMemberOutcome.refused,
          reason: 'status $status');
    }
  });

  test('reports anything else as a plain failure', () async {
    final controller = controllerWith(
      found: profile('u2', 'colleague'),
      addThrows: Exception('offline'),
    );

    expect(await controller.add('b1', 'colleague'), AddMemberOutcome.failed);
  });

  test('passes the chosen role through', () async {
    final businesses = _FakeBusinesses();
    final controller =
        TeamController(businesses, _FakeProfiles(profile('u2', 'colleague')));

    await controller.add('b1', 'colleague', role: BusinessMemberRole.owner);

    expect(businesses.added.single.$3, BusinessMemberRole.owner);
  });

  group('removing', () {
    test('reports success', () async {
      final controller = TeamController(_FakeBusinesses(), _FakeProfiles(null));

      expect(await controller.remove('b1', 'u2'), isTrue);
    });

    // The server refuses to remove the last owner. That is the common case
    // here, and the UI turns this false into that explanation.
    test('reports a refusal rather than throwing', () async {
      final controller = TeamController(
        _FakeBusinesses(
            removeThrows: const ApiException(
                statusCode: 409,
                code: 'LAST_BUSINESS_OWNER',
                message: 'conflict')),
        _FakeProfiles(null),
      );

      expect(await controller.remove('b1', 'u2'), isFalse);
    });
  });
}

class _FakeProfiles implements ProfileRepository {
  _FakeProfiles(this._found);

  final ProfileModel? _found;
  final List<String> asked = [];

  @override
  Future<ProfileModel?> getProfileByUsername(String username) async {
    asked.add(username);
    return _found;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}

class _FakeBusinesses implements BusinessRepository {
  _FakeBusinesses({this.addThrows, this.removeThrows});

  final Object? addThrows;
  final Object? removeThrows;
  final List<(String, String, BusinessMemberRole)> added = [];

  @override
  Future<void> addMember(String businessId, String userId,
      {BusinessMemberRole role = BusinessMemberRole.manager}) async {
    if (addThrows != null) throw addThrows!;
    added.add((businessId, userId, role));
  }

  @override
  Future<void> removeMember(String businessId, String userId) async {
    if (removeThrows != null) throw removeThrows!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}
