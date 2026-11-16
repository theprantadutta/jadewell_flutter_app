import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/catalogue.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:jadewell_flutter_app/platform/ads/ad_service.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/game/game_clock.dart';
import 'package:jadewell_flutter_app/state/game/game_controller.dart';
import 'package:jadewell_flutter_app/state/game/game_launch.dart';
import 'package:jadewell_flutter_app/state/game/game_providers.dart';
import 'package:jadewell_flutter_app/state/game/game_view_state.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';

class RecordingAnalytics implements AnalyticsService {
  final List<(String, Map<String, Object>)> events = [];

  List<Map<String, Object>> named(String name) => [
    for (final e in events)
      if (e.$1 == name) e.$2,
  ];

  @override
  Future<void> log(String event, [Map<String, Object> params = const {}]) async => events.add((event, params));

  @override
  Future<void> screen(String name) async {}
}

class TestAds implements AdService {
  bool reward = true;
  int rewardedCalls = 0;
  final List<RewardedPlacement> placements = [];
  int clearedCalls = 0;

  @override
  bool adsRemoved = false;

  @override
  Future<void> init() async {}
  @override
  void setAdsRemoved(bool removed) {}
  @override
  bool get privacyOptionsRequired => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  void onBoardStarted() {}
  @override
  bool isRewardedReady(RewardedPlacement placement) => true;

  @override
  Future<bool> showRewarded(RewardedPlacement placement) async {
    rewardedCalls++;
    placements.add(placement);
    return reward;
  }

  @override
  Future<bool> showRewardedInterstitial(RewardedInterstitialPlacement placement) async => reward;

  @override
  Future<bool> onBoardCleared({required bool isDaily}) async {
    clearedCalls++;
    return false;
  }
}

LayoutInfo info(Layout layout, {String chapter = 'classics', int parMs = 60000}) => LayoutInfo(
  id: layout.id,
  name: layout.id,
  chapterId: chapter,
  order: 1,
  difficulty: 'easy',
  parMs: parMs,
  layout: layout,
);

/// Two tiles side by side: one move clears it.
final pairLayout = Layout.fromPositions('pair', const [Position(0, 0, 0), Position(2, 0, 0)]);

/// Two stacks of two. With [deadlockFaces] neither top matches: deadlock.
final stacksLayout = Layout.fromPositions('stacks', const [
  Position(0, 0, 0),
  Position(4, 0, 0),
  Position(0, 0, 1),
  Position(4, 0, 1),
]);

/// Canonical order: 0 = bottom-left, 1 = bottom-right, 2 = top-left, 3 = top-right.
/// Tops show faces 0 and 1 (no match); each matches the bottom of the other stack.
final deadlockFaces = Int8List.fromList([1, 0, 0, 1]);

final turtleLayout = Layout.parse(File('assets/layouts/turtle.json').readAsStringSync());

GameState stateWithFaces(Layout layout, Int8List faces, {int seed = 1}) => GameState(
  layout: layout,
  seed: seed,
  options: DealerOptions.production,
  faces: faces,
  removed: TileSet.empty(layout.length),
  selected: null,
  history: const [],
  moveLog: const [],
  hintsUsed: 0,
  freeHintsLeft: kFreeHintsPerBoard,
  shufflesUsed: 0,
  freeShufflesLeft: kFreeShufflesPerBoard,
  rewardedShuffles: 0,
  shuffleCount: 0,
  undos: 0,
  currentStreak: 0,
  longestStreak: 0,
  lastElapsedMs: 0,
  parMs: 60000,
);

