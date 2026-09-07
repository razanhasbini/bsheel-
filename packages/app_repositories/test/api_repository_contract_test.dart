import 'dart:convert';

import 'package:app_repositories/nest_api_repositories.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_contracts/supabase_contracts.dart';
import 'package:test/test.dart';

http.Response success(Object? data, [int status = 200]) => http.Response(
      jsonEncode({
        'success': true,
        'data': data,
        'meta': {'requestId': 'repository-contract'},
      }),
      status,
      headers: {'content-type': 'application/json'},
    );

ApiClient fixtureClient(
  Future<http.Response> Function(http.Request request) handler,
) =>
    ApiClient(
      baseUrl: Uri.parse('https://api.example.test/api/v1/'),
      tokenStore: InMemoryApiTokenStore(),
      httpClient: MockClient(handler),
    );

Map<String, Object?> questRow({String id = 'quest-1'}) => {
      'id': id,
      'title': 'Take a photo walk',
      'description': 'Walk outside and photograph something interesting.',
      'category': 'adventure',
      'difficulty': 'easy',
      'xp_reward': 25,
      'duration_hours': 4,
      'is_active': true,
      'created_by': null,
      'created_at': '2026-09-07T10:00:00.000Z',
      'updated_at': null,
    };

void main() {
  group('quest contract', () {
    test('maps the picker envelope and sends its bounded count', () async {
      final repository = ApiQuestsRepository(
        fixtureClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/quests/picker');
          expect(request.url.queryParameters, {'count': '3'});
          return success([questRow()]);
        }),
      );

      final quests = await repository.getQuestPickerOptions();
      expect(quests.single.id, 'quest-1');
      expect(quests.single.xpReward, 25);
      expect(quests.single.durationHours, 4);
    });

    test('assigns a quest and maps the nested legacy quest shape', () async {
      final repository = ApiQuestsRepository(
        fixtureClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/quests/assign');
          expect(jsonDecode(request.body), {'questId': 'quest-1'});
          return success({
            'id': 'user-quest-1',
            'user_id': 'user-1',
            'quest_id': 'quest-1',
            'status': UserQuestStatus.assigned,
            'assigned_at': '2026-09-07T10:05:00.000Z',
            'completed_at': null,
            'expires_at': '2026-09-07T14:05:00.000Z',
            'quests': questRow(),
          });
        }),
      );

      final assignment =
          await repository.assignSpecificQuest('ignored-user', 'quest-1');
      expect(assignment.userId, 'user-1');
      expect(assignment.quest?.title, 'Take a photo walk');
      expect(assignment.status, UserQuestStatus.assigned);
    });
  });

  group('social contract', () {
    test('maps follow state/counts and preserves server-owned identity',
        () async {
      final seen = <String>[];
      final repository = ApiFollowsRepository(
        fixtureClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.url.path.endsWith('/following')) {
            return success({'following': true});
          }
          if (request.url.path.endsWith('/follow-counts')) {
            return success({'followers': 12, 'following': 7});
          }
          if (request.method == 'POST') return success({'id': 'follow-row-1'});
          return success(null, 204);
        }),
      );

      expect(await repository.isFollowing('target-1'), isTrue);
      expect(await repository.follow('target-1'), 'follow-row-1');
      expect(
        await repository.getFollowCounts('target-1'),
        (followers: 12, following: 7),
      );
      await repository.unfollow('target-1');
      expect(seen, contains('DELETE /api/v1/social/users/target-1/follow'));
    });

    test('rejects an invalid vote locally and sends a valid vote', () async {
      var networkCalls = 0;
      final repository = ApiReactionsRepository(
        fixtureClient((request) async {
          networkCalls++;
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/v1/social/posts/post-1/vote');
          expect(jsonDecode(request.body), {'type': ReactionType.upvote});
          return success({
            'id': 'reaction-1',
            'submission_id': 'post-1',
            'user_id': 'user-1',
            'type': ReactionType.upvote,
            'created_at': '2026-09-07T10:10:00.000Z',
          });
        }),
      );

      await expectLater(
        repository.vote('post-1', 'user-1', 'clap'),
        throwsArgumentError,
      );
      expect(networkCalls, 0);
      final reaction = await repository.vote(
        'post-1',
        'user-1',
        ReactionType.upvote,
      );
      expect(reaction.type, ReactionType.upvote);
      expect(networkCalls, 1);
    });

    test('maps saved-quest state and idempotent mutation routes', () async {
      final requests = <String>[];
      final repository = ApiSavedQuestsRepository(
        fixtureClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'GET') return success({'saved': true});
          return success(null, 204);
        }),
      );

      expect(await repository.isQuestSaved('quest-1', 'ignored-user'), isTrue);
      await repository.saveQuest('quest-1', 'ignored-user');
      await repository.unsaveQuest('quest-1', 'ignored-user');
      expect(requests, [
        'GET /api/v1/social/saved/quests/quest-1',
        'PUT /api/v1/social/saved/quests/quest-1',
        'DELETE /api/v1/social/saved/quests/quest-1',
      ]);
    });
  });

  group('account and admin contract', () {
    test('registers device tokens without exposing a user id', () async {
      final repository = ApiAccountRepository(
        fixtureClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/notifications/devices');
          expect(jsonDecode(request.body), {
            'token': 'fcm-token',
            'platform': 'ios',
          });
          return success({'id': 'device-1'});
        }),
      );

      expect(
        await repository.registerDeviceToken('fcm-token', 'ios'),
        'device-1',
      );
    });

    test('maps admin roles and sends typed configuration values', () async {
      final repository = ApiAdminRepository(
        fixtureClient((request) async {
          if (request.url.path.endsWith('/admin/me')) {
            return success({'role': 'super_admin'});
          }
          expect(request.method, 'PUT');
          expect(request.url.path, '/api/v1/admin/config/feed_page_size');
          expect(jsonDecode(request.body), {
            'value': 24,
            'description': 'Feed page size',
            'isPublic': true,
          });
          return success({'key': 'feed_page_size', 'value': 24});
        }),
      );

      expect(
        await repository.getCurrentUserRole(),
        AdminRoleEnum.superAdmin,
      );
      final row = await repository.setConfig(
        'feed_page_size',
        value: 24,
        description: 'Feed page size',
        isPublic: true,
      );
      expect(row['value'], 24);
    });

    test('lists, actions, and bans report targets through admin commands',
        () async {
      final seen = <String>[];
      final repository = ApiAdminRepository(
        fixtureClient((request) async {
          seen.add('${request.method} ${request.url.path}');
          if (request.method == 'GET') {
            expect(request.url.queryParameters, {
              'status': 'all',
              'limit': '100',
              'offset': '0',
            });
            return success([
              {
                'id': 'report-1',
                'status': 'pending',
                'reported_user_id': 'user-2',
                'reported_username': 'reported_user',
              },
            ]);
          }
          if (request.url.path.endsWith('/reports/report-1')) {
            expect(jsonDecode(request.body), {'status': 'actioned'});
          } else {
            expect(request.url.path, '/api/v1/admin/users/user-2/status');
            expect(jsonDecode(request.body), {
              'status': 'banned',
              'reason': 'Content report report-1',
            });
          }
          return success(null, 204);
        }),
      );

      final reports = await repository.reports(status: 'all', limit: 100);
      expect(reports.single['reported_user_id'], 'user-2');
      await repository.reviewReport('report-1', status: 'actioned');
      await repository.setAccountStatus(
        'user-2',
        'banned',
        'Content report report-1',
      );
      expect(seen, [
        'GET /api/v1/admin/reports',
        'PATCH /api/v1/admin/reports/report-1',
        'PATCH /api/v1/admin/users/user-2/status',
      ]);
    });
  });
}
