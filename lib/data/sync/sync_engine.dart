import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart' show TableUpdateQuery, UpdateKind;
import 'package:flutter/foundation.dart' show debugPrint;

import '../api/api_client.dart';
import '../api/api_result.dart';
import '../db/app_database.dart';
import '../db/daos/outbox_dao.dart';

/// Sends one `POST /sync/batch` body. [ApiSyncTransport] in the app, a fake
/// in tests.
abstract interface class SyncTransport {
  Future<ApiResult<Map<String, dynamic>>> postBatch(Map<String, Object?> body);
}

class ApiSyncTransport implements SyncTransport {
  ApiSyncTransport(this._api);
  final ApiClient _api;

  static const path = '/sync/batch';

  @override
  Future<ApiResult<Map<String, dynamic>>> postBatch(Map<String, Object?> body) => _api.post(path, body: body);
}

/// What one drain did (for tests and debug UI).
class SyncDrainReport {
  int sent = 0;
  int acknowledged = 0;
  int dropped = 0;
  int retried = 0;
  int deferred = 0;

  @override
  String toString() =>
      'SyncDrainReport(sent: $sent, acked: $acknowledged, dropped: $dropped, retried: $retried, deferred: $deferred)';
}

/// The only thing that pushes local changes to the backend
/// (docs/ARCHITECTURE.md §3). Drains `sync_outbox` in order to
/// `POST /sync/batch`:
///
/// * 2xx: ids in `accepted` are deleted, ids in `rejected` are dropped
///   (logged), ids in neither retry with backoff. A 2xx without either list
///   acknowledges the whole batch.
/// * 404 (endpoint not deployed yet): items kept, attempts unchanged,
///   retried after [notFoundRetry]; logged once per run.
/// * 401: kept unchanged (the API client re-mints the session).
/// * 400/409/422 for a single item: dropped (logged). For a batch, each
///   item is resent alone to find the bad one.
/// * Transport errors, timeouts, 429, 5xx, 403, unparsable 2xx: attempts
///   +1, next try after [backoffFor] (exponential, capped at [maxBackoff]).
///
/// Triggers: [debounce] after an enqueue (bounded by [maxDefer]), every
/// [periodic], and [drainNow] (app pause/resume, session online). Runs only
/// while [hasSession] is true. Never throws to callers.
class SyncEngine {
  SyncEngine({
    required this._db,
    required this._transport,
    required this._hasSession,
    DateTime Function()? clock,
    this.debounce = const Duration(seconds: 3),
    this.maxDefer = const Duration(seconds: 10),
    this.periodic = const Duration(minutes: 2),
    this.batchSize = 50,
    this.maxBatchesPerDrain = 10,
    void Function(String message)? log,
  })  : _clock = clock ?? DateTime.now,
        _log = log ?? debugPrint;

  final AppDatabase _db;
  final SyncTransport _transport;
  final bool Function() _hasSession;
  final DateTime Function() _clock;
  final void Function(String) _log;

  final Duration debounce;
  final Duration maxDefer;
  final Duration periodic;
  final int batchSize;
  final int maxBatchesPerDrain;

  static const baseBackoff = Duration(seconds: 15);
  static const maxBackoff = Duration(minutes: 30);
  static const notFoundRetry = Duration(minutes: 30);

  /// Delay before the next try after [attempts] failed attempts:
  /// 15 s, 30 s, 1 min, 2 min, … capped at 30 min.
  static Duration backoffFor(int attempts) {
    final n = math.max(attempts, 1) - 1;
    if (n >= 20) return maxBackoff;
    final d = baseBackoff * math.pow(2, n).toInt();
    return d > maxBackoff ? maxBackoff : d;
  }

  OutboxDao get _outbox => _db.outboxDao;

  StreamSubscription<Object?>? _insertSub;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  DateTime? _deadline;
  Future<SyncDrainReport>? _inFlight;
  bool _started = false;
  bool _disposed = false;
  bool _loggedNotFound = false;

