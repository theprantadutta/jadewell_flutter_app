import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../engine/engine.dart';
import '../models/progress.dart';
import '../models/settings.dart';
import '../repositories/repositories.dart';
import '../sync/sync_payloads.dart';
import 'app_database.dart';
import 'daos/outbox_dao.dart';
import 'streak_rules.dart';
import 'watch_utils.dart';

/// Drift-backed implementations of the repository contracts. Every write
/// that the backend should know about enqueues its outbox rows in the same
/// transaction; `SyncEngine` pushes them later.

typedef Clock = DateTime Function();

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);
  final AppDatabase _db;

  @override
  Stream<AppSettings> watch() => _db.settingsDao.watch();

  @override
  Future<AppSettings> read() => _db.settingsDao.read();

  @override
  Future<void> write(AppSettings settings) => _db.settingsDao.write(settings);
}

LayoutProgress _progressModel(LayoutProgressRow r, {double? savedFraction}) => LayoutProgress(
      layoutId: r.layoutId,
      adUnlocked: r.adUnlocked,
      bestTimeMs: r.bestTimeMs,
      bestStars: r.bestStars,
      clears: r.clears,
      lastPlayedAt: r.lastPlayedAt,
      savedFraction: savedFraction,
    );

/// Enqueues the current aggregate snapshot (coalesced: one pending row).
Future<void> _enqueueStats(AppDatabase db, DateTime now) async {
  final totals = await db.progressDao.totals();
  final streak = await db.dailyDao.streak();
  await db.outboxDao.enqueue(
    SyncKind.stats,
    SyncPayloads.stats(
      gamesPlayed: totals.gamesPlayed,
      boardsCleared: totals.boardsCleared,
      tilesMatched: totals.tilesMatched,
      currentStreak: StreakRules.effective(streak, utcDayNumber(now)),
      bestStreak: streak.best,
      lastDailyDate: streak.lastDay == null ? null : keyFromDay(streak.lastDay!),
    ),
    now: now,
  );
}

