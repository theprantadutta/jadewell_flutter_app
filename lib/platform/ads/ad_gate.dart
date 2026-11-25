// The rules for the full-screen ads Jadewell shows on its own initiative
// (docs/ARCHITECTURE.md §7, docs/ADS.md). Pure Dart: no Flutter, no SDK, no
// clock of its own, so every rule is unit-tested (test/platform/ad_gate_test.dart).
//
// Opt-in formats (rewarded, and the rewarded interstitial behind its intro
// sheet) are not gated here: the player asked for them.

/// The four full-screen formats Jadewell uses (no banners, anywhere).
enum AdFormat {
  interstitial('interstitial'),
  rewarded('rewarded'),
  rewardedInterstitial('rewarded_interstitial'),
  appOpen('app_open');

  const AdFormat(this.key);

  /// Analytics value.
  final String key;
}

/// What asked the gate.
enum AdTrigger {
  /// A board was completed (cleared). Restart, abandon, deadlock and leaving
  /// a board never reach the gate: nothing calls it for them.
  boardCleared('board_cleared'),

  /// The app came back to the foreground.
  appResumed('app_resumed');

  const AdTrigger(this.key);
  final String key;
}

/// The tunables, in one place (docs/ADS.md lists them).
class AdGateRules {
  const AdGateRules({
    this.freeBoards = 3,
    this.boardsPerInterstitial = 3,
    this.interstitialMinGap = const Duration(minutes: 4),
    this.fullScreenMinGap = const Duration(minutes: 2),
    this.appOpenMinAway = const Duration(minutes: 30),
    this.appOpenMinGap = const Duration(minutes: 30),
  });

  /// A new install's first N completed boards never get an interstitial
  /// (3: the 40-tile Sprout warm-up is one of them)
  /// (and no app open ad shows before N boards either).
  final int freeBoards;

  /// At most one interstitial per this many completed boards.
  final int boardsPerInterstitial;

  /// Minimum time between two interstitials.
  final Duration interstitialMinGap;

  /// Minimum time between any two full-screen ads (an opt-in rewarded watch
  /// is never chased by an interstitial or app open ad moments later).
  final Duration fullScreenMinGap;

  /// App open: only after this long away, counted from `paused`.
  final Duration appOpenMinAway;

  /// App open: at most one per this interval.
  final Duration appOpenMinGap;
}

/// Counters the gate needs across launches (persisted through [AdGateStore]).
/// Only COMPLETED boards are counted.
class AdGateCounters {
  const AdGateCounters({
    this.completedBoards = 0,
    this.boardsSinceInterstitial = 0,
    this.lastInterstitialMs,
    this.lastFullScreenMs,
  });

  /// Every board this install has completed.
  final int completedBoards;

  /// Completed boards since the last interstitial actually shown.
  final int boardsSinceInterstitial;

  /// Wall-clock ms of the last interstitial shown; null = never.
  final int? lastInterstitialMs;

  /// Wall-clock ms of the last full-screen ad of any format; null = never.
  final int? lastFullScreenMs;

  /// A board was completed: count it (before asking the gate).
  AdGateCounters boardCompleted() => AdGateCounters(
        completedBoards: completedBoards + 1,
        boardsSinceInterstitial: boardsSinceInterstitial + 1,
        lastInterstitialMs: lastInterstitialMs,
        lastFullScreenMs: lastFullScreenMs,
      );

  /// An interstitial was actually shown (not merely decided).
  AdGateCounters interstitialShown(int nowMs) => AdGateCounters(
        completedBoards: completedBoards,
        lastInterstitialMs: nowMs,
        lastFullScreenMs: nowMs,
      );

  /// Any other full-screen ad was shown.
  AdGateCounters fullScreenShown(int nowMs) => AdGateCounters(
        completedBoards: completedBoards,
        boardsSinceInterstitial: boardsSinceInterstitial,
        lastInterstitialMs: lastInterstitialMs,
        lastFullScreenMs: nowMs,
      );

  @override
  bool operator ==(Object other) =>
      other is AdGateCounters &&
      other.completedBoards == completedBoards &&
      other.boardsSinceInterstitial == boardsSinceInterstitial &&
      other.lastInterstitialMs == lastInterstitialMs &&
      other.lastFullScreenMs == lastFullScreenMs;

  @override
  int get hashCode => Object.hash(completedBoards, boardsSinceInterstitial, lastInterstitialMs, lastFullScreenMs);

  @override
  String toString() => 'AdGateCounters(completed: $completedBoards, since: $boardsSinceInterstitial, '
      'lastInterstitial: $lastInterstitialMs, lastFullScreen: $lastFullScreenMs)';
}

/// Where [AdGateCounters] live (SharedPreferences in the app, memory in tests).
abstract interface class AdGateStore {
  AdGateCounters read();
  Future<void> write(AdGateCounters counters);
}

class MemoryAdGateStore implements AdGateStore {
  MemoryAdGateStore([this.counters = const AdGateCounters()]);
  AdGateCounters counters;

  @override
  AdGateCounters read() => counters;

  @override
  Future<void> write(AdGateCounters c) async => counters = c;
}

/// Everything the gate looks at, captured at one moment.
class AdGateContext {
  const AdGateContext({
    required this.trigger,
    required this.nowMs,
    required this.counters,
    this.adsRemoved = false,
    this.adsEnabled = true,
    this.hasUnit = true,
    this.loaded = true,
    this.fullScreenShowing = false,
    this.foreground = true,
    this.isDaily = false,
    this.backgroundedAtMs,
    this.suppressed = false,
    this.lastAppOpenMs,
    this.rules = const AdGateRules(),
  });