class Harness {
  Harness({this.daily}) {
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        catalogueProvider.overrideWith(
          (ref) async => Catalogue(
            chapters: [
              ChapterInfo(
                id: 'classics',
                name: 'Classics',
                order: 1,
                unlock: const UnlockAlways(),
                layoutIds: const ['pair', 'stacks', 'turtle'],
              ),
            ],
            layouts: {
              'pair': info(pairLayout, parMs: 10000),
              'stacks': info(stacksLayout),
              'turtle': info(turtleLayout, parMs: 360000),
            },
            dailyPool: const ['pair'],
          ),
        ),
        if (daily != null) dailyProvider.overrideWith((ref) => Stream.value(daily!)),
        progressRepositoryProvider.overrideWithValue(repo),
        analyticsProvider.overrideWithValue(analytics),
        adServiceProvider.overrideWithValue(ads),
        gameClockFactoryProvider.overrideWithValue(() => clock),
        gameSeedSourceProvider.overrideWithValue(() => 42),
        gameDealerProvider.overrideWithValue((layout, seed, parMs) async => GameState.newGame(layout, seed, parMs: parMs)),
      ],
    );
  }

  final DailyStatus? daily;
  late final ProviderContainer container;
  final repo = MemoryProgressRepository();
  final analytics = RecordingAnalytics();
  final ads = TestAds();
  final clock = FakeGameClock();

  Future<GameController> open(GameLaunch launch) async {
    container.listen(gameControllerProvider(launch), (_, _) {});
    final c = container.read(gameControllerProvider(launch).notifier);
    for (var i = 0; i < 100 && container.read(gameControllerProvider(launch)).phase == GamePhase.loading; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    return c;
  }

  GameViewState state(GameLaunch launch) => container.read(gameControllerProvider(launch));

  void dispose() => container.dispose();
}

