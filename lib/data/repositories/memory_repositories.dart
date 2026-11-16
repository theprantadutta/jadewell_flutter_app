import 'dart:async';

import '../../engine/engine.dart';
import '../models/catalogue.dart';
import '../models/progress.dart';
import '../models/settings.dart';
import 'repositories.dart';

/// In-memory implementations for tests, previews and until Drift lands.
class MemorySettingsRepository implements SettingsRepository {
  MemorySettingsRepository([AppSettings initial = const AppSettings()]) : _value = initial;

  AppSettings _value;
  final _ctrl = StreamController<AppSettings>.broadcast();

  @override
  Future<AppSettings> read() async => _value;

  @override
  Stream<AppSettings> watch() async* {
    yield _value;
    yield* _ctrl.stream;
  }

  @override
  Future<void> write(AppSettings settings) async {
    _value = settings;
    _ctrl.add(settings);
  }
}

class MemoryProgressRepository implements ProgressRepository, StatsRepository {
  final Map<String, LayoutProgress> _progress = {};
  final Map<String, ({Map<String, Object?> stateJson, int elapsedMs})> _saved = {};
  final List<GameResult> results = [];
  final _ctrl = StreamController<void>.broadcast();

  void _changed() => _ctrl.add(null);

  @override
  Stream<Map<String, LayoutProgress>> watchAll() async* {
    yield Map.unmodifiable(_progress);
    await for (final _ in _ctrl.stream) {
      yield Map.unmodifiable(_progress);
    }
  }

  @override
  Future<RecordOutcome> recordResult(GameResult r) async {
    results.add(r);
    final prev = _progress[r.layoutId] ?? LayoutProgress(layoutId: r.layoutId);
    var next = prev.copyWith(lastPlayedAt: r.playedAt, clearSaved: true);
    var isNewBest = false;
    if (r.outcome == GameOutcome.cleared) {
      isNewBest = prev.bestTimeMs == null || r.timeMs < prev.bestTimeMs!;
      next = next.copyWith(
        clears: prev.clears + 1,
        bestTimeMs: isNewBest ? r.timeMs : prev.bestTimeMs,
        bestStars: r.stars > prev.bestStars ? r.stars : prev.bestStars,
      );
    }
    _progress[r.layoutId] = next;
    _saved.remove(r.layoutId);
    _changed();
    return RecordOutcome(isNewBest: isNewBest, previousBestMs: prev.bestTimeMs, progress: next);
  }

  @override
  Future<void> unlockWithAd(String layoutId) async {
    _progress[layoutId] = (_progress[layoutId] ?? LayoutProgress(layoutId: layoutId)).copyWith(adUnlocked: true);
    _changed();
  }

  @override
  Future<void> saveGame(String layoutId,
      {required Map<String, Object?> stateJson, required int elapsedMs, required double fractionCleared}) async {
    _saved[layoutId] = (stateJson: stateJson, elapsedMs: elapsedMs);
    _progress[layoutId] = (_progress[layoutId] ?? LayoutProgress(layoutId: layoutId))
        .copyWith(savedFraction: fractionCleared, lastPlayedAt: DateTime.now());
    _changed();
  }

  @override
  Future<({Map<String, Object?> stateJson, int elapsedMs})?> loadSavedGame(String layoutId) async => _saved[layoutId];

  @override
  Future<void> clearSavedGame(String layoutId) async {
    _saved.remove(layoutId);
    final p = _progress[layoutId];
    if (p != null) _progress[layoutId] = p.copyWith(clearSaved: true);
    _changed();
  }

  @override
  Future<void> resetAll() async {
    _progress.clear();
    _saved.clear();
    results.clear();
    _changed();
  }

  @override
  Stream<PlayerStats> watch() async* {
    PlayerStats compute() => PlayerStats(
          gamesPlayed: results.length,
          boardsCleared: results.where((r) => r.outcome == GameOutcome.cleared).length,
          tilesMatched: results.fold(0, (s, r) => s + r.tilesMatched),
        );
    yield compute();
    await for (final _ in _ctrl.stream) {
      yield compute();
    }
  }
}

/// Daily status computed from the catalogue pool and recorded results.
class MemoryDailyRepository implements DailyRepository {
  MemoryDailyRepository(this._catalogue, this._progress, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final Catalogue _catalogue;
  final MemoryProgressRepository _progress;
  final DateTime Function() _clock;

  DailyStatus _compute() {
    final now = _clock().toUtc();
    final date = dailySeedKey(now, '', kGeneratorVersion).split('|').first;
    final layoutId = dailyLayoutId(now, _catalogue.dailyPool);
    final first = _progress.results
        .where((r) => r.dailyDate == date && r.outcome == GameOutcome.cleared)
        .firstOrNull;
    return DailyStatus(
      date: date,
      layoutId: layoutId,
      seed: dailySeed(now, layoutId, kGeneratorVersion),
      firstClearMs: first?.timeMs,
      firstClearStars: first?.stars,
    );
  }

  @override
  Stream<DailyStatus> watchToday() async* {
    yield _compute();
    await for (final _ in _progress.watchAll()) {
      yield _compute();
    }
  }
}
