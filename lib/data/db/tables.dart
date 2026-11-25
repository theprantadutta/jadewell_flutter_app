import 'package:drift/drift.dart';

import '../models/settings.dart';

/// Drift tables (docs/ARCHITECTURE.md §3). One store per datum: everything
/// the player earns lives here; SharedPreferences only holds device flags.
///
/// DateTimes use Drift's default storage (unix seconds).

/// Single row (id = 0).
@DataClassName('SettingsRow')
class SettingsTable extends Table {
  @override
  String get tableName => 'settings';

  IntColumn get id => integer().withDefault(const Constant(0))();
  TextColumn get theme => textEnum<ThemePreference>().withDefault(Constant(ThemePreference.system.name))();
  BoolColumn get music => boolean().withDefault(const Constant(true))();
  BoolColumn get soundEffects => boolean().withDefault(const Constant(true))();
  BoolColumn get haptics => boolean().withDefault(const Constant(true))();
  BoolColumn get showTimer => boolean().withDefault(const Constant(true))();
  TextColumn get tileSize => textEnum<TileSizePreference>().withDefault(Constant(TileSizePreference.medium.name))();
  BoolColumn get reduceMotion => boolean().withDefault(const Constant(false))();

  /// Added in schema 2.
  BoolColumn get highRefreshRate => boolean().withDefault(const Constant(false))();

  /// Added in schema 3.
  BoolColumn get dailyReminder => boolean().withDefault(const Constant(true))();
  BoolColumn get onboardingDone => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('LayoutProgressRow')
class LayoutProgressTable extends Table {
  @override
  String get tableName => 'layout_progress';

  TextColumn get layoutId => text()();
  BoolColumn get adUnlocked => boolean().withDefault(const Constant(false))();
  IntColumn get bestTimeMs => integer().nullable()();
  IntColumn get bestStars => integer().withDefault(const Constant(0))();
  IntColumn get clears => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {layoutId};
}

/// The resumable in-progress board of a layout (engine `GameState.toJson()`).
@DataClassName('SavedGameRow')
class SavedGameTable extends Table {
  @override
  String get tableName => 'saved_game';

  TextColumn get layoutId => text()();
  TextColumn get stateJson => text()();
  IntColumn get elapsedMs => integer()();
  RealColumn get fractionCleared => real()();
  DateTimeColumn get savedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {layoutId};
}

/// Every finished or abandoned game.
@DataClassName('GameResultRow')
class GameResultsTable extends Table {
  @override
  String get tableName => 'game_results';

  /// UUID; also the `result_id` sent to the backend.
  TextColumn get id => text()();
  TextColumn get layoutId => text()();
  IntColumn get seed => integer()();
  IntColumn get generatorVersion => integer()();

  /// `cleared` | `abandoned`.
  TextColumn get outcome => text()();
  IntColumn get timeMs => integer()();
  IntColumn get stars => integer()();
  IntColumn get hintsUsed => integer()();
  IntColumn get undos => integer()();
  IntColumn get shufflesUsed => integer()();
  IntColumn get tilesMatched => integer()();
  IntColumn get longestStreak => integer()();
  DateTimeColumn get playedAt => dateTime()();

  /// UTC `YYYY-MM-DD` for daily games.
  TextColumn get dailyDate => text().nullable()();
  TextColumn get moveLog => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The ranked (first) clear of each UTC day's daily board.
@DataClassName('DailyEntryRow')
class DailyEntriesTable extends Table {
  @override
  String get tableName => 'daily_entries';

  /// UTC `YYYY-MM-DD`.
  TextColumn get date => text()();
  TextColumn get layoutId => text()();
  IntColumn get seed => integer()();
  IntColumn get firstClearMs => integer()();
  IntColumn get stars => integer()();
  TextColumn get moveLog => text().nullable()();

  /// The backend acknowledged the `daily_result` outbox item.
  BoolColumn get submitted => boolean().withDefault(const Constant(false))();

  /// The backend replayed the move log and accepted the time.
  BoolColumn get verified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get clearedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {date};
}

/// Daily-challenge streak, single row (id = 0). See `StreakRules`.
@DataClassName('StreakRow')
class StreakTable extends Table {
  @override
  String get tableName => 'streak';

  IntColumn get id => integer().withDefault(const Constant(0))();
  IntColumn get current => integer().withDefault(const Constant(0))();
  IntColumn get best => integer().withDefault(const Constant(0))();

  /// UTC `YYYY-MM-DD` of the last cleared (or repaired) daily.
  TextColumn get lastDailyDate => text().nullable()();
  DateTimeColumn get lastRepairAt => dateTime().nullable()();

  /// Streak lost when a clear followed exactly one missed day (repairable).
  IntColumn get brokenStreak => integer().withDefault(const Constant(0))();

  /// Last cleared date before that gap.
  TextColumn get brokenAfterDate => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Single row (id = 0). Written by the IAP layer (Phase 8).
@DataClassName('EntitlementsRow')
class EntitlementsTable extends Table {
  @override
  String get tableName => 'entitlements';

  IntColumn get id => integer().withDefault(const Constant(0))();
  BoolColumn get removeAds => boolean().withDefault(const Constant(false))();

  /// e.g. `play`, `app_store`, `restore`, `server`.
  TextColumn get source => text().nullable()();
  DateTimeColumn get verifiedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Pending backend writes, written in the same transaction as the change.
/// Only `SyncEngine` reads it.
@DataClassName('OutboxRow')
class SyncOutboxTable extends Table {
  @override
  String get tableName => 'sync_outbox';

  /// UUID; the backend's idempotency key.
  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get payload => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