/// Taps the first available matching pair.
void playMove(GameController c, GameViewState s) {
  final (a, b) = s.game!.availableMoves.first;
  c
    ..tap(a)
    ..tap(b);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loading', () {
    test('deals a new board, starts the clock and logs layout_start', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('turtle');
      await h.open(launch);
      final s = h.state(launch);
      expect(s.phase, GamePhase.playing);
      expect(s.game!.seed, 42);
      expect(s.tilesLeft, 144);
      expect(s.chapterName, 'Classics');
      expect(s.resumed, isFalse);
      expect(h.clock.isRunning, isTrue);
      expect(h.analytics.named(AnalyticsEvents.layoutStart).single['layout_id'], 'turtle');
    });

    test('resumes the saved board with its elapsed time', () async {
      final h = Harness();
      addTearDown(h.dispose);
      var saved = GameState.newGame(turtleLayout, 7, parMs: 360000);
      final (a, b) = saved.availableMoves.first;
      saved = match(saved, a, b, elapsedMs: 9000).$1;
      await h.repo.saveGame('turtle', stateJson: saved.toJson(), elapsedMs: 12345, fractionCleared: 2 / 144);

      const launch = GameLaunch.layout('turtle');
      final c = await h.open(launch);
      final s = h.state(launch);
      expect(s.resumed, isTrue);
      expect(s.game!.seed, 7);
      expect(s.tilesLeft, 142);
      expect(c.elapsedMs, 12345);
      expect(h.analytics.named(AnalyticsEvents.layoutStart).single['resumed'], 1);
    });

    test('a head-start bonus adds free hints to the next board once', () async {
      final h = Harness();
      addTearDown(h.dispose);
      h.container.read(headStartBonusProvider.notifier).grant(kHeadStartHints);
      const launch = GameLaunch.layout('turtle');
      await h.open(launch);
      expect(h.state(launch).freeHintsLeft, kFreeHintsPerBoard + kHeadStartHints);
      expect(h.container.read(headStartBonusProvider), 0);
    });
  });

  group('hints', () {
    test('three free hints, then the rewarded video grants one only when it rewards', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('turtle');
      final c = await h.open(launch);

      for (var i = 0; i < kFreeHintsPerBoard; i++) {
        expect(c.useHint(), HintAvailability.free);
        expect(h.state(launch).hint, isNotNull);
      }
      expect(h.state(launch).freeHintsLeft, 0);
      expect(c.useHint(), HintAvailability.needsReward);
      expect(h.ads.rewardedCalls, 0);

      h.ads.reward = false;
      expect(await c.watchAdForHint(), isFalse);
      expect(h.state(launch).game!.hintsUsed, 3);

      h.ads.reward = true;
      final events = <GameEvent>[];
      final sub = c.events.listen(events.add);
      addTearDown(sub.cancel);
      expect(await c.watchAdForHint(), isTrue);
      expect(events.whereType<HintShown>(), hasLength(1));
      expect(h.state(launch).game!.hintsUsed, 4);
      expect(h.ads.placements, [RewardedPlacement.hint, RewardedPlacement.hint]);
      expect(h.analytics.named(AnalyticsEvents.hintUsed).last['kind'], 'rewarded');
    });

    test('never offers the video on a deadlock: the free shuffle instead', () async {
      final h = Harness();
      addTearDown(h.dispose);
      final dead = stateWithFaces(stacksLayout, deadlockFaces).copyWith(
        freeHintsLeft: 0,
        moveLog: const [LogHint(HintKind.credit)],
      );
      expect(dead.isDeadlocked, isTrue);
      await h.repo.saveGame('stacks', stateJson: dead.toJson(), elapsedMs: 1000, fractionCleared: 0);

      const launch = GameLaunch.layout('stacks');
      final c = await h.open(launch);
      expect(h.state(launch).deadlocked, isTrue);
      expect(h.analytics.named(AnalyticsEvents.deadlockShown), hasLength(1));
      expect(c.useHint(), HintAvailability.noMoves);
      expect(await c.watchAdForHint(), isFalse);
      expect(h.ads.rewardedCalls, 0);

      expect(h.state(launch).shuffleAvailability, ShuffleAvailability.deadlockFree);
      expect(c.shuffleFromDeadlock(), isTrue);
      final s = h.state(launch);
      expect(s.deadlocked, isFalse);
      expect(s.game!.rewardedShuffles, 0);
      expect(s.freeShufflesLeft, kFreeShufflesPerBoard);
      expect(h.analytics.named(AnalyticsEvents.shuffleUsed).single['kind'], 'deadlock');
    });

    test('a hint clears on the next tap', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('turtle');
      final c = await h.open(launch);
      c.useHint();
      final (a, _) = h.state(launch).hint!;
      c.tap(a);
      expect(h.state(launch).hint, isNull);
    });
  });

  group('shuffles', () {
    test('two free credits, then a rewarded shuffle that costs the third star', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('turtle');
      final c = await h.open(launch);

      expect(h.state(launch).shuffleAvailability, ShuffleAvailability.free);
      expect(c.shuffleWithCredit(), isTrue);
      expect(c.shuffleWithCredit(), isTrue);
      expect(h.state(launch).freeShufflesLeft, 0);
      expect(h.state(launch).shuffleAvailability, ShuffleAvailability.needsReward);
      expect(c.shuffleWithCredit(), isFalse);

      h.ads.reward = false;
      expect(await c.watchAdForShuffle(), isFalse);
      expect(h.state(launch).game!.shufflesUsed, 2);

      h.ads.reward = true;
      expect(await c.watchAdForShuffle(), isTrue);
      final g = h.state(launch).game!;
      expect(g.shufflesUsed, 3);
      expect(g.rewardedShuffles, 1);
      expect(h.ads.placements.last, RewardedPlacement.shuffle);
      expect(h.analytics.named(AnalyticsEvents.shuffleUsed).map((e) => e['kind']), ['free', 'free', 'rewarded']);
    });

    test('the clock is stopped while the rewarded video plays', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('turtle');
      final c = await h.open(launch);
      c
        ..shuffleWithCredit()
        ..shuffleWithCredit();
      final future = c.watchAdForShuffle();
      expect(h.state(launch).busy, RewardBusy.shuffle);
      expect(h.clock.isRunning, isFalse);
      await future;
      expect(h.clock.isRunning, isTrue);
    });
  });

  group('clearing', () {
    test('daily clear records the result with stars, date and the move log', () async {
      const daily = DailyStatus(date: '2026-11-16', layoutId: 'pair', seed: 99);
      final h = Harness(daily: daily);
      addTearDown(h.dispose);
      const launch = GameLaunch.daily();
      final c = await h.open(launch);
      expect(h.state(launch).game!.seed, 99);
      expect(h.analytics.named(AnalyticsEvents.dailyStart), hasLength(1));

      h.clock.advance(5000);
      playMove(c, h.state(launch));
      expect(h.state(launch).phase, GamePhase.cleared);
      expect(h.clock.isRunning, isFalse);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final r = h.repo.results.single;
      expect(r.outcome, GameOutcome.cleared);
      expect(r.layoutId, 'pair');
      expect(r.seed, 99);
      expect(r.timeMs, 5000);
      expect(r.stars, 3);
      expect(r.dailyDate, '2026-11-16');
      final log = decodeMoveLog(r.moveLog!);
      expect(log.single, isA<LogMatch>());
      final replayed = replay(pairLayout, 99, kGeneratorVersion, r.moveLog!);
      expect(replayed.cleared, isTrue);

      final result = h.container.read(lastClearedProvider)!;
      expect(result.stars, 3);
      expect(result.isDaily, isTrue);
      expect(result.firstClear, isTrue);
      expect(h.state(launch).result, isNotNull);
      expect(h.ads.clearedCalls, 1);
      expect(h.analytics.named(AnalyticsEvents.boardCleared).single['stars'], 3);
      expect(h.analytics.named(AnalyticsEvents.dailyComplete), hasLength(1));
      expect(await h.repo.loadSavedGame('pair'), isNull);
    });

    test('collection clear: stars from the layout par, no daily fields', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('pair');
      final c = await h.open(launch);
      for (var i = 0; i < 4; i++) {
        c.useHint();
      }
      h.clock.advance(40000);
      playMove(c, h.state(launch));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final r = h.repo.results.single;
      expect(r.dailyDate, isNull);
      expect(r.moveLog, isNull);
      expect(r.hintsUsed, 3);
      // 40 s > 1.5 × 10 s par and 3 hints ≤ 3 → 2 stars.
      expect(r.stars, starsFor(timeMs: 40000, parMs: 10000, hintsUsed: 3, rewardedShuffles: 0));
      expect(r.stars, 2);
    });
  });

  group('lifecycle and persistence', () {
    test('backgrounding fires board_abandon, pauses, saves, and records nothing', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('turtle');
      final c = await h.open(launch);
      h.clock.advance(3000);
      playMove(c, h.state(launch));

      c.handleLifecycle(AppLifecycleState.inactive);
      expect(h.clock.isRunning, isFalse);
      c.handleLifecycle(AppLifecycleState.paused);
      expect(h.analytics.named(AnalyticsEvents.boardAbandon).single['tiles_left'], 142);
      expect(h.state(launch).pauseReason, PauseReason.background);
      await Future<void>.delayed(Duration.zero);
      expect(h.repo.results, isEmpty);
      final saved = await h.repo.loadSavedGame('turtle');
      expect(saved, isNotNull);
      expect(saved!.elapsedMs, 3000);

      h.clock.advance(5000);
      expect(c.elapsedMs, 3000);
      c.handleLifecycle(AppLifecycleState.resumed);
      expect(h.clock.isRunning, isFalse, reason: 'stays paused until the pause card is dismissed');
      c.resume();
      expect(h.clock.isRunning, isTrue);
    });

    test('no board_abandon once the board is cleared', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('pair');
      final c = await h.open(launch);
      playMove(c, h.state(launch));
      c.handleLifecycle(AppLifecycleState.paused);
      expect(h.analytics.named(AnalyticsEvents.boardAbandon), isEmpty);
    });

    test('moves are saved after a short debounce', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('turtle');
      final c = await h.open(launch);
      playMove(c, h.state(launch));
      expect(await h.repo.loadSavedGame('turtle'), isNull);
      await Future<void>.delayed(kSaveDebounce + const Duration(milliseconds: 100));
      final saved = await h.repo.loadSavedGame('turtle');
      expect(saved, isNotNull);
      expect(GameState.fromJson(turtleLayout, saved!.stateJson).tilesMatched, 2);
    });

    test('pause stops the clock; quit saves, logs board_abandon and releases', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('turtle');
      final c = await h.open(launch);
      h.clock.advance(1000);
      c.pause();
      h.clock.advance(1000);
      expect(c.elapsedMs, 1000);
      c.tap(h.state(launch).game!.freeTiles.first);
      expect(h.state(launch).game!.selected, isNull, reason: 'taps are ignored while paused');
      c.resume();
      playMove(c, h.state(launch));
      await c.quit();
      expect(h.analytics.named(AnalyticsEvents.boardAbandon).single['trigger'], 'quit');
      expect(await h.repo.loadSavedGame('turtle'), isNotNull);
    });

    test('combo counts matches at most 4 s apart', () async {
      final h = Harness();
      addTearDown(h.dispose);
      const launch = GameLaunch.layout('turtle');
      final c = await h.open(launch);
      for (var i = 0; i < 3; i++) {
        h.clock.advance(1000);
        playMove(c, h.state(launch));
      }
      expect(h.state(launch).combo, 3);
      h.clock.advance(5000);
      playMove(c, h.state(launch));
      expect(h.state(launch).combo, 1);
    });
  });
}
