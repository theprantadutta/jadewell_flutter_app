import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/platform/ads/ad_gate.dart';
import 'package:jadewell_flutter_app/platform/ads/ad_gate_store_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _min = 60 * 1000;
const _t0 = 1800000000000; // a fixed wall clock

/// Counters after [boards] completed boards with no interstitial yet.
AdGateCounters _fresh(int boards) {
  var c = const AdGateCounters();
  for (var i = 0; i < boards; i++) {
    c = c.boardCompleted();
  }
  return c;
}

AdDecision _clear(
  AdGateCounters counters, {
  int now = _t0,
  bool adsRemoved = false,
  bool adsEnabled = true,
  bool hasUnit = true,
  bool loaded = true,
  bool fullScreenShowing = false,
  bool foreground = true,
  bool isDaily = false,
}) =>
    AdGate.evaluate(AdGateContext(
      trigger: AdTrigger.boardCleared,
      nowMs: now,
      counters: counters,
      adsRemoved: adsRemoved,
      adsEnabled: adsEnabled,
      hasUnit: hasUnit,
      loaded: loaded,
      fullScreenShowing: fullScreenShowing,
      foreground: foreground,
      isDaily: isDaily,
    ));

AdDecision _resume(
  AdGateCounters counters, {
  int now = _t0,
  int? backgroundedAt,
  bool adsRemoved = false,
  bool adsEnabled = true,
  bool hasUnit = true,
  bool loaded = true,
  bool suppressed = false,
  bool fullScreenShowing = false,
  int? lastAppOpen,
}) =>
    AdGate.evaluate(AdGateContext(
      trigger: AdTrigger.appResumed,
      nowMs: now,
      counters: counters,
      backgroundedAtMs: backgroundedAt,
      adsRemoved: adsRemoved,
      adsEnabled: adsEnabled,
      hasUnit: hasUnit,
      loaded: loaded,
      suppressed: suppressed,
      fullScreenShowing: fullScreenShowing,
      lastAppOpenMs: lastAppOpen,
    ));

/// Plays [boards] boards through the gate the way AdServiceImpl does (count
/// the board, ask, record the interstitial when one shows), one board every
/// [minutesPerBoard]. Returns the 1-based boards that got an interstitial.
List<int> _simulate(int boards, {int minutesPerBoard = 5, AdGateCounters start = const AdGateCounters()}) {
  var c = start;
  final shown = <int>[];
  for (var i = 1; i <= boards; i++) {
    final now = _t0 + i * minutesPerBoard * _min;
    c = c.boardCompleted();
    if (_clear(c, now: now).format == AdFormat.interstitial) {
      shown.add(i);
      c = c.interstitialShown(now);
    }
  }
  return shown;
}

