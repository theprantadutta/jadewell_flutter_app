import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming, PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// The frame budget Jadewell is held to: 60 fps (docs/PERFORMANCE.md).
/// Displays running faster (90/120 Hz) are the player's choice; frames are
/// judged against 16.7 ms either way.
const kFrameBudgetUs = 16667;

/// Collects [FrameTiming]s per named segment (one screen or one board of the
/// demo) and prints a one-line summary to the log, tagged `JWPERF`, that
/// `tool/perf/profile.sh` collects:
///
/// `JWPERF seg=game:turtle frames=812 build_p50=2.1 build_p90=3.4 build_p99=6.0 build_max=9.8
///  raster_p50=3.0 ... over_budget=0 (0.0%) severe=0`
///
/// A frame is "over budget" when its build (UI thread) or raster (GPU
/// thread) phase took longer than 16.7 ms, i.e. it would miss a 60 Hz vsync.
/// "Severe" is over 33 ms (two vsyncs or more).
class FrameStats {
  FrameStats._();

  static final instance = FrameStats._();

  String? _segment;
  final _build = <int>[];
  final _raster = <int>[];
  int _over = 0;
  int _severe = 0;
  int _segStartUs = 0;
  final _all = <String, _Summary>{};
  bool _listening = false;

  void _start() {
    if (_listening) return;
    _listening = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    final display = PlatformDispatcher.instance.displays.firstOrNull;
    debugPrint('JWPERF display refresh=${display?.refreshRate.toStringAsFixed(1)}Hz '
        'size=${display?.size.width.round()}x${display?.size.height.round()} budget=16.7ms');
  }

  /// Starts measuring [name], closing (and printing) the current segment.
  void begin(String name) {
    _start();
    end();
    _segment = name;
    _build.clear();
    _raster.clear();
    _over = 0;
    _severe = 0;
    _segStartUs = 0;
  }

  /// Prints and closes the current segment.
  void end() {
    final seg = _segment;
    if (seg == null) return;
    _segment = null;
    if (_build.isEmpty) return;
    final s = _Summary.of(_build, _raster, _over, _severe);
    _all.update(seg.split(':').first, (old) => old.merge(s), ifAbsent: () => s);
    debugPrint('JWPERF seg=$seg ${s.line}');
  }

  /// Prints a summary per segment kind (home, game, cleared, …) so far.
  void report(String label) {
    end();
    for (final MapEntry(:key, :value) in _all.entries) {
      debugPrint('JWPERF total=$label kind=$key ${value.line}');
    }
  }

  void _onTimings(List<FrameTiming> timings) {
    if (_segment == null) return;
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds, r = t.rasterDuration.inMicroseconds;
      _build.add(b);
      _raster.add(r);
      final worst = math.max(b, r);
      final at = t.timestampInMicroseconds(FramePhase.vsyncStart);
      if (_segStartUs == 0) _segStartUs = at;
      if (worst > kFrameBudgetUs) {
        _over++;
        debugPrint('JWPERF slow seg=$_segment frame=${_build.length} at=+${(at - _segStartUs) ~/ 1000}ms '
            'build=${(b / 1000).toStringAsFixed(1)} raster=${(r / 1000).toStringAsFixed(1)}');
      }
      if (worst > 2 * kFrameBudgetUs) _severe++;
    }
  }
}

class _Summary {
  _Summary(this.build, this.raster, this.over, this.severe);

  factory _Summary.of(List<int> build, List<int> raster, int over, int severe) =>
      _Summary([...build]..sort(), [...raster]..sort(), over, severe);

  final List<int> build;
  final List<int> raster;
  final int over;
  final int severe;

  _Summary merge(_Summary o) =>
      _Summary([...build, ...o.build]..sort(), [...raster, ...o.raster]..sort(), over + o.over, severe + o.severe);

  String get line {
    final n = build.length;
    final pct = (100 * over / n).toStringAsFixed(1);
    String ms(int us) => (us / 1000).toStringAsFixed(1);
    String p(List<int> xs, double q) => ms(xs[math.min(xs.length - 1, (q * xs.length).floor())]);
    return 'frames=$n '
        'build_p50=${p(build, .5)} build_p90=${p(build, .9)} build_p99=${p(build, .99)} build_max=${ms(build.last)} '
        'raster_p50=${p(raster, .5)} raster_p90=${p(raster, .9)} raster_p99=${p(raster, .99)} raster_max=${ms(raster.last)} '
        'over_budget=$over ($pct%) severe=$severe';
  }
}
