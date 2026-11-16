import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jadewell_flutter_app/data/api/api_client.dart';
import 'package:jadewell_flutter_app/data/api/api_result.dart';
import 'package:jadewell_flutter_app/data/api/install_identity.dart';
import 'package:jadewell_flutter_app/data/api/social_api.dart';
import 'package:jadewell_flutter_app/data/repositories/social_repository.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _dailyJson = '''
{
  "date": "2026-11-16",
  "layout_id": "lotus",
  "total_players": 143,
  "entries": [
    {"rank": 1, "user_id": "a", "display_name": "Mira K.", "avatar_color": "#E06A4E", "stars": 3, "time_ms": 298000, "is_me": false},
    {"rank": 2, "user_id": "b", "display_name": "tilewhisper", "avatar_color": "#2E8B57", "stars": 3, "time_ms": 311000},
    {"rank": 3, "user_id": "c", "display_name": "Kofi A.", "avatar_color": null, "stars": 2, "time_ms": 286000}
  ],
  "me": {"rank": 27, "user_id": "me", "display_name": "Jade Otter", "avatar_color": "#14897A", "stars": 2, "time_ms": 462000, "top_percent": 18}
}
''';

late InstallIdentity _identity;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Jadewell',
      packageName: 'com.pranta.jadewell',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    _identity = await InstallIdentity.load();
  });

  group('FriendCodes', () {
    test('accepts canonical codes', () {
      expect(FriendCodes.isValid('JW-7K3P9Q'), isTrue);
      expect(FriendCodes.isValid('JW-7K3P9'), isFalse);
      expect(FriendCodes.isValid('JW-7K3P9I'), isFalse, reason: 'I is not in the alphabet');
      expect(FriendCodes.isValid('jw-7k3p9q'), isFalse);
    });

    test('normalises what people type', () {
      expect(FriendCodes.normalize('JW-7K3P9Q'), 'JW-7K3P9Q');
      expect(FriendCodes.normalize('jw-7k3p9q'), 'JW-7K3P9Q');
      expect(FriendCodes.normalize('  7k3 p9q '), 'JW-7K3P9Q');
      expect(FriendCodes.normalize('JW7K3P9Q'), 'JW-7K3P9Q');
      expect(FriendCodes.normalize('jw 7k3-p9q'), 'JW-7K3P9Q');
    });

    test('maps Crockford look-alikes', () {
      expect(FriendCodes.normalize('JW-OIL234'), 'JW-011234');
      expect(FriendCodes.normalize('oil234'), 'JW-011234');
    });

    test('accepts invite links', () {
      expect(FriendCodes.normalize('https://jadewell.pranta.dev/f/JW-7K3P9Q'), 'JW-7K3P9Q');
      expect(FriendCodes.normalize('Play with me: https://jadewell.pranta.dev/f/jw-7k3p9q?x=1'), 'JW-7K3P9Q');
    });

    test('rejects what cannot be a code', () {
      expect(FriendCodes.normalize(null), isNull);
      expect(FriendCodes.normalize(''), isNull);
      expect(FriendCodes.normalize('JW-7K3P9'), isNull);
      expect(FriendCodes.normalize('JW-7K3P9QQ'), isNull);
      expect(FriendCodes.normalize('JW-7K3P9U'), isNull, reason: 'U is excluded');
      expect(FriendCodes.normalize('JW-7K3P9!'), isNull);
    });

    test('formats partial input while typing', () {
      expect(FriendCodes.formatPartial(''), '');
      expect(FriendCodes.formatPartial('7'), 'JW-7');
      expect(FriendCodes.formatPartial('j'), 'J');
      expect(FriendCodes.formatPartial('jw'), 'JW-');
      expect(FriendCodes.formatPartial('jw-7k'), 'JW-7K');
      expect(FriendCodes.formatPartial('JW-7k3p9q1'), 'JW-7K3P9Q', reason: 'capped at 6');
      expect(FriendCodes.formatPartial('jk'), 'JW-JK');
      expect(FriendCodes.formatPartial('o!u'), 'JW-0', reason: 'O→0, junk and U dropped');
    });

    test('invite link', () {
      expect(FriendCodes.inviteLink('JW-7K3P9Q'), 'https://jadewell.pranta.dev/f/JW-7K3P9Q');
    });
  });

  group('date keys', () {
    test('UTC date', () {
      expect(utcDateKey(DateTime.utc(2026, 11, 6, 23, 59)), '2026-11-06');
    });

    test('ISO weeks, including year boundaries', () {
      expect(isoWeekKey(DateTime.utc(2026, 11, 16)), '2026-W47');
      expect(isoWeekKey(DateTime.utc(2026, 1, 1)), '2026-W01');
      expect(isoWeekKey(DateTime.utc(2027, 1, 1)), '2026-W53');
      expect(isoWeekKey(DateTime.utc(2024, 12, 30)), '2025-W01');
      expect(isoWeekKey(DateTime.utc(2021, 1, 3)), '2020-W53');
    });
  });

  group('JSON', () {
    test('parses a leaderboard page in snake_case', () {
      final page = LeaderboardPage.fromJson(jsonDecode(_dailyJson) as Map<String, dynamic>);
      expect(page.totalPlayers, 143);
      expect(page.layoutId, 'lotus');
      expect(page.entries, hasLength(3));
      final first = page.entries.first;
      expect((first.rank, first.userId, first.displayName, first.avatarColor, first.stars, first.timeMs, first.isMe),
          (1, 'a', 'Mira K.', '#E06A4E', 3, 298000, false));
      expect(page.entries[1].isMe, isFalse, reason: 'is_me defaults to false');
      expect(page.entries[2].avatarColor, isNull);
      expect(page.me!.entry.rank, 27);
      expect(page.me!.entry.isMe, isTrue);
      expect(page.me!.topPercent, 18);
    });

    test('an empty board has no me', () {
      final page = LeaderboardPage.fromJson({'entries': <Object>[], 'me': null, 'total_players': 0});
      expect(page.isEmpty, isTrue);
      expect(page.me, isNull);
    });

    test('parses friends and requests', () {
      final f = Friend.fromJson({
        'user_id': 'u2',
        'display_name': 'Mira K.',
        'username': 'mira_k',
        'avatar_color': '#C2577A',
        'friend_code': 'JW-ABCDEF',
        'since': '2026-11-10T08:00:00Z',
      });
      expect((f.userId, f.player.username, f.player.friendCode), ('u2', 'mira_k', 'JW-ABCDEF'));
      expect(f.since, DateTime.utc(2026, 11, 10, 8));

      final reqs = FriendRequests.fromJson({
        'incoming': [
          {
            'id': 'r1',
            'status': 'pending',
            'created_at': '2026-11-15T12:00:00Z',
            'user': {'user_id': 'u3', 'display_name': 'Kofi A.'},
          },
        ],
        'outgoing': <Object>[],
      });
      expect(reqs.incoming.single.player.displayName, 'Kofi A.');
      expect(reqs.incoming.single.status, FriendRequestStatus.pending);
      expect(reqs.outgoing, isEmpty);
    });
  });

  group('SocialApi over HTTP', () {
    ApiClient client(MockClientHandler handler) => ApiClient(
          baseUrl: 'https://api.test/api/v1',
          identity: _identity,
          tokenProvider: () => 'jwt',
          httpClient: MockClient(handler),
        );

    test('daily leaderboard hits the documented path and parses', () async {
      late http.Request seen;
      final api = SocialApi(client((r) async {
        seen = r;
        return http.Response(_dailyJson, 200);
      }));
      final r = await api.dailyLeaderboard('2026-11-16');
      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/v1/leaderboards/daily/2026-11-16');
      expect(seen.url.queryParameters['limit'], '50');
      expect(seen.headers['Authorization'], 'Bearer jwt');
      expect(r.isSuccess, isTrue);
      expect(r.value!.entries, hasLength(3));
    });

    test('a missing endpoint is a 404 failure, not a crash', () async {
      final api = SocialApi(client((_) async => http.Response('', 404)));
      final r = await api.weeklyLeaderboard('2026-W47');
      expect(r.isSuccess, isFalse);
      expect(r.statusCode, 404);
    });

    test('a malformed body is badResponse', () async {
      final api = SocialApi(client((_) async => http.Response('{"entries": [{"rank": "x"}]}', 200)));
      final r = await api.friendsLeaderboard('2026-11-16');
      expect(r.failure, ApiFailure.badResponse);
    });

    test('transport errors are offline', () async {
      final api = SocialApi(client((_) async => throw http.ClientException('no route')));
      final r = await api.friends();
      expect(r.failure, ApiFailure.offlineOrTransport);
    });

    test('send request posts the canonical code', () async {
      late http.Request seen;
      final api = SocialApi(client((r) async {
        seen = r;
        return http.Response(
          '{"id": "r9", "status": "pending", "user": {"user_id": "u5", "display_name": "Sana"}}',
          201,
        );
      }));
      final r = await api.sendRequest('JW-7K3P9Q');
      expect(seen.url.path, '/api/v1/friends/requests');
      expect(jsonDecode(seen.body), {'friend_code': 'JW-7K3P9Q'});
      expect(r.value!.player.displayName, 'Sana');
    });

    test('accept / decline / cancel / remove paths', () async {
      final seen = <String>[];
      final api = SocialApi(client((r) async {
        seen.add('${r.method} ${r.url.path}');
        if (r.url.path.endsWith('/accept')) {
          return http.Response('{"user_id": "u5", "display_name": "Sana"}', 200);
        }
        return http.Response('', 204);
      }));
      expect((await api.accept('r1')).value!.userId, 'u5');
      expect((await api.decline('r2')).isSuccess, isTrue);
      expect((await api.cancel('r3')).isSuccess, isTrue);
      expect((await api.remove('u9')).isSuccess, isTrue);
      expect(seen, [
        'POST /api/v1/friends/requests/r1/accept',
        'POST /api/v1/friends/requests/r2/decline',
        'DELETE /api/v1/friends/requests/r3',
        'DELETE /api/v1/friends/u9',
      ]);
    });
  });

  group('add-friend errors', () {
    test('map status codes', () {
      expect(addFriendErrorFor(ApiResult.failed(ApiFailure.validation, statusCode: 404, message: 'No user')),
          AddFriendError.notFound);
      expect(addFriendErrorFor(ApiResult.failed(ApiFailure.validation, statusCode: 404)), AddFriendError.unavailable);
      expect(addFriendErrorFor(ApiResult.failed(ApiFailure.validation, statusCode: 409)), AddFriendError.alreadyConnected);
      expect(addFriendErrorFor(ApiResult.failed(ApiFailure.validation, statusCode: 400)), AddFriendError.invalidCode);
      expect(addFriendErrorFor(ApiResult.failed(ApiFailure.timeout)), AddFriendError.offline);
      expect(addFriendErrorFor(ApiResult.failed(ApiFailure.serverUnavailable, statusCode: 503)), AddFriendError.unavailable);
    });

    test('repository rejects non-canonical codes without a request', () async {
      var calls = 0;
      final repo = ApiSocialRepository(SocialApi(ApiClient(
        baseUrl: 'https://api.test/api/v1',
        identity: _identity,
        tokenProvider: () => null,
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{}', 200);
        }),
      )));
      final r = await repo.sendRequest('7k3p9q');
      expect(r.error, AddFriendError.invalidCode);
      expect(calls, 0);
    });
  });
}
