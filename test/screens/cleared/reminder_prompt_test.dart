import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/repositories/asset_catalogue_repository.dart';
import 'package:jadewell_flutter_app/data/repositories/repositories.dart';
import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:jadewell_flutter_app/platform/store_listing/store_listing_service.dart';
import 'package:jadewell_flutter_app/state/app_providers.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/game/game_providers.dart';
import 'package:jadewell_flutter_app/state/game/game_view_state.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/state/reminder_controller.dart';
import 'package:jadewell_flutter_app/state/store_listing_controller.dart';
import 'package:jadewell_flutter_app/ui/screens/cleared/cleared_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/fake_notifications.dart';
import '../../ui/golden_helpers.dart' show loadJwFonts;
import '../meta_checks.dart';
import '../settings/harness.dart';

/// Serves `assets/` from disk so the real catalogue loads.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());
}

const _result = ClearedResult(
  layoutId: 'turtle',
  layoutName: 'Turtle',
  chapterId: 'c1',
  chapterName: 'Garden',
  tileCount: 144,
  isDaily: false,
  stats: ClearStats(
    elapsedMs: 300000,
    hintsUsed: 0,
    shufflesUsed: 0,
    rewardedShuffles: 0,
    undos: 0,
    longestStreak: 4,
    tilesMatched: 144,
    parMs: 420000,
    stars: 3,
  ),
  stars: 3,
  isNewBest: true,
  previousBestMs: null,
  firstClear: true,
);

class _Cleared extends LastClearedController {
  @override
  ClearedResult? build() => _result;
}

/// A review prompter that always asks (or never does).
class _Review extends ReviewPrompter {
  _Review(this.asks, SharedPreferences prefs)
      : super(store: const NoOpStoreListing(), prefs: () => prefs, stats: () async => const PlayerStats());

  final bool asks;
  int calls = 0;

  @override
  Future<bool> maybeAskAfterClear({required int stars}) async {
    calls++;
    return asks;
  }
}

class _Stats implements StatsRepository {
  _Stats(this.stats);

  final PlayerStats stats;

  @override
  Stream<PlayerStats> watch() => Stream.value(stats);
}

void main() {
  setUpAll(loadJwFonts);

  late SharedPreferences prefs;
  late FakeNotifications notifications;
  late RecordingAnalytics analytics;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    notifications = FakeNotifications();
    analytics = RecordingAnalytics();
  });

  Future<_Review> pump(WidgetTester tester, {bool reviewAsks = false, int boardsCleared = 1, Size size = const Size(390, 844)}) async {
    final review = _Review(reviewAsks, prefs);
    await pumpScreen(
      tester,
      const ClearedScreen(layoutId: 'turtle'),
      size: size,
      overrides: [
        catalogueRepositoryProvider.overrideWithValue(AssetCatalogueRepository(bundle: _DiskBundle())),
        lastClearedProvider.overrideWith(_Cleared.new),
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(notifications),
        analyticsProvider.overrideWithValue(analytics),
        reviewPrompterProvider.overrideWithValue(review),
        statsRepositoryProvider.overrideWithValue(_Stats(PlayerStats(gamesPlayed: boardsCleared, boardsCleared: boardsCleared))),
      ],
    );
    return review;
  }

  /// Runs the cleared beat sheet to its end plus the 400 ms pause.
  Future<void> finishBeats(WidgetTester tester) async {
    for (var t = 0; t < 5500; t += 50) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  const title = 'Want a daily reminder?';

  testWidgets('after the first clear: the soft ask, and the head-start offer waits for another board', (tester) async {
    await pump(tester);
    await finishBeats(tester);
    expect(find.text(title), findsOneWidget);
    expect(find.text('Head start'), findsNothing);

    await tester.tap(find.text('Not now'));
    await finishBeats(tester);
    expect(find.text(title), findsNothing);
    expect(find.text('Head start'), findsNothing); // not stacked on the ask
    expect(notifications.requests, 0);
    expect(prefs.getBool(ReminderController.decidedKey), isTrue);
    expect(analytics.events.where((e) => e.$1 == 'reminder_prompt').single.$2, {'result': 'declined', 'source': 'cleared'});
  });

  testWidgets('Yes shows the OS dialog and confirms', (tester) async {
    await pump(tester);
    await finishBeats(tester);
    await tester.tap(find.text('Yes, remind me'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(notifications.requests, 1);
    expect(find.text('Daily reminder is on'), findsOneWidget);
    await finishBeats(tester);
  });

  testWidgets('asked once: the next clear gets the head-start offer instead', (tester) async {
    await prefs.setBool(ReminderController.decidedKey, true);
    await pump(tester, boardsCleared: 2);
    await finishBeats(tester);
    expect(find.text(title), findsNothing);
    expect(find.text('Head start'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await finishBeats(tester);
  });

  testWidgets('never stacked with the review sheet', (tester) async {
    final review = await pump(tester, reviewAsks: true);
    await finishBeats(tester);
    expect(review.calls, 1);
    expect(find.text(title), findsNothing);
    expect(prefs.getBool(ReminderController.decidedKey), isNull); // still to ask on a later clear
  });

  testWidgets('never after an interstitial', (tester) async {
    await pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(ClearedScreen)));
    container.read(clearInterstitialShownProvider.notifier).set(true);
    await finishBeats(tester);
    expect(find.text(title), findsNothing);
  });

  testWidgets('not after the third clear', (tester) async {
    await pump(tester, boardsCleared: 3);
    await finishBeats(tester);
    expect(find.text(title), findsNothing);
    expect(find.text('Head start'), findsOneWidget);
    await tester.tap(find.text('Skip'));
    await finishBeats(tester);
  });

  for (final size in layoutSizes.entries) {
    for (final scale in textScales) {
      testWidgets('reminder sheet · ${size.key} · text ${scale}x: no overflow', (tester) async {
        setTextScale(tester, scale);
        await pump(tester, size: size.value);
        await finishBeats(tester);
        expect(find.text(title), findsOneWidget);
        await expectNoOverflow(tester);
        await tester.tap(find.text('Not now'));
        await finishBeats(tester);
      });
    }
  }
}
