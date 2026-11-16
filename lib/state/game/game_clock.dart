/// The board clock. The engine never reads time; the controller owns one of
/// these and passes `elapsedMs` into every command.
abstract interface class GameClock {
  /// Elapsed board time in ms (only counts while running).
  int get elapsedMs;
  bool get isRunning;
  void start();
  void stop();

  /// Sets the elapsed time (resume from a saved game, restart) and stops.
  void reset([int elapsedMs = 0]);
}

/// [Stopwatch]-backed clock used in the app.
class StopwatchGameClock implements GameClock {
  final Stopwatch _watch = Stopwatch();
  int _base = 0;

  @override
  int get elapsedMs => _base + _watch.elapsedMilliseconds;

  @override
  bool get isRunning => _watch.isRunning;

  @override
  void start() => _watch.start();

  @override
  void stop() => _watch.stop();

  @override
  void reset([int elapsedMs = 0]) {
    _watch
      ..stop()
      ..reset();
    _base = elapsedMs;
  }
}

/// Manually advanced clock for tests: time passes only through [advance],
/// and only while running.
class FakeGameClock implements GameClock {
  int _elapsed = 0;
  bool _running = false;

  @override
  int get elapsedMs => _elapsed;

  @override
  bool get isRunning => _running;

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;

  @override
  void reset([int elapsedMs = 0]) {
    _running = false;
    _elapsed = elapsedMs;
  }

  /// Moves time forward by [ms] if the clock is running.
  void advance(int ms) {
    if (_running) _elapsed += ms;
  }
}
