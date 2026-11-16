import 'package:drift/drift.dart';

import '../app_database.dart';
import '../streak_rules.dart';
import '../tables.dart';

part 'daily_dao.g.dart';

@DriftAccessor(tables: [DailyEntriesTable, StreakTable])
class DailyDao extends DatabaseAccessor<AppDatabase> with _$DailyDaoMixin {
  DailyDao(super.attachedDatabase);

  // ---- daily_entries ----

  Future<DailyEntryRow?> entry(String date) =>
      (select(dailyEntriesTable)..where((t) => t.date.equals(date))).getSingleOrNull();

  Future<List<DailyEntryRow>> entries(Iterable<String> dates) =>
      (select(dailyEntriesTable)..where((t) => t.date.isIn(dates))).get();

  Future<void> insertEntry(DailyEntriesTableCompanion row) => into(dailyEntriesTable).insert(row);

  /// After the backend acknowledged the `daily_result` for [date].
  Future<void> markSubmitted(String date, {bool? verified}) =>
      (update(dailyEntriesTable)..where((t) => t.date.equals(date))).write(DailyEntriesTableCompanion(
        submitted: const Value(true),
        verified: verified == null ? const Value.absent() : Value(verified),
      ));

  // ---- streak ----

  Future<StreakSnapshot> streak() async {
    final r = await select(streakTable).getSingleOrNull();
    if (r == null) return const StreakSnapshot();
    return StreakSnapshot(
      current: r.current,
      best: r.best,
      lastDay: r.lastDailyDate == null ? null : dayFromKey(r.lastDailyDate!),
      lastRepairAt: r.lastRepairAt,
      brokenStreak: r.brokenStreak,
      brokenAfterDay: r.brokenAfterDate == null ? null : dayFromKey(r.brokenAfterDate!),
    );
  }

  Future<void> writeStreak(StreakSnapshot s) => into(streakTable).insertOnConflictUpdate(StreakTableCompanion.insert(
        id: const Value(0),
        current: Value(s.current),
        best: Value(s.best),
        lastDailyDate: Value(s.lastDay == null ? null : keyFromDay(s.lastDay!)),
        lastRepairAt: Value(s.lastRepairAt),
        brokenStreak: Value(s.brokenStreak),
        brokenAfterDate: Value(s.brokenAfterDay == null ? null : keyFromDay(s.brokenAfterDay!)),
      ));

  Future<void> wipe() async {
    await delete(dailyEntriesTable).go();
    await delete(streakTable).go();
  }
}
