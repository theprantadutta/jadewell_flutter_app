import 'dart:async';

/// A stream that runs [compute] on listen and again after every event of
/// any [triggers] stream. Runs are serialised; events during a run cause one
/// more run, never a pile-up.
Stream<T> recomputeOn<T>(List<Stream<Object?>> triggers, Future<T> Function() compute) {
  late final StreamController<T> out;
  final subs = <StreamSubscription<Object?>>[];
  var running = false;
  var dirty = false;

  Future<void> run() async {
    if (running) {
      dirty = true;
      return;
    }
    running = true;
    try {
      do {
        dirty = false;
        final value = await compute();
        if (!out.isClosed) out.add(value);
      } while (dirty && !out.isClosed);
    } on Object catch (e, s) {
      if (!out.isClosed) out.addError(e, s);
    } finally {
      running = false;
    }
  }

  out = StreamController<T>(
    onListen: () {
      for (final t in triggers) {
        subs.add(t.listen((_) => unawaited(run()), onError: (Object e, StackTrace s) => out.addError(e, s)));
      }
      unawaited(run());
    },
    onPause: () {
      for (final s in subs) {
        s.pause();
      }
    },
    onResume: () {
      for (final s in subs) {
        s.resume();
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    },
  );
  return out.stream;
}

/// Emits once at every midnight of the clock's day (UTC when [utc], else
/// local time), so day-based read models roll over without a DB change.
Stream<void> midnightTicks(DateTime Function() clock, {required bool utc}) {
  Timer? timer;
  late final StreamController<void> out;

  void schedule() {
    final now = utc ? clock().toUtc() : clock().toLocal();
    final next = utc ? DateTime.utc(now.year, now.month, now.day + 1) : DateTime(now.year, now.month, now.day + 1);
    // +1 s so the tick lands safely inside the new day.
    timer = Timer(next.difference(now) + const Duration(seconds: 1), () {
      out.add(null);
      schedule();
    });
  }

  out = StreamController<void>(
    onListen: schedule,
    onCancel: () => timer?.cancel(),
  );
  return out.stream;
}
