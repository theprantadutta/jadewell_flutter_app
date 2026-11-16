import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'progress_dao.g.dart';

/// Aggregates over `game_results`.
class ResultTotals {
  const ResultTotals({required this.gamesPlayed, required this.boardsCleared, required this.tilesMatched});
  final int gamesPlayed;
  final int boardsCleared;
  final int tilesMatched;
}

@DriftAccessor(tables: [LayoutProgressTable, SavedGameTable, GameResultsTable])
class ProgressDao extends DatabaseAccessor<AppDatabase> with _$ProgressDaoMixin {
  ProgressDao(super.attachedDatabase);

  // ---- layout_progress ----

  Future<LayoutProgressRow?> progress(String layoutId) =>
      (select(layoutProgressTable)..where((t) => t.layoutId.equals(layoutId))).getSingleOrNull();

  Future<List<LayoutProgressRow>> allProgress() => select(layoutProgressTable).get();

  Future<void> upsertProgress(LayoutProgressRow row) => into(layoutProgressTable).insertOnConflictUpdate(row);

  /// Creates the row if needed and sets only [lastPlayedAt].
  Future<void> touch(String layoutId, DateTime lastPlayedAt) => into(layoutProgressTable).insert(
        LayoutProgressTableCompanion.insert(layoutId: layoutId, lastPlayedAt: Value(lastPlayedAt)),
        onConflict: DoUpdate((_) => LayoutProgressTableCompanion(lastPlayedAt: Value(lastPlayedAt))),
      );

  /// Creates the row if needed and sets `adUnlocked`.
  Future<void> markAdUnlocked(String layoutId) => into(layoutProgressTable).insert(
        LayoutProgressTableCompanion.insert(layoutId: layoutId, adUnlocked: const Value(true)),
        onConflict: DoUpdate((_) => const LayoutProgressTableCompanion(adUnlocked: Value(true))),
      );

  // ---- saved_game ----

  Future<SavedGameRow?> savedGame(String layoutId) =>
      (select(savedGameTable)..where((t) => t.layoutId.equals(layoutId))).getSingleOrNull();

  Future<List<SavedGameRow>> allSavedGames() => select(savedGameTable).get();

  Future<void> upsertSavedGame(SavedGameTableCompanion row) => into(savedGameTable).insertOnConflictUpdate(row);

  Future<void> deleteSavedGame(String layoutId) =>
      (delete(savedGameTable)..where((t) => t.layoutId.equals(layoutId))).go();

  // ---- game_results ----

  Future<void> insertResult(GameResultsTableCompanion row) => into(gameResultsTable).insert(row);

  Future<ResultTotals> totals() async {
    final count = gameResultsTable.id.count();
    final cleared = gameResultsTable.id.count(filter: gameResultsTable.outcome.equals('cleared'));
    final tiles = gameResultsTable.tilesMatched.sum();
    final row = await (selectOnly(gameResultsTable)..addColumns([count, cleared, tiles])).getSingle();
    return ResultTotals(
      gamesPlayed: row.read(count) ?? 0,
      boardsCleared: row.read(cleared) ?? 0,
      tilesMatched: row.read(tiles) ?? 0,
    );
  }

  /// `playedAt` of every game since [from] (inclusive).
  Future<List<DateTime>> playedSince(DateTime from) {
    final q = selectOnly(gameResultsTable)
      ..addColumns([gameResultsTable.playedAt])
      ..where(gameResultsTable.playedAt.isBiggerOrEqualValue(from));
    return q.map((r) => r.read(gameResultsTable.playedAt)!).get();
  }

  Future<void> wipe() async {
    await delete(layoutProgressTable).go();
    await delete(savedGameTable).go();
    await delete(gameResultsTable).go();
  }
}
