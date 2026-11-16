import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jadewell_flutter_app/data/api/api_result.dart';
import 'package:jadewell_flutter_app/data/api/auth_api.dart';
import 'package:jadewell_flutter_app/data/repositories/social_repository.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/platform/audio/audio_service.dart';
import 'package:jadewell_flutter_app/platform/auth/auth_service.dart';
import 'package:jadewell_flutter_app/platform/haptics/haptic_service.dart';
import 'package:jadewell_flutter_app/state/session_controller.dart';
import 'package:jadewell_flutter_app/ui/l10n/generated/app_localizations.dart';
import 'package:jadewell_flutter_app/ui/router.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui/material_ui.dart' as material_ui show GlobalMaterialLocalizations;

/// Pumps [screen] inside the Jadewell theme, localizations and a GoRouter
/// whose other routes render their path as text (so navigation is visible).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 844),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final router = GoRouter(
    initialLocation: '/test',
    routes: [
      GoRoute(path: '/test', builder: (_, _) => screen),
      for (final p in [
        AppRoutes.home,
        AppRoutes.account,
        AppRoutes.friends,
        AppRoutes.store,
        AppRoutes.dailyPlay,
        AppRoutes.settings,
      ])
        GoRoute(path: p, builder: (_, _) => Scaffold(body: Center(child: Text('route:$p')))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      retry: (_, _) => null,
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildJwThemeData(brightness),
        localizationsDelegates: [
          AppLocalizations.delegate,
          ...material_ui.GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
  await tester.pump();
}

AppLocalizations l10n(WidgetTester tester) => AppLocalizations.of(tester.element(find.byType(Scaffold).first));

// ---- fakes ----

class RecordingAnalytics implements AnalyticsService {
  final List<(String, Map<String, Object>)> events = [];

  @override
  Future<void> log(String event, [Map<String, Object> params = const {}]) async => events.add((event, params));

  @override
  Future<void> screen(String name) async {}
}

class RecordingAudio extends NoOpAudio {
  RecordingAudio();
  bool? music;
  bool? sfx;

  @override
  void setMusicEnabled(bool enabled) => music = enabled;

  @override
  void setSfxEnabled(bool enabled) => sfx = enabled;
}

class RecordingHaptics extends NoOpHaptics {
  RecordingHaptics();
  bool? enabled;

  @override
  void setEnabled(bool enabled) => this.enabled = enabled;
}

const guestIdentity = AuthIdentity(uid: 'u1', isAnonymous: true, providers: []);
const googleIdentity =
    AuthIdentity(uid: 'u1', isAnonymous: false, providers: ['google.com'], email: 'mei@example.com');

const testUser = BackendUser(
  id: 'b1',
  username: 'jade_otter_42',
  displayName: 'Jade Otter',
  friendCode: 'JW-7K3P9Q',
  avatarColor: '#2E8B57',
  authProvider: 'anonymous',
  isAnonymous: true,
);

/// A session controller that never touches Firebase or the network.
class FakeSession extends SessionController {
  FakeSession(this.initial, {this.linkError});

  final BackendSession initial;
  final AuthException? linkError;
  final List<String> calls = [];

  @override
  Future<BackendSession> build() async => initial;

  @override
  Future<void> ensureBackendSession({bool force = false}) async => calls.add('ensure');

  Future<void> _maybeFail(String name) async {
    calls.add(name);
    if (linkError != null) throw linkError!;
  }

  @override
  Future<void> linkGoogle() => _maybeFail('linkGoogle');
  @override
  Future<void> linkApple() => _maybeFail('linkApple');
  @override
  Future<void> linkEmail(String email, String password) => _maybeFail('linkEmail');
  @override
  Future<void> signInWithGoogle() async => calls.add('signInWithGoogle');
  @override
  Future<void> signInWithApple() async => calls.add('signInWithApple');
  @override
  Future<void> signInWithEmail(String email, String password) async => calls.add('signInWithEmail');
  @override
  Future<void> signOut() async => calls.add('signOut');
}

/// In-memory social backend; a non-null [failWith] makes reads fail.
class FakeSocialRepository implements SocialRepository {
  FakeSocialRepository({
    this.pages = const {},
    this.friendList = const [],
    this.incoming = const [],
    this.outgoing = const [],
    this.failWith,
    this.failStatus,
  });

  final Map<LeaderboardKind, LeaderboardPage> pages;
  List<Friend> friendList;
  List<FriendRequest> incoming;
  List<FriendRequest> outgoing;
  ApiFailure? failWith;
  int? failStatus;
  final List<String> sent = [];

  ApiResult<T> _fail<T>() => ApiResult.failed(failWith!, statusCode: failStatus);

  @override
  Future<ApiResult<LeaderboardPage>> leaderboard(LeaderboardKind kind, DateTime utcNow) async =>
      failWith != null ? _fail() : ApiResult.success(pages[kind] ?? const LeaderboardPage(entries: []));

  @override
  Future<ApiResult<List<Friend>>> friends() async => failWith != null ? _fail() : ApiResult.success(friendList);

  @override
  Future<ApiResult<FriendRequests>> requests() async => failWith != null
      ? _fail()
      : ApiResult.success(FriendRequests(incoming: incoming, outgoing: outgoing));

  @override
  Future<({FriendRequest? request, AddFriendError? error})> sendRequest(String friendCode) async {
    sent.add(friendCode);
    if (friendCode == 'JW-NNNNNN') return (request: null, error: AddFriendError.notFound);
    final r = FriendRequest(id: 'r-$friendCode', player: PlayerSummary(userId: 'x', displayName: 'Mira K.'));
    outgoing = [...outgoing, r];
    return (request: r, error: null);
  }

  @override
  Future<ApiResult<Friend>> accept(String requestId) async {
    final r = incoming.firstWhere((x) => x.id == requestId);
    incoming = [for (final x in incoming) if (x.id != requestId) x];
    final f = Friend(player: r.player);
    friendList = [...friendList, f];
    return ApiResult.success(f);
  }

  @override
  Future<ApiResult<void>> decline(String requestId) async {
    incoming = [for (final x in incoming) if (x.id != requestId) x];
    return ApiResult<void>.success(null);
  }

  @override
  Future<ApiResult<void>> cancel(String requestId) async {
    outgoing = [for (final x in outgoing) if (x.id != requestId) x];
    return ApiResult<void>.success(null);
  }

  @override
  Future<ApiResult<void>> remove(String userId) async {
    friendList = [for (final x in friendList) if (x.userId != userId) x];
    return ApiResult<void>.success(null);
  }
}
