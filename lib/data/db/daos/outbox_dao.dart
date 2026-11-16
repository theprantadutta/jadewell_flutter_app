import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../app_database.dart';
import '../tables.dart';

part 'outbox_dao.g.dart';

/// Outbox item kinds (the `kind` field of `POST /sync/batch` items).
abstract final class SyncKind {
  static const gameResult = 'game_result';
  static const personalBest = 'personal_best';
  static const dailyResult = 'daily_result';
  static const stats = 'stats';
  static const layoutUnlock = 'layout_unlock';
  static const streakRepair = 'streak_repair';
  static const reset = 'reset';

  /// Snapshot kinds: only the newest pending row matters, older ones are
  /// replaced on enqueue.
  static const coalesced = {stats};
}

@DriftAccessor(tables: [SyncOutboxTable])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.attachedDatabase);

  static const _uuid = Uuid();

  /// Adds an item. Call inside the transaction that makes the change.
  Future<String> enqueue(String kind, Map<String, Object?> payload, {required DateTime now}) async {
    if (SyncKind.coalesced.contains(kind)) {
      await (delete(syncOutboxTable)..where((t) => t.kind.equals(kind))).go();
    }
    final id = _uuid.v4();
    await into(syncOutboxTable).insert(SyncOutboxTableCompanion.insert(
      id: id,
      kind: kind,
      payload: jsonEncode(payload),
      nextAttemptAt: now,
      createdAt: now,
    ));
    return id;
  }

  /// Items due at [now], oldest first (insertion order breaks ties).
  Future<List<OutboxRow>> due(DateTime now, {int limit = 50}) => (select(syncOutboxTable)
        ..where((t) => t.nextAttemptAt.isSmallerOrEqualValue(now))
        ..orderBy([
          (t) => OrderingTerm.asc(t.createdAt),
          (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
        ])
        ..limit(limit))
      .get();

  Future<List<OutboxRow>> all() => (select(syncOutboxTable)
        ..orderBy([
          (t) => OrderingTerm.asc(t.createdAt),
          (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
        ]))
      .get();

  Stream<int> watchCount() {
    final c = syncOutboxTable.id.count();
    return (selectOnly(syncOutboxTable)..addColumns([c])).map((r) => r.read(c) ?? 0).watchSingle();
  }

  Future<void> deleteIds(Iterable<String> ids) =>
      (delete(syncOutboxTable)..where((t) => t.id.isIn(ids))).go();

  /// Counts a failed attempt and schedules the next one.
  Future<void> markFailed(OutboxRow row, DateTime nextAttemptAt) =>
      (update(syncOutboxTable)..where((t) => t.id.equals(row.id))).write(
        SyncOutboxTableCompanion(attempts: Value(row.attempts + 1), nextAttemptAt: Value(nextAttemptAt)),
      );

  /// Postpones without counting an attempt (endpoint missing, signed out).
  Future<void> defer(Iterable<String> ids, DateTime nextAttemptAt) =>
      (update(syncOutboxTable)..where((t) => t.id.isIn(ids)))
          .write(SyncOutboxTableCompanion(nextAttemptAt: Value(nextAttemptAt)));
}
