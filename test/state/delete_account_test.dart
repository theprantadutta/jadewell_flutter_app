import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:drift/drift.dart' show Table, TableInfo;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jadewell_flutter_app/data/api/api_client.dart';
import 'package:jadewell_flutter_app/data/api/install_identity.dart';
import 'package:jadewell_flutter_app/data/db/app_database.dart';
import 'package:jadewell_flutter_app/data/db/drift_repositories.dart';
import 'package:jadewell_flutter_app/data/models/settings.dart';
import 'package:jadewell_flutter_app/data/repositories/entitlement_repository.dart';
import 'package:jadewell_flutter_app/platform/auth/auth_service.dart';
import 'package:jadewell_flutter_app/state/app_providers.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/entitlement_providers.dart';
import 'package:jadewell_flutter_app/state/session_controller.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/drift_repositories_test.dart' show result;

/// Firebase stand-in: a guest per sign-in, optionally Apple-linked.
class FakeAuth implements AuthService {
  FakeAuth({this.prepareError});

  final AuthException? prepareError;
  final List<String> calls = [];
  final _changes = StreamController<AuthIdentity?>.broadcast();
  int _n = 1;
  AuthIdentity? _current;

  AuthIdentity _guest() => AuthIdentity(uid: 'guest-${_n++}', isAnonymous: true, providers: const []);

  @override
  AuthIdentity? get current => _current;

  @override
  Stream<AuthIdentity?> get changes => _changes.stream;

  @override
  Future<AuthIdentity> ensureSignedIn() async => _current ??= _guest();

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => 'firebase-${_current?.uid}';

  @override
  Future<void> prepareAccountDeletion() async {
    calls.add('prepare');
    if (prepareError != null) throw prepareError!;
  }

