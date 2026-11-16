import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../models/settings.dart';
import 'daos/daily_dao.dart';
import 'daos/entitlements_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/progress_dao.dart';
import 'daos/settings_dao.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The app's Drift database. `*.g.dart` is gitignored: run
/// `dart run build_runner build --delete-conflicting-outputs` after a clone.
@DriftDatabase(
  tables: [
    SettingsTable,
    LayoutProgressTable,
    SavedGameTable,
    GameResultsTable,
    DailyEntriesTable,
    StreakTable,
    EntitlementsTable,
    SyncOutboxTable,
  ],
  daos: [SettingsDao, ProgressDao, DailyDao, EntitlementsDao, OutboxDao],
)
class AppDatabase extends _$AppDatabase {
  /// On-device database (`jadewell.sqlite`), opened on a background isolate.
  AppDatabase() : super(driftDatabase(name: 'jadewell'));

  /// Any executor, e.g. `NativeDatabase.memory()` in tests.
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await customStatement('CREATE INDEX IF NOT EXISTS idx_game_results_played_at ON game_results (played_at)');
          await customStatement('CREATE INDEX IF NOT EXISTS idx_sync_outbox_due ON sync_outbox (next_attempt_at)');
        },
        onUpgrade: (m, from, to) async {
          // schemaVersion 1 is the first shipped schema. Future versions add
          // explicit, step-by-step migrations here (never drop user data).
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
