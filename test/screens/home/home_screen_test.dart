import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/platform/ads/ad_service.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/home/home_screen.dart';
import 'package:jadewell_flutter_app/ui/screens/home/layout_card_parts.dart';
import 'package:material_ui/material_ui.dart';

import '../../ui/golden_helpers.dart' show loadJwFonts;
import 'screen_harness.dart';

GameResult _clear(String id, int ms, int stars) => GameResult(
      layoutId: id,
      seed: 1,
      generatorVersion: 1,
      outcome: GameOutcome.cleared,
      timeMs: ms,
      stars: stars,
      hintsUsed: 0,
      undos: 0,
      shufflesUsed: 0,
      tilesMatched: 4,
      longestStreak: 1,
      playedAt: DateTime(2026, 11, 15),
    );

Future<(RecordingAnalytics, InstantAdService, MemoryProgressRepository)> _pump(
  WidgetTester tester, {
  required Future<void> Function(MemoryProgressRepository) seed,
  Size size = const Size(390, 844),
}) async {
  final repo = MemoryProgressRepository();
  await seed(repo);
  final analytics = RecordingAnalytics();
  final ads = InstantAdService();
  await pumpScreen(
    tester,
    initial: '/home',
    size: size,
    screens: {'/home': (_) => const HomeScreen()},
    overrides: [
      catalogueRepositoryProvider.overrideWithValue(FakeCatalogueRepository(testCatalogue())),
      progressRepositoryProvider.overrideWithValue(repo),
      dailyProvider.overrideWith(
        (ref) => Stream.value(const DailyStatus(date: '2026-11-15', layoutId: 'lotus', seed: 7)),
      ),
      analyticsProvider.overrideWithValue(analytics),
      adServiceProvider.overrideWithValue(ads),
    ],
  );
  await tester.pumpAndSettle();
  return (analytics, ads, repo);
}

Future<void> _scrollTo(WidgetTester tester, Finder f) =>
    tester.scrollUntilVisible(f, 200, scrollable: find.byType(Scrollable).first);