  /// Starts the triggers. Idempotent.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _insertSub = _db
        .tableUpdates(TableUpdateQuery.onTable(_db.syncOutboxTable, limitUpdateKind: UpdateKind.insert))
        .listen((_) => _schedule());
    _periodicTimer = Timer.periodic(periodic, (_) => unawaited(drainNow()));
    _schedule();
  }

  /// Debounced drain after a local change.
  void _schedule() {
    if (_disposed) return;
    final now = DateTime.now();
    _deadline ??= now.add(maxDefer);
    var wait = debounce;
    final untilDeadline = _deadline!.difference(now);
    if (untilDeadline < wait) wait = untilDeadline.isNegative ? Duration.zero : untilDeadline;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(wait, () {
      _deadline = null;
      unawaited(drainNow());
    });
  }

  /// Drains now (app pause/resume, session came online). Coalesced with a
  /// drain already running.
  Future<SyncDrainReport> drainNow() {
    if (_disposed) return Future.value(SyncDrainReport());
    return _inFlight ??= _drain().whenComplete(() => _inFlight = null);
  }

  Future<SyncDrainReport> _drain() async {
    final report = SyncDrainReport();
    try {
      for (var i = 0; i < maxBatchesPerDrain; i++) {
        if (_disposed || !_hasSession()) break;
        final items = await _outbox.due(_clock(), limit: batchSize);
        if (items.isEmpty) break;
        final keepGoing = await _sendBatch(items, report);
        if (!keepGoing || items.length < batchSize) break;
      }
    } on Object catch (e) {
      _log('sync: drain failed: $e');
    }
    return report;
  }

  static Map<String, Object?> _wire(OutboxRow r) => {
        'id': r.id,
        'kind': r.kind,
        'payload': jsonDecode(r.payload),
        'created_at': r.createdAt.toUtc().toIso8601String(),
      };

  /// Returns whether the drain may continue with the next batch.
  Future<bool> _sendBatch(List<OutboxRow> items, SyncDrainReport report) async {
    report.sent += items.length;
    final res = await _transport.postBatch({'items': items.map(_wire).toList()});
    final now = _clock();

    if (res.isSuccess) {
      await _applyAck(items, res.value ?? const {}, now, report);
      return true;
    }
    if (res.statusCode == 404) {
      if (!_loggedNotFound) {
        _loggedNotFound = true;
        _log('sync: /sync/batch not found (404); keeping ${items.length} item(s), will retry later');
      }
      await _outbox.defer(items.map((r) => r.id), now.add(notFoundRetry));
      report.deferred += items.length;
      return false;
    }
    if (res.failure == ApiFailure.unauthorized) return false;
    if (res.failure == ApiFailure.validation) {
      if (items.length == 1) {
        _log('sync: dropping ${items.single.kind} ${items.single.id}: rejected (${res.statusCode} ${res.message ?? ''})');
        await _outbox.deleteIds([items.single.id]);
        report.dropped++;
        return true;
      }
      // Isolate the bad item(s): resend one by one.
      report.sent -= items.length;
      for (final item in items) {
        if (!await _sendBatch([item], report)) return false;
      }
      return true;
    }
    // Transient (or forbidden / unparsable): back off per item.
    for (final r in items) {
      await _outbox.markFailed(r, now.add(backoffFor(r.attempts + 1)));
    }
    report.retried += items.length;
    _log('sync: batch failed (${res.failure?.name}, ${res.statusCode}); retrying ${items.length} item(s) with backoff');
    return false;
  }

  Future<void> _applyAck(List<OutboxRow> items, Map<String, dynamic> body, DateTime now, SyncDrainReport report) async {
    final sentIds = {for (final r in items) r.id};
    final acceptedRaw = body['accepted'];
    final rejectedRaw = body['rejected'];

    final Set<String> accepted;
    final rejected = <String, String?>{};
    if (acceptedRaw == null && rejectedRaw == null) {
      accepted = sentIds;
    } else {
      accepted = {
        if (acceptedRaw is List)
          for (final id in acceptedRaw)
            if (id is String && sentIds.contains(id)) id,
      };
      if (rejectedRaw is List) {
        for (final e in rejectedRaw) {
          if (e is String && sentIds.contains(e)) rejected[e] = null;
          if (e is Map && e['id'] is String && sentIds.contains(e['id'])) {
            rejected[e['id'] as String] = e['error']?.toString();
          }
        }
      }
    }
    final results = body['results'];

    await _db.transaction(() async {
      for (final r in items) {
        if (accepted.contains(r.id) && r.kind == SyncKind.dailyResult) {
          final payload = jsonDecode(r.payload);
          final date = payload is Map ? payload['date'] : null;
          final result = results is Map ? results[r.id] : null;
          final verified = result is Map && result['verified'] is bool ? result['verified'] as bool : null;
          if (date is String) await _db.dailyDao.markSubmitted(date, verified: verified);
        }
      }
      await _outbox.deleteIds({...accepted, ...rejected.keys});
      for (final r in items) {
        if (!accepted.contains(r.id) && !rejected.containsKey(r.id)) {
          await _outbox.markFailed(r, now.add(backoffFor(r.attempts + 1)));
          report.retried++;
        }
      }
    });
    for (final e in rejected.entries) {
      final kind = items.firstWhere((r) => r.id == e.key).kind;
      _log('sync: dropping $kind ${e.key}: rejected${e.value == null ? '' : ' (${e.value})'}');
    }
    report.acknowledged += accepted.length;
    report.dropped += rejected.length;
  }

  Future<void> dispose() async {
    _disposed = true;
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    await _insertSub?.cancel();
  }
}
