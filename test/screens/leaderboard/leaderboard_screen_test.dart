import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/api/api_result.dart';
import 'package:jadewell_flutter_app/data/repositories/social_repository.dart';
import 'package:jadewell_flutter_app/state/session_controller.dart';
import 'package:jadewell_flutter_app/state/social_providers.dart';
import 'package:jadewell_flutter_app/ui/router.dart';
import 'package:jadewell_flutter_app/ui/screens/leaderboard/leaderboard_screen.dart';
import 'package:jadewell_flutter_app/ui/screens/leaderboard/leaderboard_widgets.dart';
import 'package:material_ui/material_ui.dart' show Brightness, Size;

import '../../ui/golden_helpers.dart' show loadJwFonts;
import '../meta_checks.dart';
import '../settings/harness.dart';

LeaderboardEntry _e(int rank, String name, int stars, int timeMs, {bool me = false}) => LeaderboardEntry(
      rank: rank,
      userId: 'u$rank',
      displayName: name,
      avatarColor: '#2E8B57',
      stars: stars,
      timeMs: timeMs,
      isMe: me,
    );

final _daily = LeaderboardPage(
  totalPlayers: 143,
  layoutId: 'lotus',
  entries: [
    _e(1, 'Mira K.', 3, 298000),
    _e(2, 'tilewhisper', 3, 311000),
    _e(3, 'Kofi A.', 3, 326000),
    _e(4, 'Ines R.', 2, 340000),
    _e(5, 'lotuslover', 2, 352000),
  ],
  me: LeaderboardMe(entry: _e(27, 'Jade Otter', 2, 462000, me: true), topPercent: 18),
);

void main() {
  setUpAll(loadJwFonts);

  Future<void> pump(
    WidgetTester tester,
    FakeSocialRepository repo, {
    Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
  }) async {
    await pumpScreen(
      tester,
      const LeaderboardScreen(),
      brightness: brightness,
      size: size,
      overrides: [
        sessionProvider.overrideWith(() => FakeSession(const BackendSession(identity: guestIdentity, user: testUser))),
        socialRepositoryProvider.overrideWithValue(repo),
        socialClockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 16, 9)),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('podium, rows with stars and time, and the pinned You row', (tester) async {
    await pump(tester, FakeSocialRepository(pages: {LeaderboardKind.daily: _daily}));
    expect(find.text('Leaderboard'), findsOneWidget);
    expect(find.byType(Podium), findsOneWidget);
    expect(find.text('Mira K.'), findsOneWidget);
    expect(find.text('4:58'), findsOneWidget);
    expect(find.text('Ines R.'), findsOneWidget);
    expect(find.text('5:40'), findsOneWidget);
    expect(find.byType(StarsRow), findsNWidgets(6));
    expect(find.text('Top 18% today'), findsOneWidget);
    expect(find.text('27'), findsOneWidget);
    expect(find.text('7:42'), findsOneWidget);
  });

  testWidgets('no entries shows the empty state with Play today', (tester) async {
    await pump(tester, FakeSocialRepository());
    expect(find.text('No times yet today'), findsOneWidget);
    expect(find.byType(EmptyPodium), findsOneWidget);
    await tester.tap(find.text("Play today's board"));
    await tester.pumpAndSettle();
    expect(find.text('route:${AppRoutes.dailyPlay}'), findsOneWidget);
  });

  testWidgets('a missing endpoint (404) shows the empty state, not an error', (tester) async {
    await pump(tester, FakeSocialRepository(failWith: ApiFailure.validation, failStatus: 404));
    expect(find.text('No times yet today'), findsOneWidget);
  });

  testWidgets('offline shows a retry', (tester) async {
    final repo = FakeSocialRepository(failWith: ApiFailure.offlineOrTransport, pages: {LeaderboardKind.daily: _daily});
    await pump(tester, repo);
    expect(find.text("You're offline"), findsOneWidget);
    repo.failWith = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Mira K.'), findsOneWidget);
  });

  testWidgets('switching tabs; Friends with no friends offers Add friends', (tester) async {
    await pump(
      tester,
      FakeSocialRepository(pages: {
        LeaderboardKind.daily: _daily,
        LeaderboardKind.friends: LeaderboardPage(entries: [_e(1, 'Jade Otter', 2, 462000, me: true)]),
      }),
    );
    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();
    expect(find.text('No results yet this week'), findsOneWidget);

    await tester.tap(find.text('Friends'));
    await tester.pumpAndSettle();
    expect(find.text('No friends here yet'), findsOneWidget);
    await tester.tap(find.text('Add friends'));
    await tester.pumpAndSettle();
    expect(find.text('route:${AppRoutes.friends}'), findsOneWidget);
  });

  testWidgets('keeps the last page when a refresh fails', (tester) async {
    final repo = FakeSocialRepository(pages: {LeaderboardKind.daily: _daily});
    await pump(tester, repo, brightness: Brightness.dark);
    repo.failWith = ApiFailure.timeout;
    await tester.tap(find.text('This week'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Today'));
    await tester.pumpAndSettle();
    expect(find.text('Mira K.'), findsOneWidget, reason: 'cached in memory');
  });

  final full = LeaderboardPage(
    totalPlayers: 143,
    layoutId: 'lotus',
    entries: [
      _e(1, 'Mira K.', 3, 298000),
      _e(2, 'tilewhisper', 3, 311000),
      _e(3, 'Kofi A.', 3, 326000),
      _e(4, 'Ines R.', 2, 340000),
      _e(5, 'lotuslover', 2, 352000),
      _e(6, 'Theo M.', 2, 363000),
      _e(7, 'Sana', 1, 377000),
      _e(8, 'June P.', 1, 389000),
      _e(9, 'Rahul D. with a very long display name', 1, 3604000),
    ],
    me: LeaderboardMe(entry: _e(27, 'Jade Otter', 2, 462000, me: true), topPercent: 18),
  );
  for (final size in layoutSizes.entries) {
    for (final scale in textScales) {
      testWidgets('leaderboard layout · ${size.key} · text ${scale}x: no overflow', (tester) async {
        setTextScale(tester, scale);
        await pump(tester, FakeSocialRepository(pages: {LeaderboardKind.daily: full}), size: size.value);
        await expectNoOverflow(tester);
        await pump(tester, FakeSocialRepository(), size: size.value);
        await expectNoOverflow(tester);
      });
    }
  }
  for (final b in Brightness.values) {
    testWidgets('leaderboard shots ${b.name}', skip: !shotsEnabled, (tester) async {
      await pump(tester, FakeSocialRepository(pages: {LeaderboardKind.daily: full}), brightness: b);
      await maybeShot(tester, 'leaderboard_${b.name}');
      await pump(tester, FakeSocialRepository(), brightness: b);
      await maybeShot(tester, 'empty_leaderboard_${b.name}');
    });
  }
}