void main() {
  group('interstitial after a cleared board', () {
    test('never in a new install\'s first 3 completed boards (Sprout is one)', () {
      expect(_clear(_fresh(1)), (format: null, reason: AdGateReason.firstBoards));
      expect(_clear(_fresh(2)), (format: null, reason: AdGateReason.firstBoards));
      expect(_clear(_fresh(3)), (format: null, reason: AdGateReason.firstBoards));
    });

    test('the first one can show on the 4th completed board', () {
      expect(_clear(_fresh(4)), (format: AdFormat.interstitial, reason: AdGateReason.shown));
    });

    test('at most one per 3 completed boards', () {
      final after = _fresh(3).interstitialShown(_t0);
      final later = _t0 + 60 * _min; // far past every time gap
      expect(_clear(after.boardCompleted(), now: later).reason, AdGateReason.cadence);
      expect(_clear(after.boardCompleted().boardCompleted(), now: later).reason, AdGateReason.cadence);
      expect(_clear(after.boardCompleted().boardCompleted().boardCompleted(), now: later).format, AdFormat.interstitial);
    });

    test('at least 4 minutes apart, whatever the board count', () {
      var c = _fresh(3).interstitialShown(_t0);
      for (var i = 0; i < 10; i++) {
        c = c.boardCompleted();
      }
      expect(_clear(c, now: _t0 + 4 * _min - 1).reason, AdGateReason.interstitialGap);
      expect(_clear(c, now: _t0 + 4 * _min).format, AdFormat.interstitial);
    });

    test('no interstitial within 2 minutes of any other full-screen ad (e.g. a rewarded hint)', () {
      final c = _fresh(5).fullScreenShown(_t0);
      expect(_clear(c, now: _t0 + 2 * _min - 1).reason, AdGateReason.fullScreenGap);
      expect(_clear(c, now: _t0 + 2 * _min).format, AdFormat.interstitial);
    });

    test('Remove ads turns it off before any other rule', () {
      expect(_clear(_fresh(10), adsRemoved: true), (format: null, reason: AdGateReason.adsRemoved));
      expect(_clear(_fresh(1), adsRemoved: true).reason, AdGateReason.adsRemoved);
    });

    test('no consent / SDK not ready: off', () {
      expect(_clear(_fresh(10), adsEnabled: false).reason, AdGateReason.adsOff);
    });

    test('no unit id configured: off', () {
      expect(_clear(_fresh(10), hasUnit: false).reason, AdGateReason.noUnit);
    });

    test('not loaded, another ad on screen, or app in the background: nothing', () {
      expect(_clear(_fresh(10), loaded: false).reason, AdGateReason.notLoaded);
      expect(_clear(_fresh(10), fullScreenShowing: true).reason, AdGateReason.adShowing);
      expect(_clear(_fresh(10), foreground: false).reason, AdGateReason.notForeground);
    });

    test('daily boards are allowed (shown after the result, by the service)', () {
      expect(_clear(_fresh(4), isDaily: true).format, AdFormat.interstitial);
    });

    test('rule order: the cheapest, most general reason wins', () {
      // first boards beats not loaded, cadence beats the time gaps
      expect(_clear(_fresh(1), loaded: false).reason, AdGateReason.firstBoards);
      final c = _fresh(3).interstitialShown(_t0).boardCompleted();
      expect(_clear(c, now: _t0 + 1).reason, AdGateReason.cadence);
    });

    test('a clock moved backwards does not lock interstitials out', () {
      final c = _fresh(3).interstitialShown(_t0).boardCompleted().boardCompleted().boardCompleted();
      expect(_clear(c, now: _t0 - 24 * 60 * _min).format, AdFormat.interstitial);
    });

    test('a long session: boards 4, 7, 10… when boards take 5 minutes', () {
      expect(_simulate(12), [4, 7, 10]);
    });

    test('quick boards: the 4-minute gap stretches the cadence', () {
      // a board a minute: board 3 shows; boards 6 (3 min later) is too soon;
      // 7 is exactly 4 minutes later.
      expect(_simulate(12, minutesPerBoard: 1), [4, 8, 12]);
    });
  });

  group('counters', () {
    test('only completed boards count, and an interstitial resets the cadence only', () {
      final c = _fresh(4);
      expect(c.completedBoards, 4);
      expect(c.boardsSinceInterstitial, 4);
      final shown = c.interstitialShown(_t0);
      expect(shown, AdGateCounters(completedBoards: 4, lastInterstitialMs: _t0, lastFullScreenMs: _t0));
      final other = shown.boardCompleted().fullScreenShown(_t0 + 5);
      expect(other, AdGateCounters(completedBoards: 5, boardsSinceInterstitial: 1, lastInterstitialMs: _t0, lastFullScreenMs: _t0 + 5));
    });

    test('survive a restart through SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsAdGateStore(prefs);
      expect(store.read(), const AdGateCounters());
      final c = _fresh(7).interstitialShown(_t0).boardCompleted().fullScreenShown(_t0 + 9);
      await store.write(c);
      expect(SharedPrefsAdGateStore(prefs).read(), c);
    });

    test('memory store round-trips', () async {
      final store = MemoryAdGateStore();
      await store.write(_fresh(2));
      expect(store.read(), _fresh(2));
    });
  });

  group('app open on resume', () {
    final played = _fresh(5);
    const away = _t0 - 31 * _min;

    test('shows after 30+ minutes away', () {
      expect(_resume(played, backgroundedAt: away), (format: AdFormat.appOpen, reason: AdGateReason.shown));
      expect(_resume(played, backgroundedAt: _t0 - 30 * _min).format, AdFormat.appOpen);
    });

    test('never without a background trip: cold start (incl. a first session)', () {
      expect(_resume(played).reason, AdGateReason.coldStart);
      expect(_resume(const AdGateCounters()).reason, AdGateReason.coldStart);
    });

    test('never on a short trip away', () {
      expect(_resume(played, backgroundedAt: _t0 - 30 * _min + 1).reason, AdGateReason.shortAway);
    });

    test('never before the player has completed 3 boards', () {
      expect(_resume(_fresh(2), backgroundedAt: away).reason, AdGateReason.firstBoards);
      expect(_resume(_fresh(3), backgroundedAt: away).format, AdFormat.appOpen);
    });

    test('Remove ads, no consent, no unit id: off', () {
      expect(_resume(played, backgroundedAt: away, adsRemoved: true).reason, AdGateReason.adsRemoved);
      expect(_resume(played, backgroundedAt: away, adsEnabled: false).reason, AdGateReason.adsOff);
      expect(_resume(played, backgroundedAt: away, hasUnit: false).reason, AdGateReason.noUnit);
    });

    test('returning from our own flow (purchase, consent) never shows one', () {
      expect(_resume(played, backgroundedAt: away, suppressed: true).reason, AdGateReason.suppressed);
    });

    test('at most one per 30 minutes', () {
      expect(_resume(played, backgroundedAt: away, lastAppOpen: _t0 - 29 * _min).reason, AdGateReason.appOpenGap);
      expect(_resume(played, backgroundedAt: away, lastAppOpen: _t0 - 30 * _min).format, AdFormat.appOpen);
    });

    test('respects the full-screen gap', () {
      expect(_resume(played.fullScreenShown(_t0 - _min), backgroundedAt: away).reason, AdGateReason.fullScreenGap);
    });

    test('not loaded or another ad showing: nothing', () {
      expect(_resume(played, backgroundedAt: away, loaded: false).reason, AdGateReason.notLoaded);
      expect(_resume(played, backgroundedAt: away, fullScreenShowing: true).reason, AdGateReason.adShowing);
    });
  });

  test('reason strings are distinct analytics values', () {
    const reasons = [
      AdGateReason.shown,
      AdGateReason.adsRemoved,
      AdGateReason.adsOff,
      AdGateReason.noUnit,
      AdGateReason.firstBoards,
      AdGateReason.cadence,
      AdGateReason.interstitialGap,
      AdGateReason.fullScreenGap,
      AdGateReason.adShowing,
      AdGateReason.notForeground,
      AdGateReason.notLoaded,
      AdGateReason.coldStart,
      AdGateReason.suppressed,
      AdGateReason.shortAway,
      AdGateReason.appOpenGap,
      AdGateReason.boardStarted,
      AdGateReason.showFailed,
    ];
    expect(reasons.toSet(), hasLength(reasons.length));
    for (final r in reasons) {
      expect(r, matches(RegExp(r'^[a-z_]{1,40}$')));
    }
  });
}