void main() {
  setUpAll(loadJwFonts);

  testWidgets('cleared, resume, new and locked card states', (tester) async {
    await _pump(
      tester,
      seed: (repo) async {
        await repo.recordResult(_clear('pyramid', 228000, 2));
        await repo.saveGame('turtle', stateJson: const {}, elapsedMs: 1000, fractionCleared: 0.4);
      },
    );

    // Star chip: stars earned of 3 per chapter layout.
    expect(find.text('2/24'), findsOneWidget);
    expect(find.text('Ready for a board?'), findsOneWidget);
    expect(find.text('Lotus'), findsOneWidget);
    expect(find.text('Daily · Sun 15 Nov'), findsOneWidget);
    // Explore collections: one card per chapter.
    expect(find.text('Explore collections'), findsOneWidget);
    expect(find.text('1/4'), findsOneWidget);

    // Pyramid: best time with a check and two of three stars.
    final pyramid = find.byKey(const ValueKey('layout-card-pyramid'));
    expect(find.descendant(of: pyramid, matching: find.text('Best')), findsOneWidget);
    expect(find.descendant(of: pyramid, matching: find.text('3:48')), findsOneWidget);
    expect(tester.widget<StarRow>(find.descendant(of: pyramid, matching: find.byType(StarRow))).earned, 2);

    final turtle = find.byKey(const ValueKey('layout-card-turtle'));
    expect(find.descendant(of: turtle, matching: find.byType(MiniTrack)), findsOneWidget);
    expect(find.descendant(of: turtle, matching: find.text('40%')), findsOneWidget);

    final bridge = find.byKey(const ValueKey('layout-card-bridge'));
    await _scrollTo(tester, bridge);
    expect(find.descendant(of: bridge, matching: find.text('NEW')), findsOneWidget);

    // Creatures need 2 Classics clears; 1 cleared → 1 more.
    final crab = find.byKey(const ValueKey('layout-card-crab'));
    await _scrollTo(tester, crab);
    expect(find.descendant(of: crab, matching: find.text('Clear 1 more Classic')), findsOneWidget);

    // Wonders is a collapsed locked row.
    await _scrollTo(tester, find.text('2 layouts · unlocks at 8 clears'));
    expect(find.byKey(const ValueKey('locked-chapter-wonders')), findsOneWidget);
  });

  testWidgets('first run shows the start-here card', (tester) async {
    await _pump(tester, seed: (_) async {});
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Let’s play your first board'), findsOneWidget);
    expect(find.text('0/24'), findsOneWidget);
    expect(find.text('START HERE'), findsOneWidget);
    expect(find.text('Play first board'), findsOneWidget);
  });

  testWidgets('layout lock within an open chapter names the first layout', (tester) async {
    await _pump(
      tester,
      seed: (repo) async {
        await repo.recordResult(_clear('pyramid', 200000, 3));
        await repo.recordResult(_clear('turtle', 300000, 1));
      },
    );
    final dragon = find.byKey(const ValueKey('layout-card-dragon'));
    await _scrollTo(tester, dragon);
    expect(find.descendant(of: dragon, matching: find.text('Clear Crab first')), findsOneWidget);
    final crab = find.byKey(const ValueKey('layout-card-crab'));
    expect(find.descendant(of: crab, matching: find.text('NEW')), findsOneWidget);
  });

  testWidgets('open card pushes the game route', (tester) async {
    await _pump(tester, seed: (repo) => repo.recordResult(_clear('pyramid', 1000, 1)));
    await tester.tap(find.byKey(const ValueKey('layout-card-turtle')));
    await tester.pumpAndSettle();
    expect(find.text('route:/game/turtle'), findsOneWidget);
  });

  testWidgets('locked chapter row unlocks its first layout with a rewarded ad', (tester) async {
    final (analytics, ads, repo) = await _pump(tester, seed: (_) async {});
    final spiral = find.byKey(const ValueKey('locked-chapter-wonders'));
    await _scrollTo(tester, spiral);
    await tester.tap(spiral);
    await tester.pumpAndSettle();
    expect(find.text('Unlock Spiral now?'), findsOneWidget);
    await tester.tap(find.text('Watch video'));
    await tester.pumpAndSettle();

    expect(ads.shown, [RewardedPlacement.unlockLayout]);
    expect(analytics.events.where((e) => e.$1 == AnalyticsEvents.layoutUnlockAd).single.$2, {'layout_id': 'spiral'});
    final progress = await repo.watchAll().first;
    expect(progress['spiral']!.adUnlocked, isTrue);
    // The chapter now shows cards; Spiral is open and new.
    final card = find.byKey(const ValueKey('layout-card-spiral'));
    await _scrollTo(tester, card);
    expect(find.descendant(of: card, matching: find.text('NEW')), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('tablet width uses three columns', (tester) async {
    await _pump(tester, seed: (_) async {}, size: const Size(800, 1280));
    final a = tester.getTopLeft(find.byKey(const ValueKey('layout-card-pyramid')));
    final c = tester.getTopLeft(find.byKey(const ValueKey('layout-card-fortress')));
    expect(c.dy, a.dy);
  });

  testWidgets('a collection card scrolls to its chapter', (tester) async {
    await _pump(tester, seed: (_) async {});
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, 0);
    await tester.tap(find.bySemanticsLabel(RegExp(r'^Wonders, 0 of 2 cleared')));
    await tester.pumpAndSettle();
    // Scrolled as far as it goes towards Wonders, which is now fully visible.
    expect(scrollable.position.pixels, greaterThan(0));
    final row = tester.getRect(find.byKey(const ValueKey('locked-chapter-wonders')));
    expect(row.bottom, lessThanOrEqualTo(844));
  });
}
