import 'package:app_models/app_models.dart';
import 'package:app_repositories/app_repositories.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:business_web/core/providers/session_providers.dart';

/// Which business the dashboard shows.
///
/// The mobile card appends `?business=<id>` so an owner of two lands on the
/// right one. That id arrives from a URL, so the rule that matters is that
/// it selects *among what the caller may already see* and can never widen
/// it. The API would refuse a foreign id anyway — it answers a non-member
/// with a 404 — but a client that asked would render a loading state and
/// then an error for a business the person has no business knowing exists.
void main() {
  BusinessSummary summary(String id, String name) => BusinessSummary(
        id: id,
        name: name,
        slug: name.toLowerCase().replaceAll(' ', '-'),
        status: BusinessStatus.active,
        membershipRole: BusinessMemberRole.owner,
        analyticsSubscribed: true,
      );

  ProviderContainer containerWith(
    List<BusinessSummary> businesses, {
    String? requested,
  }) {
    final container = ProviderContainer(overrides: [
      sessionProvider.overrideWith((ref) => const AuthUser(id: 'u1')),
      businessRepositoryProvider
          .overrideWithValue(_FakeBusinessRepository(businesses)),
      selectedBusinessIdProvider.overrideWith((ref) => requested),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<BusinessSummary?> resolve(ProviderContainer container) async {
    await container.read(myBusinessesProvider.future);
    return container.read(activeBusinessProvider);
  }

  test('uses the only business when the caller belongs to one', () async {
    final container = containerWith([summary('b1', 'Tawlet')]);

    expect((await resolve(container))?.id, 'b1');
  });

  test('honours a requested id the caller actually belongs to', () async {
    final container = containerWith(
      [summary('b1', 'Tawlet'), summary('b2', 'Second')],
      requested: 'b2',
    );

    expect((await resolve(container))?.id, 'b2');
  });

  // The rule this file exists for: an id from the URL that is not the
  // caller's selects nothing. It falls back to a business they do belong
  // to rather than attempting a read the server would refuse.
  test('ignores an id the caller does not belong to', () async {
    final container = containerWith(
      [summary('b1', 'Tawlet')],
      requested: 'someone-elses-business',
    );

    final active = await resolve(container);
    expect(active?.id, 'b1');
    expect(active?.id, isNot('someone-elses-business'));
  });

  test('resolves to nothing for a caller who belongs to none', () async {
    final container = containerWith([]);

    expect(await resolve(container), isNull);
  });

  test('asks for nothing while signed out', () async {
    final repository = _FakeBusinessRepository([summary('b1', 'Tawlet')]);
    final container = ProviderContainer(overrides: [
      sessionProvider.overrideWith((ref) => null),
      businessRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);

    expect(await container.read(myBusinessesProvider.future), isEmpty);
    expect(repository.calls, 0);
  });
}

class _FakeBusinessRepository implements BusinessRepository {
  _FakeBusinessRepository(this._businesses);

  final List<BusinessSummary> _businesses;
  int calls = 0;

  @override
  Future<List<BusinessSummary>> mine() async {
    calls += 1;
    return _businesses;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      '${invocation.memberName} is not used by this test');
}