  final AdTrigger trigger;
  final int nowMs;

  /// For [AdTrigger.boardCleared]: already including the board just completed.
  final AdGateCounters counters;

  /// Remove ads was bought.
  final bool adsRemoved;

  /// The SDK is initialised and consent allows ad requests (canRequestAds).
  final bool adsEnabled;

  /// A unit id exists for the format (release ids may be left empty).
  final bool hasUnit;

  /// The format's ad is loaded (and, for app open, not expired).
  final bool loaded;

  /// Another full-screen ad is on screen right now.
  final bool fullScreenShowing;

  /// The app is in the foreground.
  final bool foreground;

  /// The completed board was the daily. Dailies are allowed: the interstitial
  /// is shown only after the result screen is up (AdServiceImpl delays it).
  final bool isDaily;

  /// App open: when this background trip began (`paused` only, our own ads
  /// excluded); null = no background trip, e.g. a cold start.
  final int? backgroundedAtMs;

  /// App open: the return was from a flow we started (purchase, consent).
  final bool suppressed;

  /// App open: when the last one showed; null = never.
  final int? lastAppOpenMs;

  final AdGateRules rules;
}

/// The gate's answer: a format to show (or null) and the rule that decided.
typedef AdDecision = ({AdFormat? format, String reason});

/// Reason strings, logged with every decision (`ad_gate` analytics event) and
/// with every ad shown (`ad_shown`).
abstract final class AdGateReason {
  static const shown = 'shown';
  static const adsRemoved = 'ads_removed';
  static const adsOff = 'ads_off'; // no consent, SDK not ready or failed
  static const noUnit = 'no_unit';
  static const firstBoards = 'first_boards';
  static const cadence = 'cadence';
  static const interstitialGap = 'interstitial_gap';
  static const fullScreenGap = 'fullscreen_gap';
  static const adShowing = 'ad_showing';
  static const notForeground = 'not_foreground';
  static const notLoaded = 'not_loaded';
  static const coldStart = 'cold_start'; // no background trip (cold start or a quick inactive blip)
  static const suppressed = 'suppressed';
  static const shortAway = 'short_away';
  static const appOpenGap = 'app_open_gap';

  // Logged by AdServiceImpl after a decision to show, when the show did not happen.
  static const boardStarted = 'board_started'; // the player moved on to a new board first
  static const showFailed = 'show_failed';
}

abstract final class AdGate {
  /// Decides whether the app shows a full-screen ad on its own initiative.
  static AdDecision evaluate(AdGateContext c) => switch (c.trigger) {
        AdTrigger.boardCleared => _interstitial(c),
        AdTrigger.appResumed => _appOpen(c),
      };

  static AdDecision _none(String reason) => (format: null, reason: reason);

  /// Time since [thenMs]; null (never) is "long ago". A negative span means
  /// the device clock went backwards, which must not lock ads out for that
  /// long, so it counts as elapsed too.
  static bool _elapsed(int nowMs, int? thenMs, Duration min) {
    if (thenMs == null) return true;
    final d = nowMs - thenMs;
    return d < 0 || d >= min.inMilliseconds;
  }

  static AdDecision _interstitial(AdGateContext c) {
    final r = c.rules;
    final k = c.counters;
    if (c.adsRemoved) return _none(AdGateReason.adsRemoved);
    if (!c.adsEnabled) return _none(AdGateReason.adsOff);
    if (!c.hasUnit) return _none(AdGateReason.noUnit);
    if (k.completedBoards <= r.freeBoards) return _none(AdGateReason.firstBoards);
    if (k.boardsSinceInterstitial < r.boardsPerInterstitial) return _none(AdGateReason.cadence);
    if (!_elapsed(c.nowMs, k.lastInterstitialMs, r.interstitialMinGap)) return _none(AdGateReason.interstitialGap);
    if (!_elapsed(c.nowMs, k.lastFullScreenMs, r.fullScreenMinGap)) return _none(AdGateReason.fullScreenGap);
    if (c.fullScreenShowing) return _none(AdGateReason.adShowing);
    if (!c.foreground) return _none(AdGateReason.notForeground);
    if (!c.loaded) return _none(AdGateReason.notLoaded);
    return (format: AdFormat.interstitial, reason: AdGateReason.shown);
  }

  static AdDecision _appOpen(AdGateContext c) {
    final r = c.rules;
    if (c.adsRemoved) return _none(AdGateReason.adsRemoved);
    if (!c.adsEnabled) return _none(AdGateReason.adsOff);
    if (!c.hasUnit) return _none(AdGateReason.noUnit);
    final away = c.backgroundedAtMs;
    if (away == null) return _none(AdGateReason.coldStart);
    if (c.suppressed) return _none(AdGateReason.suppressed);
    if (c.counters.completedBoards < r.freeBoards) return _none(AdGateReason.firstBoards);
    final awayMs = c.nowMs - away;
    if (awayMs >= 0 && awayMs < r.appOpenMinAway.inMilliseconds) return _none(AdGateReason.shortAway);
    if (!_elapsed(c.nowMs, c.lastAppOpenMs, r.appOpenMinGap)) return _none(AdGateReason.appOpenGap);
    if (!_elapsed(c.nowMs, c.counters.lastFullScreenMs, r.fullScreenMinGap)) return _none(AdGateReason.fullScreenGap);
    if (c.fullScreenShowing) return _none(AdGateReason.adShowing);
    if (!c.loaded) return _none(AdGateReason.notLoaded);
    return (format: AdFormat.appOpen, reason: AdGateReason.shown);
  }
}
