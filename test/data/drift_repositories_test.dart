import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/db/app_database.dart';
import 'package:jadewell_flutter_app/data/db/daos/outbox_dao.dart';
import 'package:jadewell_flutter_app/data/db/drift_repositories.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/models/settings.dart';
import 'package:jadewell_flutter_app/engine/engine.dart';

GameResult result({
  String layoutId = 'turtle',
  GameOutcome outcome = GameOutcome.cleared,
  int timeMs = 300000,
  int stars = 2,
  int tiles = 144,
  DateTime? playedAt,
  String? dailyDate,
  String? moveLog,
}) =>
    GameResult(
      layoutId: layoutId,
      seed: 42,
      generatorVersion: 1,
      outcome: outcome,
      timeMs: timeMs,
      stars: stars,
      hintsUsed: 1,
      undos: 2,
      shufflesUsed: 0,
      tilesMatched: tiles,
      longestStreak: 5,
      playedAt: playedAt ?? DateTime(2026, 11, 16, 10),
      dailyDate: dailyDate,
      moveLog: moveLog,
    );

void main() {
  late AppDatabase db;
  late DateTime now;
  DateTime clock() => now;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime.utc(2026, 11, 16, 12); // Monday
  });
  tearDown(() => db.close());

  Future<List<String>> kinds() async => [for (final r in await db.outboxDao.all()) r.kind];
  Future<Map<String, dynamic>> payloadOf(String kind) async =>
      jsonDecode((await db.outboxDao.all()).lastWhere((r) => r.kind == kind).payload) as Map<String, dynamic>;

  group('settings', () {
    test('defaults, round-trip and watch', () async {
      final repo = DriftSettingsRepository(db);
      expect((await repo.read()).theme, ThemePreference.system);
      const s = AppSettings(
        theme: ThemePreference.dark,
        music: false,
        soundEffects: false,
        haptics: false,
        showTimer: false,
        tileSize: TileSizePreference.large,
        reduceMotion: true,
        onboardingDone: true,
      );
      await repo.write(s);
      final back = await repo.read();
      expect(
        [back.theme, back.music, back.soundEffects, back.haptics, back.showTimer, back.tileSize, back.reduceMotion, back.onboardingDone],
        [ThemePreference.dark, false, false, false, false, TileSizePreference.large, true, true],
      );
      expect((await repo.watch().first).tileSize, TileSizePreference.large);
    });
  });

  group('recordResult', () {
    test('first clear sets bests, clears, stars and enqueues sync', () async {
      final repo = DriftProgressRepository(db, clock: clock);
      final out = await repo.recordResult(result(timeMs: 300000, stars: 2));
      expect(out.isNewBest, isTrue);
      expect(out.previousBestMs, isNull);
      expect((out.progress.clears, out.progress.bestTimeMs, out.progress.bestStars), (1, 300000, 2));
      expect(await kinds(), [SyncKind.gameResult, SyncKind.personalBest, SyncKind.stats]);
      final gr = await payloadOf(SyncKind.gameResult);
      expect(gr['layout_id'], 'turtle');
      expect(gr['outcome'], 'cleared');
      expect(gr['result_id'], isA<String>());
      expect((await payloadOf(SyncKind.stats))['games_played'], 1);
    });

    test('slower clear keeps best time but can raise stars; no PB when neither improves', () async {
      final repo = DriftProgressRepository(db, clock: clock);
      await repo.recordResult(result(timeMs: 300000, stars: 1));
      final slowerMoreStars = await repo.recordResult(result(timeMs: 400000, stars: 3));
      expect(slowerMoreStars.isNewBest, isFalse);
      expect(slowerMoreStars.previousBestMs, 300000);
      expect((slowerMoreStars.progress.bestTimeMs, slowerMoreStars.progress.bestStars, slowerMoreStars.progress.clears),
          (300000, 3, 2));

      await db.outboxDao.deleteIds([for (final r in await db.outboxDao.all()) r.id]);
      final plain = await repo.recordResult(result(timeMs: 500000, stars: 2));
      expect(plain.isNewBest, isFalse);
      expect(await kinds(), [SyncKind.gameResult, SyncKind.stats]);

      final faster = await repo.recordResult(result(timeMs: 200000, stars: 2));
      expect(faster.isNewBest, isTrue);
      expect(faster.previousBestMs, 300000);
      final all = (await repo.watchAll().first)['turtle']!;
      expect((all.bestTimeMs, all.bestStars, all.clears), (200000, 3, 4));
    });

    test('abandoned game only updates lastPlayed', () async {
      final repo = DriftProgressRepository(db, clock: clock);
      final out = await repo.recordResult(result(outcome: GameOutcome.abandoned, stars: 0, tiles: 40));
      expect(out.isNewBest, isFalse);
      expect((out.progress.clears, out.progress.bestTimeMs, out.progress.lastPlayedAt), (0, null, DateTime(2026, 11, 16, 10)));
      expect(await kinds(), [SyncKind.gameResult, SyncKind.stats]);
    });

    test('clears the saved game; stats snapshot is coalesced', () async {
      final repo = DriftProgressRepository(db, clock: clock);
      await repo.saveGame('turtle', stateJson: {'seed': 42, 'removed': [1, 2]}, elapsedMs: 12000, fractionCleared: 0.25);
      final loaded = await repo.loadSavedGame('turtle');
      expect(loaded!.elapsedMs, 12000);
      expect(loaded.stateJson['removed'], [1, 2]);
      final p = (await repo.watchAll().first)['turtle']!;
      expect((p.savedFraction, p.hasSavedGame), (0.25, true));
      expect(p.lastPlayedAt, isNotNull);

      await repo.recordResult(result());
      await repo.recordResult(result(outcome: GameOutcome.abandoned));
      expect(await repo.loadSavedGame('turtle'), isNull);
      expect((await repo.watchAll().first)['turtle']!.hasSavedGame, isFalse);
      expect((await kinds()).where((k) => k == SyncKind.stats).length, 1);
      expect((await payloadOf(SyncKind.stats))['games_played'], 2);
    });

    test('watchAll emits on change', () async {
      final repo = DriftProgressRepository(db, clock: clock);
      final emissions = <Map<String, LayoutProgress>>[];
      final sub = repo.watchAll().listen(emissions.add);
      await pumpEventQueue();
      await repo.recordResult(result());
      await pumpEventQueue();
      await sub.cancel();
      expect(emissions.first, isEmpty);
      expect(emissions.last['turtle']!.clears, 1);
    });

    test('unlockWithAd sets the flag and enqueues layout_unlock', () async {
      final repo = DriftProgressRepository(db, clock: clock);
      await repo.recordResult(result(layoutId: 'dragon', outcome: GameOutcome.abandoned));
      await repo.unlockWithAd('dragon');
      await repo.unlockWithAd('fortress');
      final all = await repo.watchAll().first;
      expect(all['dragon']!.adUnlocked, isTrue);
      expect(all['dragon']!.lastPlayedAt, isNotNull);
      expect(all['fortress']!.adUnlocked, isTrue);
      expect((await payloadOf(SyncKind.layoutUnlock))['source'], 'rewarded_ad');
    });
  });

  group('daily', () {
    const pool = ['turtle', 'fortress', 'dragon'];

    test('only the first clear of a UTC day is the ranked entry', () async {
      final repo = DriftProgressRepository(db, clock: clock);
      final daily = DriftDailyRepository(db, pool, clock: clock);
      final today = await daily.today();
      expect(today.date, '2026-11-16');
      expect(today.layoutId, dailyLayoutId(now, pool));
      expect(today.seed, dailySeed(now, today.layoutId, kGeneratorVersion));
      expect(today.clearedToday, isFalse);

      await repo.recordResult(result(layoutId: today.layoutId, outcome: GameOutcome.abandoned, dailyDate: '2026-11-16'));
      expect((await daily.today()).clearedToday, isFalse);
      await repo.recordResult(result(layoutId: today.layoutId, timeMs: 250000, stars: 2, dailyDate: '2026-11-16', moveLog: 'AAA'));
      await repo.recordResult(result(layoutId: today.layoutId, timeMs: 100000, stars: 3, dailyDate: '2026-11-16', moveLog: 'BBB'));

      final s = await daily.today();
      expect((s.firstClearMs, s.firstClearStars, s.streak), (250000, 2, 1));
      expect(s.weekDone, [true, false, false, false, false, false, false]);
      expect((await kinds()).where((k) => k == SyncKind.dailyResult).length, 1);
      final dr = await payloadOf(SyncKind.dailyResult);
      expect((dr['date'], dr['move_log'], dr['time_ms']), ('2026-11-16', 'AAA', 250000));
      final entry = await db.dailyDao.entry('2026-11-16');
      expect((entry!.submitted, entry.verified), (false, false));
    });

    test('streak increments on consecutive days, breaks after a gap, weekDone follows Mon..Sun', () async {
      final repo = DriftProgressRepository(db, clock: clock);
      final daily = DriftDailyRepository(db, pool, clock: clock);
      final stats = DriftStatsRepository(db, clock: clock);
      for (final date in ['2026-11-16', '2026-11-17', '2026-11-18']) {
        await repo.recordResult(result(dailyDate: date));
      }
      now = DateTime.utc(2026, 11, 18, 20);
      var s = await daily.today();
      expect(s.streak, 3);
      expect(s.weekDone, [true, true, true, false, false, false, false]);
      expect((await stats.read()).currentStreak, 3);

      now = DateTime.utc(2026, 11, 19, 8); // not played yet today: still alive
      expect((await daily.today()).streak, 3);
      now = DateTime.utc(2026, 11, 21, 8); // missed two days
      expect((await daily.today()).streak, 0);
      expect(await daily.canRepairStreak(), isFalse);
      await repo.recordResult(result(dailyDate: '2026-11-21'));
      s = await daily.today();
      expect(s.streak, 1);
      final st = await stats.read();
      expect((st.currentStreak, st.bestStreak), (1, 3));

      now = DateTime.utc(2026, 11, 23, 8); // Monday: a new week
      expect((await daily.today()).weekDone, everyElement(isFalse));
    });

    test('repair: one missed day, once per 7 days, enqueues streak_repair', () async {
      final repo = DriftProgressRepository(db, clock: clock);
      final daily = DriftDailyRepository(db, pool, clock: clock);
      for (final date in ['2026-11-16', '2026-11-17']) {
        await repo.recordResult(result(dailyDate: date));
      }
      now = DateTime.utc(2026, 11, 19, 9); // missed the 18th
      expect((await daily.today()).streak, 0);
      expect(await daily.watchRepairOffer().first, isA<Object>());
      expect(await daily.canRepairStreak(), isTrue);
      expect(await daily.repairStreak(), isTrue);
      expect((await daily.today()).streak, 2);
      expect(await daily.canRepairStreak(), isFalse);
      expect(await daily.repairStreak(), isFalse);
      final rp = await payloadOf(SyncKind.streakRepair);
      expect((rp['missed_date'], rp['streak']), ('2026-11-18', 2));

      await repo.recordResult(result(dailyDate: '2026-11-19'));
      expect((await daily.today()).streak, 3);

      // Miss the 20th, clear the 21st, then try to repair: within 7 days of the last repair.
      now = DateTime.utc(2026, 11, 21, 9);
      await repo.recordResult(result(dailyDate: '2026-11-21'));
      expect((await daily.today()).streak, 1);
      expect(await daily.repairStreak(), isFalse);

      // Same situation 8 days later: allowed, restores broken + today.
      for (final date in ['2026-11-22', '2026-11-23', '2026-11-24', '2026-11-25', '2026-11-26']) {
        await repo.recordResult(result(dailyDate: date));
      }
      now = DateTime.utc(2026, 11, 28, 9); // missed the 27th
      await repo.recordResult(result(dailyDate: '2026-11-28'));
      expect((await daily.today()).streak, 1);
      final offer = await daily.watchRepairOffer().first;
      expect(offer!.restoredStreak, 7);
      expect(await daily.repairStreak(), isTrue);
      expect((await daily.today()).streak, 7);
    });
  });

  group('stats', () {
    test('totals and last7Days (local days, oldest first)', () async {
      now = DateTime(2026, 11, 16, 12);
      final repo = DriftProgressRepository(db, clock: clock);
      final stats = DriftStatsRepository(db, clock: clock);
      expect((await stats.read()).isEmpty, isTrue);
      await repo.recordResult(result(playedAt: DateTime(2026, 11, 16, 9), tiles: 144));
      await repo.recordResult(result(playedAt: DateTime(2026, 11, 16, 0, 0, 5), tiles: 144));
      await repo.recordResult(result(playedAt: DateTime(2026, 11, 15, 23), outcome: GameOutcome.abandoned, tiles: 60));
      await repo.recordResult(result(playedAt: DateTime(2026, 11, 10, 12), tiles: 144));
      await repo.recordResult(result(playedAt: DateTime(2026, 11, 9, 23, 59), tiles: 144)); // 8 days ago
      final s = await stats.read();
      expect((s.gamesPlayed, s.boardsCleared, s.tilesMatched), (5, 4, 636));
      expect(s.last7Days, [1, 0, 0, 0, 0, 1, 2]);
      expect((await stats.watch().first).gamesPlayed, 5);
    });
  });

  test('resetAll wipes progress, results, saved, daily, streak; keeps settings', () async {
    final settings = DriftSettingsRepository(db);
    await settings.write(const AppSettings(theme: ThemePreference.dark));
    await db.entitlementsDao.setRemoveAds(true, source: 'play');
    final repo = DriftProgressRepository(db, clock: clock);
    final daily = DriftDailyRepository(db, const ['turtle'], clock: clock);
    final stats = DriftStatsRepository(db, clock: clock);
    await repo.recordResult(result(dailyDate: '2026-11-16'));
    await repo.saveGame('fortress', stateJson: const {}, elapsedMs: 1, fractionCleared: 0.1);
    await repo.unlockWithAd('dragon');

    await repo.resetAll();
    expect(await repo.watchAll().first, isEmpty);
    expect(await repo.loadSavedGame('fortress'), isNull);
    expect((await stats.read()).gamesPlayed, 0);
    expect((await stats.read()).bestStreak, 0);
    final d = await daily.today();
    expect((d.clearedToday, d.streak), (false, 0));
    expect((await settings.read()).theme, ThemePreference.dark);
    expect((await db.entitlementsDao.read())!.removeAds, isTrue);
    expect((await kinds()).last, SyncKind.reset);
  });
}
