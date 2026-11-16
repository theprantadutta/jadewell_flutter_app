import '../db/streak_rules.dart' show StreakRepairOffer;
import '../models/catalogue.dart';
import '../models/progress.dart';
import '../models/settings.dart';

export '../db/streak_rules.dart' show StreakRepairOffer;

/// Contracts between `state/` and storage. Drift-backed implementations live
/// in `data/db/`; in-memory ones in `memory_repositories.dart` (tests, previews).

abstract interface class CatalogueRepository {
  /// Parses `assets/layouts/` once.
  Future<Catalogue> load();
}

abstract interface class SettingsRepository {
  Stream<AppSettings> watch();
  Future<AppSettings> read();
  Future<void> write(AppSettings settings);
}

abstract interface class ProgressRepository {
  /// Layout id → progress (missing = never touched).
  Stream<Map<String, LayoutProgress>> watchAll();

  /// Stores a finished/abandoned game, updates bests/clears, stats, the daily
  /// entry and streak, clears the saved game, and enqueues sync, atomically.
  Future<RecordOutcome> recordResult(GameResult result);

  Future<void> unlockWithAd(String layoutId);

  /// Saved in-progress board (engine `GameState.toJson()` + elapsed time).
  Future<void> saveGame(String layoutId, {required Map<String, Object?> stateJson, required int elapsedMs, required double fractionCleared});
  Future<({Map<String, Object?> stateJson, int elapsedMs})?> loadSavedGame(String layoutId);
  Future<void> clearSavedGame(String layoutId);

  /// Settings → Reset progress.
  Future<void> resetAll();
}

abstract interface class StatsRepository {
  Stream<PlayerStats> watch();
}

abstract interface class DailyRepository {
  /// Today's board (UTC date), with this player's first clear and streak.
  Stream<DailyStatus> watchToday();

  /// Non-null while the broken daily streak can be restored with a rewarded
  /// ad: exactly one day (yesterday) missed, and no repair in the last 7 days.
  Stream<StreakRepairOffer?> watchRepairOffer();

  Future<bool> canRepairStreak();

  /// Bridges the missed day (call after the rewarded ad paid out). Returns
  /// false, changing nothing, when no repair is allowed.
  Future<bool> repairStreak();
}