class DriftProgressRepository implements ProgressRepository {
  DriftProgressRepository(this._db, {Clock? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final Clock _clock;
  static const _uuid = Uuid();

  @override
  Stream<Map<String, LayoutProgress>> watchAll() => recomputeOn(
        [_db.tableUpdates(TableUpdateQuery.onAllTables([_db.layoutProgressTable, _db.savedGameTable]))],
        _readAll,
      );

  Future<Map<String, LayoutProgress>> _readAll() async {
    final rows = await _db.progressDao.allProgress();
    final saved = {for (final s in await _db.progressDao.allSavedGames()) s.layoutId: s.fractionCleared};
    final out = <String, LayoutProgress>{
      for (final r in rows) r.layoutId: _progressModel(r, savedFraction: saved[r.layoutId]),
    };
    for (final e in saved.entries) {
      out.putIfAbsent(e.key, () => LayoutProgress(layoutId: e.key, savedFraction: e.value));
    }
    return Map.unmodifiable(out);
  }

  @override
  Future<RecordOutcome> recordResult(GameResult r) => _db.transaction(() async {
        final now = _clock();
        final dao = _db.progressDao;
        final outbox = _db.outboxDao;
        final prevRow = await dao.progress(r.layoutId);
        final prev = prevRow == null ? LayoutProgress(layoutId: r.layoutId) : _progressModel(prevRow);
        final cleared = r.outcome == GameOutcome.cleared;

        final resultId = _uuid.v4();
        await dao.insertResult(GameResultsTableCompanion.insert(
          id: resultId,
          layoutId: r.layoutId,
          seed: r.seed,
          generatorVersion: r.generatorVersion,
          outcome: r.outcome.name,
          timeMs: r.timeMs,
          stars: r.stars,
          hintsUsed: r.hintsUsed,
          undos: r.undos,
          shufflesUsed: r.shufflesUsed,
          tilesMatched: r.tilesMatched,
          longestStreak: r.longestStreak,
          playedAt: r.playedAt,
          dailyDate: Value(r.dailyDate),
          moveLog: Value(r.moveLog),
        ));

        final isNewBest = cleared && (prev.bestTimeMs == null || r.timeMs < prev.bestTimeMs!);
        final moreStars = cleared && r.stars > prev.bestStars;
        final next = LayoutProgressRow(
          layoutId: r.layoutId,
          adUnlocked: prev.adUnlocked,
          bestTimeMs: isNewBest ? r.timeMs : prev.bestTimeMs,
          bestStars: moreStars ? r.stars : prev.bestStars,
          clears: prev.clears + (cleared ? 1 : 0),
          lastPlayedAt: r.playedAt,
        );
        await dao.upsertProgress(next);
        await dao.deleteSavedGame(r.layoutId);
        final nextModel = _progressModel(next);

        await outbox.enqueue(SyncKind.gameResult, SyncPayloads.gameResult(resultId, r), now: now);
        if (isNewBest || moreStars) {
          await outbox.enqueue(SyncKind.personalBest, SyncPayloads.personalBest(resultId, r, nextModel), now: now);
        }

        final date = r.dailyDate;
        if (cleared && date != null && await _db.dailyDao.entry(date) == null) {
          // First clear of that UTC day's daily: the ranked one.
          await _db.dailyDao.insertEntry(DailyEntriesTableCompanion.insert(
            date: date,
            layoutId: r.layoutId,
            seed: r.seed,
            firstClearMs: r.timeMs,
            stars: r.stars,
            moveLog: Value(r.moveLog),
            clearedAt: r.playedAt,
          ));
          final streak = await _db.dailyDao.streak();
          await _db.dailyDao.writeStreak(StreakRules.onDailyClear(streak, dayFromKey(date)));
          await outbox.enqueue(SyncKind.dailyResult, SyncPayloads.dailyResult(resultId, r), now: now);
        }

        await _enqueueStats(_db, now);
        return RecordOutcome(isNewBest: isNewBest, previousBestMs: prev.bestTimeMs, progress: nextModel);
      });

  @override
  Future<void> unlockWithAd(String layoutId) => _db.transaction(() async {
        final now = _clock();
        await _db.progressDao.markAdUnlocked(layoutId);
        await _db.outboxDao.enqueue(SyncKind.layoutUnlock, SyncPayloads.layoutUnlock(layoutId, now), now: now);
      });

  @override
  Future<void> saveGame(String layoutId,
          {required Map<String, Object?> stateJson, required int elapsedMs, required double fractionCleared}) =>
      _db.transaction(() async {
        final now = _clock();
        await _db.progressDao.upsertSavedGame(SavedGameTableCompanion.insert(
          layoutId: layoutId,
          stateJson: jsonEncode(stateJson),
          elapsedMs: elapsedMs,
          fractionCleared: fractionCleared,
          savedAt: now,
        ));
        await _db.progressDao.touch(layoutId, now);
      });

  @override
  Future<({Map<String, Object?> stateJson, int elapsedMs})?> loadSavedGame(String layoutId) async {
    final row = await _db.progressDao.savedGame(layoutId);
    if (row == null) return null;
    try {
      final decoded = jsonDecode(row.stateJson);
      if (decoded is! Map<String, dynamic>) return null;
      return (stateJson: Map<String, Object?>.from(decoded), elapsedMs: row.elapsedMs);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> clearSavedGame(String layoutId) => _db.progressDao.deleteSavedGame(layoutId);

  @override
  Future<void> resetAll() => _db.transaction(() async {
        final now = _clock();
        await _db.progressDao.wipe();
        await _db.dailyDao.wipe();
        await _db.outboxDao.enqueue(SyncKind.reset, SyncPayloads.reset(now), now: now);
      });

  @override
  Future<void> wipeForDeletedAccount() => _db.transaction(() async {
        await _db.progressDao.wipe();
        await _db.dailyDao.wipe();
        await _db.outboxDao.wipe();
      });
}

class DriftStatsRepository implements StatsRepository {
  DriftStatsRepository(this._db, {Clock? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final Clock _clock;

  @override
  Stream<PlayerStats> watch() => recomputeOn(
        [
          _db.tableUpdates(TableUpdateQuery.onAllTables([_db.gameResultsTable, _db.streakTable])),
          midnightTicks(_clock, utc: false),
          midnightTicks(_clock, utc: true),
        ],
        read,
      );

  /// One snapshot (also used by [watch]).
  Future<PlayerStats> read() async {
    final now = _clock();
    final totals = await _db.progressDao.totals();
    final streak = await _db.dailyDao.streak();

    final local = now.toLocal();
    final start = DateTime(local.year, local.month, local.day - 6);
    final startDay = DateTime.utc(start.year, start.month, start.day);
    final days = List<int>.filled(7, 0);
    for (final t in await _db.progressDao.playedSince(start)) {
      final l = t.toLocal();
      final i = DateTime.utc(l.year, l.month, l.day).difference(startDay).inDays;
      if (i >= 0 && i < 7) days[i]++;
    }

    return PlayerStats(
      gamesPlayed: totals.gamesPlayed,
      boardsCleared: totals.boardsCleared,
      tilesMatched: totals.tilesMatched,
      currentStreak: StreakRules.effective(streak, utcDayNumber(now)),
      bestStreak: streak.best,
      last7Days: List.unmodifiable(days),
    );
  }
}

class DriftDailyRepository implements DailyRepository {
  DriftDailyRepository(this._db, this._pool, {Clock? clock}) : _clock = clock ?? DateTime.now;

  final AppDatabase _db;

  /// `index.json`'s `dailyPool`, in file order.
  final List<String> _pool;
  final Clock _clock;

  @override
  Stream<DailyStatus> watchToday() => recomputeOn(
        [
          _db.tableUpdates(TableUpdateQuery.onAllTables([_db.dailyEntriesTable, _db.streakTable])),
          midnightTicks(_clock, utc: true),
        ],
        today,
      );

  /// One snapshot (also used by [watchToday]).
  Future<DailyStatus> today() async {
    final now = _clock().toUtc();
    final day = utcDayNumber(now);
    final date = keyFromDay(day);
    final layoutId = dailyLayoutId(now, _pool);
    final entry = await _db.dailyDao.entry(date);
    final streak = await _db.dailyDao.streak();

    final monday = day - (now.weekday - DateTime.monday);
    final week = [for (var i = 0; i < 7; i++) keyFromDay(monday + i)];
    final done = {for (final e in await _db.dailyDao.entries(week)) e.date};

    return DailyStatus(
      date: date,
      layoutId: layoutId,
      seed: dailySeed(now, layoutId, kGeneratorVersion),
      firstClearMs: entry?.firstClearMs,
      firstClearStars: entry?.stars,
      streak: StreakRules.effective(streak, day),
      weekDone: List.unmodifiable([for (final d in week) done.contains(d)]),
    );
  }

  Future<StreakRepairOffer?> _offer() async {
    final now = _clock();
    return StreakRules.repairOffer(await _db.dailyDao.streak(), utcDayNumber(now), now);
  }

  @override
  Stream<StreakRepairOffer?> watchRepairOffer() => recomputeOn(
        [
          _db.tableUpdates(TableUpdateQuery.onAllTables([_db.streakTable])),
          midnightTicks(_clock, utc: true),
        ],
        _offer,
      );

  @override
  Future<bool> canRepairStreak() async => await _offer() != null;

  @override
  Future<bool> repairStreak() => _db.transaction(() async {
        final now = _clock();
        final today = utcDayNumber(now);
        final current = await _db.dailyDao.streak();
        final offer = StreakRules.repairOffer(current, today, now);
        final next = StreakRules.repair(current, today, now);
        if (offer == null || next == null) return false;
        await _db.dailyDao.writeStreak(next);
        await _db.outboxDao.enqueue(
          SyncKind.streakRepair,
          SyncPayloads.streakRepair(missedDate: offer.missedDate, streak: next.current, at: now),
          now: now,
        );
        await _enqueueStats(_db, now);
        return true;
      });
}
