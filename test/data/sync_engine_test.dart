import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/api/api_result.dart';
import 'package:jadewell_flutter_app/data/db/app_database.dart';
import 'package:jadewell_flutter_app/data/db/daos/outbox_dao.dart';
import 'package:jadewell_flutter_app/data/db/drift_repositories.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/sync/sync_engine.dart';

/// Answers each batch with [respond] and records the bodies.
class FakeTransport implements SyncTransport {
  FakeTransport(this.respond);
  ApiResult<Map<String, dynamic>> Function(List<Map<String, Object?>> items) respond;
  final List<List<Map<String, Object?>>> batches = [];

  @override
  Future<ApiResult<Map<String, dynamic>>> postBatch(Map<String, Object?> body) async {
    final items = (body['items']! as List).cast<Map<String, Object?>>();
    batches.add(items);
    return respond(items);
  }
}

ApiResult<Map<String, dynamic>> ok([Map<String, dynamic> body = const {}]) => ApiResult.success(body, statusCode: 200);
ApiResult<Map<String, dynamic>> fail(int code) =>
    ApiResult.failed(ApiFailureClassifier.forStatus(code), statusCode: code);

void main() {
  late AppDatabase db;
  late DateTime now;
  late FakeTransport transport;
  late List<String> logs;
  var session = true;

  SyncEngine engine({int batchSize = 50}) => SyncEngine(
        db: db,
        transport: transport,
        hasSession: () => session,
        clock: () => now,
        batchSize: batchSize,
        log: logs.add,
      );

  Future<void> enqueue(String kind, [Map<String, Object?> payload = const {'x': 1}]) =>
      db.outboxDao.enqueue(kind, payload, now: now);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    now = DateTime.utc(2026, 11, 16, 12);
    transport = FakeTransport((_) => ok());
    logs = [];
    session = true;
  });
  tearDown(() => db.close());

  test('backoff schedule: 15 s doubling, capped at 30 min', () {
    expect([for (var a = 1; a <= 9; a++) SyncEngine.backoffFor(a).inSeconds],
        [15, 30, 60, 120, 240, 480, 960, 1800, 1800]);
    expect(SyncEngine.backoffFor(100), SyncEngine.maxBackoff);
  });

  test('wire format: ordered items with id, kind, payload, created_at', () async {
    await enqueue(SyncKind.gameResult, {'layout_id': 'turtle'});
    await enqueue(SyncKind.layoutUnlock, {'layout_id': 'dragon'});
    await engine().drainNow();
    final items = transport.batches.single;
    expect(items.map((i) => i['kind']), [SyncKind.gameResult, SyncKind.layoutUnlock]);
    expect(items.first.keys, unorderedEquals(['id', 'kind', 'payload', 'created_at']));
    expect(items.first['payload'], {'layout_id': 'turtle'});
    expect(items.first['created_at'], '2026-11-16T12:00:00.000Z');
  });

  test('2xx without lists deletes the whole batch', () async {
    await enqueue(SyncKind.gameResult);
    await enqueue(SyncKind.stats);
    final r = await engine().drainNow();
    expect(r.acknowledged, 2);
    expect(await db.outboxDao.all(), isEmpty);
  });

  test('2xx: accepted deleted, rejected dropped, unmentioned retried', () async {
    await enqueue(SyncKind.gameResult);
    await enqueue(SyncKind.layoutUnlock);
    await enqueue(SyncKind.reset);
    final ids = [for (final r in await db.outboxDao.all()) r.id];
    transport.respond = (_) => ok({
          'accepted': [ids[0]],
          'rejected': [
            {'id': ids[1], 'error': 'unknown layout'},
          ],
        });
    final r = await engine().drainNow();
    expect((r.acknowledged, r.dropped, r.retried), (1, 1, 1));
    final left = await db.outboxDao.all();
    expect(left.single.id, ids[2]);
    expect(left.single.attempts, 1);
    expect(logs.any((l) => l.contains('unknown layout')), isTrue);
  });

  test('daily_result ack marks the entry submitted and verified', () async {
    final repo = DriftProgressRepository(db, clock: () => now);
    await repo.recordResult(GameResult(
      layoutId: 'turtle',
      seed: 1,
      generatorVersion: 1,
      outcome: GameOutcome.cleared,
      timeMs: 1000,
      stars: 3,
      hintsUsed: 0,
      undos: 0,
      shufflesUsed: 0,
      tilesMatched: 144,
      longestStreak: 9,
      playedAt: now,
      dailyDate: '2026-11-16',
      moveLog: 'log',
    ));
    final daily = (await db.outboxDao.all()).firstWhere((r) => r.kind == SyncKind.dailyResult);
    transport.respond = (items) => ok({
          'accepted': [for (final i in items) i['id']],
          'results': {
            daily.id: {'verified': true},
          },
        });
    await engine().drainNow();
    final e = await db.dailyDao.entry('2026-11-16');
    expect((e!.submitted, e.verified), (true, true));
    expect(await db.outboxDao.all(), isEmpty);
  });

  test('404 keeps items without counting attempts, logs once, retries later', () async {
    transport.respond = (_) => fail(404);
    await enqueue(SyncKind.gameResult);
    final e = engine();
    final r = await e.drainNow();
    expect(r.deferred, 1);
    final row = (await db.outboxDao.all()).single;
    expect(row.attempts, 0);
    expect(row.nextAttemptAt.toUtc(), now.add(SyncEngine.notFoundRetry));

    // Not due yet: nothing sent.
    await enqueue(SyncKind.stats);
    await e.drainNow();
    expect(transport.batches.length, 2);
    expect(transport.batches.last.single['kind'], SyncKind.stats);

    now = now.add(const Duration(minutes: 31));
    await e.drainNow();
    expect(logs.where((l) => l.contains('404')).length, 1);
    expect((await db.outboxDao.all()).length, 2);

    transport.respond = (_) => ok();
    now = now.add(const Duration(minutes: 31));
    await e.drainNow();
    expect(await db.outboxDao.all(), isEmpty);
  });

  test('transient failures back off exponentially per item', () async {
    transport.respond = (_) => fail(503);
    await enqueue(SyncKind.gameResult);
    final e = engine();
    final waits = <int>[];
    for (var i = 0; i < 4; i++) {
      await e.drainNow();
      final row = (await db.outboxDao.all()).single;
      waits.add(row.nextAttemptAt.toUtc().difference(now).inSeconds);
      // Before it is due nothing is sent.
      final sent = transport.batches.length;
      await e.drainNow();
      expect(transport.batches.length, sent);
      now = row.nextAttemptAt.toUtc();
    }
    expect(waits, [15, 30, 60, 120]);
    expect((await db.outboxDao.all()).single.attempts, 4);
  });

  test('timeouts and transport errors also back off', () async {
    transport.respond = (_) => ApiResult.failed(ApiFailure.offlineOrTransport);
    await enqueue(SyncKind.gameResult);
    final r = await engine().drainNow();
    expect(r.retried, 1);
    expect((await db.outboxDao.all()).single.attempts, 1);
  });

  test('validation: a bad item in a batch is isolated and dropped, the rest sent', () async {
    await enqueue(SyncKind.gameResult, {'n': 1});
    await enqueue(SyncKind.gameResult, {'n': 2, 'bad': true});
    await enqueue(SyncKind.gameResult, {'n': 3});
    transport.respond = (items) =>
        items.any((i) => (i['payload']! as Map)['bad'] == true) ? fail(422) : ok();
    final r = await engine().drainNow();
    expect((r.acknowledged, r.dropped), (2, 1));
    expect(transport.batches.map((b) => b.length), [3, 1, 1, 1]);
    expect(await db.outboxDao.all(), isEmpty);
    expect(logs.any((l) => l.contains('dropping')), isTrue);
  });

  test('401 keeps items untouched', () async {
    transport.respond = (_) => fail(401);
    await enqueue(SyncKind.gameResult);
    await engine().drainNow();
    final row = (await db.outboxDao.all()).single;
    expect((row.attempts, row.nextAttemptAt.toUtc()), (0, now));
  });

  test('no session: nothing is sent', () async {
    session = false;
    await enqueue(SyncKind.gameResult);
    await engine().drainNow();
    expect(transport.batches, isEmpty);
  });

  test('drains in batches until empty', () async {
    for (var i = 0; i < 5; i++) {
      await enqueue(SyncKind.gameResult, {'n': i});
    }
    await engine(batchSize: 2).drainNow();
    expect(transport.batches.map((b) => b.length), [2, 2, 1]);
    expect(await db.outboxDao.all(), isEmpty);
  });

  test('enqueue triggers a debounced drain after start()', () async {
    final e = SyncEngine(
      db: db,
      transport: transport,
      hasSession: () => true,
      clock: () => now,
      debounce: const Duration(milliseconds: 50),
      maxDefer: const Duration(milliseconds: 200),
      log: logs.add,
    )..start();
    await enqueue(SyncKind.gameResult);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(transport.batches, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(transport.batches.length, 1);
    expect(await db.outboxDao.all(), isEmpty);
    await e.dispose();
  });

  test('concurrent drainNow calls are coalesced', () async {
    final gate = Completer<void>();
    var calls = 0;
    final slow = _SlowTransport(gate, () => calls++);
    await enqueue(SyncKind.gameResult);
    final e = SyncEngine(db: db, transport: slow, hasSession: () => true, clock: () => now, log: logs.add);
    final a = e.drainNow();
    final b = e.drainNow();
    gate.complete();
    await Future.wait([a, b]);
    expect(calls, 1);
  });
}

class _SlowTransport implements SyncTransport {
  _SlowTransport(this.gate, this.onCall);
  final Completer<void> gate;
  final void Function() onCall;

  @override
  Future<ApiResult<Map<String, dynamic>>> postBatch(Map<String, Object?> body) async {
    onCall();
    await gate.future;
    return ApiResult.success(const {}, statusCode: 200);
  }
}