  @override
  Future<AuthIdentity> signOutToGuest() async {
    calls.add('signOutToGuest');
    _current = _guest();
    _changes.add(_current);
    return _current!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late InstallIdentity identity;
  late List<String> requests;

  /// What `DELETE /auth/me` answers.
  late Future<http.Response> Function() deleteResponse;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Jadewell',
      packageName: 'com.pranta.jadewell',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    identity = await InstallIdentity.load();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    requests = [];
    deleteResponse = () async => http.Response('', 204);
  });
  tearDown(() => db.close());

  Future<http.Response> backend(http.Request r) async {
    requests.add('${r.method} ${r.url.path.replaceFirst('/api/v1', '')}');
    if (r.method == 'POST' && r.url.path.endsWith('/auth/firebase')) {
      final token = (jsonDecode(r.body) as Map)['firebase_token'] as String;
      final uid = token.replaceFirst('firebase-', '');
      return http.Response(
        jsonEncode({
          'access_token': 'jwt-$uid',
          'is_new_user': true,
          'user': {
            'id': 'user-$uid',
            'username': 'Player_$uid'.replaceAll('-', '_'),
            'display_name': 'Player $uid',
            'friend_code': 'JW-ABCDEF',
            'avatar_color': '#14897A',
            'auth_provider': 'anonymous',
            'is_anonymous': true,
          },
        }),
        200,
      );
    }
    if (r.method == 'DELETE' && r.url.path.endsWith('/auth/me')) return deleteResponse();
    return http.Response('{"error":"unexpected"}', 400);
  }

  Future<(ProviderContainer, FakeAuth)> start({AuthException? prepareError}) async {
    final prefs = await SharedPreferences.getInstance();
    final auth = FakeAuth(prepareError: prepareError);
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        appConfigProvider.overrideWithValue(const AppConfig(apiBaseUrl: 'https://api.test/api/v1')),
        sharedPreferencesProvider.overrideWithValue(prefs),
        installIdentityProvider.overrideWithValue(identity),
        authServiceProvider.overrideWithValue(auth),
        apiClientProvider.overrideWith((ref) {
          final store = ref.watch(sessionStoreProvider);
          return ApiClient(
            baseUrl: 'https://api.test/api/v1',
            identity: identity,
            tokenProvider: () => store.token,
            httpClient: MockClient(backend),
          );
        }),
        progressRepositoryProvider.overrideWithValue(DriftProgressRepository(db)),
        entitlementRepositoryProvider.overrideWithValue(DriftEntitlementRepository(db)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(sessionProvider.future);
    // build() starts the first exchange on the next event-loop turn; join it.
    await Future<void>.delayed(Duration.zero);
    await container.read(sessionProvider.notifier).ensureBackendSession();
    expect(container.read(sessionStoreProvider).token, 'jwt-guest-1');
    requests.clear();
    return (container, auth);
  }

  /// One cleared board, a daily clear, a saved game, Remove ads and a dark theme.
  Future<void> seed() async {
    final progress = DriftProgressRepository(db);
    await progress.recordResult(result());
    await progress.recordResult(result(layoutId: 'lotus', dailyDate: '2026-11-16', moveLog: 'AQ'));
    await progress.saveGame('crab', stateJson: const {'x': 1}, elapsedMs: 1000, fractionCleared: 0.2);
    await DriftEntitlementRepository(db).grantRemoveAds(source: 'play');
    await DriftSettingsRepository(db).write(const AppSettings(theme: ThemePreference.dark, onboardingDone: true));
  }

  Future<int> count<T extends Table, R>(TableInfo<T, R> table) async => (await db.select(table).get()).length;

  Future<Map<String, int>> counts() async => {
        'progress': await count(db.layoutProgressTable),
        'saved': await count(db.savedGameTable),
        'results': await count(db.gameResultsTable),
        'daily': await count(db.dailyEntriesTable),
        'streak': await count(db.streakTable),
        'outbox': await count(db.syncOutboxTable),
        'entitlements': await count(db.entitlementsTable),
      };

  test('success: server first, then the device is wiped and a fresh guest starts', () async {
    final (container, auth) = await start();
    await seed();
    final before = await counts();
    expect(before.values.every((n) => n > 0), isTrue, reason: '$before');

    final outcome = await container.read(sessionProvider.notifier).deleteAccount();

    expect(outcome, DeleteAccountOutcome.deleted);
    expect(requests.first, 'DELETE /auth/me');
    expect(requests.skip(1), everyElement('POST /auth/firebase'), reason: 'only the new guest exchange follows');
    expect(auth.calls, ['prepare', 'signOutToGuest']);
    expect((await counts()).values, everyElement(0));
    expect((await DriftEntitlementRepository(db).read()).removeAds, isFalse);
    // Device settings survive.
    final settings = await DriftSettingsRepository(db).read();
    expect(settings.theme, ThemePreference.dark);
    expect(settings.onboardingDone, isTrue);
    // The new guest has its own backend session.
    final session = container.read(sessionProvider).value!;
    expect(session.identity.uid, 'guest-2');
    expect(session.user!.id, 'user-guest-2');
    expect(container.read(sessionStoreProvider).token, 'jwt-guest-2');
  });

  test('a 404 "User not found" (already deleted) still wipes the device', () async {
    final (container, _) = await start();
    await seed();
    deleteResponse = () async => http.Response('{"error":"User not found"}', 404);

    expect(await container.read(sessionProvider.notifier).deleteAccount(), DeleteAccountOutcome.deleted);
    expect((await counts()).values, everyElement(0));
  });

  group('failures change nothing', () {
    Future<void> expectUntouched(ProviderContainer container, FakeAuth auth, Map<String, int> before) async {
      expect(await counts(), before);
      expect((await DriftEntitlementRepository(db).read()).removeAds, isTrue);
      expect(auth.calls, isNot(contains('signOutToGuest')));
      expect(container.read(sessionProvider).value!.identity.uid, 'guest-1');
      expect(container.read(sessionStoreProvider).token, 'jwt-guest-1');
    }

    test('server error', () async {
      final (container, auth) = await start();
      await seed();
      final before = await counts();
      deleteResponse = () async => http.Response('{"error":"boom"}', 500);

      expect(await container.read(sessionProvider.notifier).deleteAccount(), DeleteAccountOutcome.failed);
      await expectUntouched(container, auth, before);
    });

    test('offline', () async {
      final (container, auth) = await start();
      await seed();
      final before = await counts();
      deleteResponse = () async => throw const SocketException('no route');

      expect(await container.read(sessionProvider.notifier).deleteAccount(), DeleteAccountOutcome.offline);
      await expectUntouched(container, auth, before);
    });

    test('an unrelated 404 (endpoint not deployed) is a failure', () async {
      final (container, auth) = await start();
      await seed();
      final before = await counts();
      deleteResponse = () async => http.Response('', 404);

      expect(await container.read(sessionProvider.notifier).deleteAccount(), DeleteAccountOutcome.failed);
      await expectUntouched(container, auth, before);
    });

    test('backing out of the Apple re-authentication never calls the server', () async {
      final (container, auth) = await start(prepareError: const AuthException(AuthErrorKind.cancelled));
      await seed();
      final before = await counts();

      expect(await container.read(sessionProvider.notifier).deleteAccount(), DeleteAccountOutcome.cancelled);
      expect(requests, isEmpty);
      await expectUntouched(container, auth, before);
    });
  });
}
