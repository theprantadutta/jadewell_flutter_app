import 'dart:async';
import 'dart:math' as math;

import 'package:app_tracking_transparency/app_tracking_transparency.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../analytics/analytics_service.dart';
import 'ad_config.dart';
import 'ad_gate.dart';
import 'ad_service.dart';

/// The interstitial is decided the moment a board clears but shown this much
/// later, so it lands on the cleared screen (the game hands over ~1.3 s after
/// the last match) and never over the board's final animation. A player who
/// moves on to the next board first cancels it ([onBoardStarted]).
const kInterstitialDelay = Duration(milliseconds: 1600);

/// AdMob (docs/ADS.md). Consent first (UMP, then ATT on iOS), fail closed on
/// `canRequestAds()`, then the SDK and staggered preloads with retry backoff.
/// The automatic formats go through the pure [AdGate]; opt-in rewarded ads
/// resolve true only from the SDK's reward callback.
class AdServiceImpl implements AdService {
  AdServiceImpl({
    required this._store,
    required this._analytics,
    this.rules = const AdGateRules(),
    int Function()? clock,
  }) : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final AdGateStore _store;
  final AnalyticsService _analytics;
  final int Function() _clock;
  final AdGateRules rules;

  // ---- tunables ----
  static const _consentTimeout = Duration(seconds: 10);
  static const _onDemandWait = Duration(seconds: 5); // a tapped "watch" button waits this long for a fill
  static const _rewardGrace = Duration(milliseconds: 1000); // earn event arriving after dismiss
  static const _preloadStagger = Duration(milliseconds: 1500);
  static const _retryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 10),
    Duration(seconds: 45),
    Duration(minutes: 3),
    Duration(minutes: 10),
  ];
  static const _expiry = {
    AdFormat.interstitial: Duration(hours: 1),
    AdFormat.rewarded: Duration(hours: 1),
    AdFormat.rewardedInterstitial: Duration(hours: 1),
    AdFormat.appOpen: Duration(hours: 4),
  };

  // Debug-only consent testing (never applied in release):
  //   --dart-define=ADS_DEBUG_GEOGRAPHY=eea --dart-define=ADS_TEST_DEVICE_ID=<hashed id from logcat>
  static const _debugGeography = String.fromEnvironment('ADS_DEBUG_GEOGRAPHY');
  static const _debugDeviceId = String.fromEnvironment('ADS_TEST_DEVICE_ID');

  // ---- state ----
  bool _initStarted = false;
  final Completer<void> _initDone = Completer<void>();
  bool _sdkReady = false;
  Future<void>? _sdkStarting;
  bool _canRequestAds = false;
  bool _consentUpdated = false;
  bool _consentUpdating = false;
  bool _privacyOptionsRequired = false;
  bool _adsRemoved = false;

  AdGateCounters _counters = const AdGateCounters();
  bool _countersLoaded = false;

  final Map<AdFormat, AdWithoutView> _held = {};
  final Map<AdFormat, int> _loadedAtMs = {};
  final Set<AdFormat> _loading = {};
  final Map<AdFormat, int> _attempts = {};
  final Map<AdFormat, Timer> _retryTimers = {};
  final List<Timer> _staggerTimers = [];
  final StreamController<void> _changed = StreamController<void>.broadcast();
  final math.Random _random = math.Random();

  bool _fullScreenShowing = false;
  Timer? _pendingInterstitial;
  bool _boardActive = false;

  AppLifecycleListener? _lifecycle;
  int? _backgroundedAtMs;
  int? _lastAppOpenMs;
  bool _suppressNextAppOpen = false;

  static bool get _supported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);

  /// SDK started and consent allows ad requests.
  bool get _adsEnabled => _sdkReady && _canRequestAds;

  /// Interstitial, app open and automatic rewarded interstitials.
  bool get _automaticOn => _adsEnabled && !_adsRemoved;

  bool get _foreground {
    final s = WidgetsBinding.instance.lifecycleState;
    return s == null || s == AppLifecycleState.resumed;
  }

  // ================================================================ AdService

  @override
  bool get adsRemoved => _adsRemoved;

  @override
  void setAdsRemoved(bool removed) {
    if (removed == _adsRemoved) return;
    _adsRemoved = removed;
    if (removed) {
      _cancelPendingInterstitial();
      for (final f in const [AdFormat.interstitial, AdFormat.appOpen, AdFormat.rewardedInterstitial]) {
        _retryTimers.remove(f)?.cancel();
        _drop(f);
      }
    } else {
      _preloadAll();
    }
  }

  @override
  bool get privacyOptionsRequired => _privacyOptionsRequired;

  @override
  Future<void> showPrivacyOptions() async {
    if (!_supported) return;
    _suppressNextAppOpen = true;
    final done = Completer<void>();
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (error != null) debugPrint('ads: privacy options form failed: ${error.message}');
        if (!done.isCompleted) done.complete();
      });
    } catch (e) {
      debugPrint('ads: privacy options form threw: $e');
      if (!done.isCompleted) done.complete();
    }
    await done.future;
    await _onConsentChanged();
  }

  @override
  Future<void> init() async {
    if (_initStarted) return _initDone.future;
    _initStarted = true;
    try {
      _ensureCounters();
      if (!_supported) return;
      _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
      await _updateConsent();
      await _requestTracking();
      await _refreshCanRequestAds();
      if (_canRequestAds) await _startSdk();
      debugPrint('ads: init done (canRequestAds=$_canRequestAds, sdk=$_sdkReady)');
    } catch (e, st) {
      debugPrint('ads: init failed: $e\n$st');
    } finally {
      if (!_initDone.isCompleted) _initDone.complete();
      _changed.add(null);
    }
  }

  @override
  bool isRewardedReady(RewardedPlacement placement) => _adsEnabled && _fresh(AdFormat.rewarded) != null;

  @override
  Future<bool> showRewarded(RewardedPlacement placement) async {
    final name = _snake(placement.name);
    if (!await _readyForOnDemand()) return false;
    final ad = await _takeOrWait(AdFormat.rewarded) as RewardedAd?;
    if (ad == null) return false;
    return _present<RewardedAd>(
      ad: ad,
      format: AdFormat.rewarded,
      placement: name,
      reason: 'opt_in',
      rewarded: true,
      attach: (cb) => ad.fullScreenContentCallback = cb,
      show: (onEarned) => ad.show(onUserEarnedReward: onEarned),
    );
  }

  @override
  Future<bool> showRewardedInterstitial(RewardedInterstitialPlacement placement) async {
    final name = _snake(placement.name);
    if (!await _readyForOnDemand()) return false;
    // The player accepted the intro sheet: a rewarded video is an equally
    // fair way to deliver the same reward when no rewarded interstitial filled.
    var ri = _fresh(AdFormat.rewardedInterstitial);
    var rv = _fresh(AdFormat.rewarded);
    if (ri == null && rv == null) {
      _load(AdFormat.rewardedInterstitial, force: true);
      _load(AdFormat.rewarded);
      await _waitFor(() => _fresh(AdFormat.rewardedInterstitial) != null || _fresh(AdFormat.rewarded) != null);
      ri = _fresh(AdFormat.rewardedInterstitial);
      rv = _fresh(AdFormat.rewarded);
    }
    if (ri is RewardedInterstitialAd) {
      final ad = ri;
      _held.remove(AdFormat.rewardedInterstitial);
      return _present<RewardedInterstitialAd>(
        ad: ad,
        format: AdFormat.rewardedInterstitial,
        placement: name,
        reason: 'opt_in',
        rewarded: true,
        attach: (cb) => ad.fullScreenContentCallback = cb,
        show: (onEarned) => ad.show(onUserEarnedReward: onEarned),
      );
    }
    if (rv is RewardedAd) {
      final ad = rv;
      _held.remove(AdFormat.rewarded);
      return _present<RewardedAd>(
        ad: ad,
        format: AdFormat.rewarded,
        placement: name,
        reason: 'opt_in',
        rewarded: true,
        attach: (cb) => ad.fullScreenContentCallback = cb,
        show: (onEarned) => ad.show(onUserEarnedReward: onEarned),
      );
    }
    return false;
  }

  @override
  void onBoardStarted() {
    _boardActive = true;
    if (_pendingInterstitial != null) {
      _cancelPendingInterstitial();
      _logGate(AdTrigger.boardCleared, AdGateReason.boardStarted);
    }
    // Warm the formats this board's clear may need.
    _maybeLoadInterstitial();
    _load(AdFormat.rewardedInterstitial);
  }

  @override
  Future<bool> onBoardCleared({required bool isDaily}) async {
    _boardActive = false;
    _ensureCounters();
    _counters = _counters.boardCompleted();
    _save();
    final decision = AdGate.evaluate(AdGateContext(
      trigger: AdTrigger.boardCleared,
      nowMs: _clock(),
      counters: _counters,
      adsRemoved: _adsRemoved,
      adsEnabled: _adsEnabled,
      hasUnit: AdConfig.hasUnit(AdFormat.interstitial),
      loaded: _fresh(AdFormat.interstitial) != null,
      fullScreenShowing: _fullScreenShowing,
      foreground: _foreground,
      isDaily: isDaily,
      rules: rules,
    ));
    _logGate(AdTrigger.boardCleared, decision.reason, daily: isDaily);
    if (decision.format == null) {
      _maybeLoadInterstitial();
      return false;
    }
    _cancelPendingInterstitial();
    _pendingInterstitial = Timer(kInterstitialDelay, () {
      _pendingInterstitial = null;
      unawaited(_showInterstitial(isDaily: isDaily, reason: decision.reason));
    });
    return true;
  }

  // ============================================================ consent + SDK

  /// UMP consent status, showing the form when required. Only the status
  /// request is time-limited (a player reading the form is not a hang); an
  /// answer arriving after the deadline still applies via [_onConsentChanged].
  /// On timeout/failure `canRequestAds()` falls back to the cached status.
  Future<void> _updateConsent() async {
    if (_consentUpdating) return;
    _consentUpdating = true;
    try {
      final answered = Completer<void>();
      final finished = Completer<void>();
      var timedOut = false;
      ConsentInformation.instance.requestConsentInfoUpdate(
        ConsentRequestParameters(consentDebugSettings: _debugConsentSettings()),
        () async {
          if (!answered.isCompleted) answered.complete();
          try {
            await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
              if (error != null) debugPrint('ads: consent form: ${error.message}');
            });
          } catch (e) {
            debugPrint('ads: consent form threw: $e');
          }
          _consentUpdated = true;
          if (!finished.isCompleted) finished.complete();
          if (timedOut) unawaited(_onConsentChanged());
        },
        (FormError error) {
          debugPrint('ads: consent update failed: ${error.message}');
          if (!answered.isCompleted) answered.complete();
          if (!finished.isCompleted) finished.complete();
        },
      );
      await answered.future.timeout(_consentTimeout, onTimeout: () {
        timedOut = true;
        debugPrint('ads: consent update timed out; using the cached status');
        if (!finished.isCompleted) finished.complete();
      });
      await finished.future;
      await _refreshPrivacyOptions();
    } catch (e) {
      debugPrint('ads: consent errored: $e');
    } finally {
      _consentUpdating = false;
    }
  }

  ConsentDebugSettings? _debugConsentSettings() {
    if (kReleaseMode || (_debugGeography.isEmpty && _debugDeviceId.isEmpty)) return null;
    return ConsentDebugSettings(
      debugGeography: switch (_debugGeography) {
        'eea' => DebugGeography.debugGeographyEea,
        'us' => DebugGeography.debugGeographyRegulatedUsState,
        _ => null,
      },
      testIdentifiers: _debugDeviceId.isEmpty ? null : [_debugDeviceId],
    );
  }

  Future<void> _refreshPrivacyOptions() async {
    try {
      final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      _privacyOptionsRequired = status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      _privacyOptionsRequired = false;
    }
  }

  /// iOS App Tracking Transparency, asked once (after the UMP form, which may
  /// already have asked it through its IDFA explainer).
  Future<void> _requestTracking() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    try {
      final status = await AppTrackingTransparency.trackingAuthorizationStatus;
      if (status == TrackingStatus.notDetermined) {
        _suppressNextAppOpen = true;
        await AppTrackingTransparency.requestTrackingAuthorization();
      }
    } catch (e) {
      debugPrint('ads: ATT request failed: $e');
    }
  }

  /// Fail closed: a platform error means no ad requests this session.
  Future<void> _refreshCanRequestAds() async {
    try {
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
    } catch (e) {
      debugPrint('ads: canRequestAds failed, ads off: $e');
      _canRequestAds = false;
    }
  }

  /// Consent was settled late, or changed in the privacy options form.
  Future<void> _onConsentChanged() async {
    await _refreshCanRequestAds();
    await _refreshPrivacyOptions();
    if (_canRequestAds) {
      if (_sdkReady) {
        _rearm();
      } else {
        await _startSdk();
      }
    } else {
      _cancelPendingInterstitial();
      for (final f in AdFormat.values) {
        _retryTimers.remove(f)?.cancel();
        _drop(f);
      }
    }
    _changed.add(null);
  }

  Future<void> _startSdk() => _sdkStarting ??= () async {
        try {
          await MobileAds.instance.updateRequestConfiguration(RequestConfiguration(
            // A calm family-friendly puzzle game: PG ceiling. Child-directed
            // treatment stays unspecified (the app is not directed at children).
            maxAdContentRating: MaxAdContentRating.pg,
            testDeviceIds: (!kReleaseMode && _debugDeviceId.isNotEmpty) ? [_debugDeviceId] : null,
          ));
          await MobileAds.instance.initialize();
          _sdkReady = true;
          _preloadAll();
        } catch (e) {
          debugPrint('ads: SDK start failed: $e');
          _sdkStarting = null;
        }
      }();

  Future<bool> _readyForOnDemand() async {
    if (!_supported) return false;
    if (!_initStarted) unawaited(init());
    if (!_initDone.isCompleted) {
      await _initDone.future.timeout(_onDemandWait, onTimeout: () {});
    }
    return _adsEnabled && !_fullScreenShowing;
  }

  // ================================================================== loading

  /// Requests every format the app may need soon, one at a time (requesting
  /// all at once exhausts the WebView JS engines), opt-in rewarded first.
  /// App open is not here: it is requested on resume, for the next return.
  void _preloadAll() {
    for (final t in _staggerTimers) {
      t.cancel();
    }
    _staggerTimers.clear();
    final steps = <void Function()>[
      () => _load(AdFormat.rewarded),
      () => _load(AdFormat.rewardedInterstitial),
      _maybeLoadInterstitial,
    ];
    for (var i = 0; i < steps.length; i++) {
      _staggerTimers.add(Timer(_preloadStagger * i, steps[i]));
    }
  }

  /// Network back, consent granted: forget exhausted backoffs and reload.
  void _rearm() {
    _attempts.clear();
    for (final t in _retryTimers.values) {
      t.cancel();
    }
    _retryTimers.clear();
    _preloadAll();
  }

  /// The interstitial is only worth holding when the next clear could show it.
  void _maybeLoadInterstitial() {
    _ensureCounters();
    final next = _counters.boardCompleted();
    if (next.completedBoards <= rules.freeBoards) return;
    if (next.boardsSinceInterstitial < rules.boardsPerInterstitial) return;
    _load(AdFormat.interstitial);
  }

  bool _wanted(AdFormat f) => switch (f) {
        AdFormat.rewarded => _adsEnabled,
        _ => _automaticOn,
      };

  /// The held ad for [f] if it has not expired (an expired one is dropped).
  AdWithoutView? _fresh(AdFormat f) {
    final ad = _held[f];
    if (ad == null) return null;
    final age = _clock() - (_loadedAtMs[f] ?? 0);
    if (age >= 0 && age < _expiry[f]!.inMilliseconds) return ad;
    _drop(f);
    return null;
  }

  void _drop(AdFormat f) {
    final ad = _held.remove(f);
    _loadedAtMs.remove(f);
    unawaited(ad?.dispose());
  }

  void _load(AdFormat f, {bool force = false}) {
    if (!_adsEnabled || (!force && !_wanted(f))) return;
    if (_fresh(f) != null || _loading.contains(f)) return;
    final unit = AdConfig.unitId(f);
    if (unit.isEmpty) return;
    _loading.add(f);
    const request = AdRequest();

    void loaded(AdWithoutView ad) {
      _loading.remove(f);
      ad.onPaidEvent = (ad, valueMicros, precision, currencyCode) => _log(AnalyticsEvents.adRevenue, {
            'format': f.key,
            'value_micros': valueMicros.round(),
            'currency': currencyCode,
            'precision': precision.name,
          });
      _held[f] = ad;
      _loadedAtMs[f] = _clock();
      _attempts[f] = 0;
      _retryTimers.remove(f)?.cancel();
      _changed.add(null);
    }

    void failed(LoadAdError e) {
      _loading.remove(f);
      debugPrint('ads: ${f.key} failed to load (${e.code}): ${e.message}');
      _log(AnalyticsEvents.adLoadFailed, {'format': f.key, 'code': e.code});
      _scheduleRetry(f);
      _changed.add(null);
    }

    try {
      switch (f) {
        case AdFormat.interstitial:
          unawaited(InterstitialAd.load(
            adUnitId: unit,
            request: request,
            adLoadCallback: InterstitialAdLoadCallback(onAdLoaded: loaded, onAdFailedToLoad: failed),
          ));
        case AdFormat.rewarded:
          unawaited(RewardedAd.load(
            adUnitId: unit,
            request: request,
            rewardedAdLoadCallback: RewardedAdLoadCallback(onAdLoaded: loaded, onAdFailedToLoad: failed),
          ));
        case AdFormat.rewardedInterstitial:
          unawaited(RewardedInterstitialAd.load(
            adUnitId: unit,
            request: request,
            rewardedInterstitialAdLoadCallback:
                RewardedInterstitialAdLoadCallback(onAdLoaded: loaded, onAdFailedToLoad: failed),
          ));
        case AdFormat.appOpen:
          unawaited(AppOpenAd.load(
            adUnitId: unit,
            request: request,
            adLoadCallback: AppOpenAdLoadCallback(onAdLoaded: loaded, onAdFailedToLoad: failed),
          ));
      }
    } catch (e) {
      _loading.remove(f);
      debugPrint('ads: ${f.key} load threw: $e');
      _scheduleRetry(f);
    }
  }

  /// Backoff with jitter (formats that failed together must not retry on
  /// the same tick). No-fill is routine without mediation; the long tail
  /// lets fill recover later in the session.
  void _scheduleRetry(AdFormat f) {
    if (!_wanted(f)) return;
    final attempt = _attempts[f] ?? 0;
    if (attempt >= _retryDelays.length) return;
    _attempts[f] = attempt + 1;
    _retryTimers.remove(f)?.cancel();
    final d = _retryDelays[attempt] * (0.8 + _random.nextDouble() * 0.6);
    _retryTimers[f] = Timer(d, () {
      _retryTimers.remove(f);
      _load(f);
    });
  }

  /// The held ad for [f], or one loaded within [_onDemandWait]; removed from
  /// the pool (the caller shows it).
  Future<AdWithoutView?> _takeOrWait(AdFormat f) async {
    if (_fresh(f) == null) {
      _attempts[f] = 0; // a tap is a good reason to try now
      _retryTimers.remove(f)?.cancel();
      _load(f, force: true);
      await _waitFor(() => _fresh(f) != null);
    }
    final ad = _fresh(f);
    if (ad != null) _held.remove(f);
    return ad;
  }

  Future<void> _waitFor(bool Function() ready) async {
    if (ready()) return;
    final done = Completer<void>();
    final sub = _changed.stream.listen((_) {
      if (!done.isCompleted && (ready() || !_adsEnabled)) done.complete();
    });
    try {
      await done.future.timeout(_onDemandWait, onTimeout: () {});
    } finally {
      await sub.cancel();
    }
  }

  // ================================================================== showing

  Future<void> _showInterstitial({required bool isDaily, required String reason}) async {
    final ad = _fresh(AdFormat.interstitial);
    if (ad is! InterstitialAd || !_foreground || _fullScreenShowing || !_automaticOn) {
      _logGate(AdTrigger.boardCleared, AdGateReason.showFailed, daily: isDaily);
      _maybeLoadInterstitial();
      return;
    }
    _held.remove(AdFormat.interstitial);
    final shown = await _present<InterstitialAd>(
      ad: ad,
      format: AdFormat.interstitial,
      placement: isDaily ? 'daily_cleared' : 'board_cleared',
      reason: reason,
      attach: (cb) => ad.fullScreenContentCallback = cb,
      show: (_) => ad.show(),
    );
    if (!shown) _logGate(AdTrigger.boardCleared, AdGateReason.showFailed, daily: isDaily);
  }

  /// Shows [ad] and completes once it is gone. For [rewarded] formats the
  /// result is whether the SDK's reward callback fired (granted once; an earn
  /// event that lands after the dismiss is honoured within [_rewardGrace]).
  /// Otherwise, whether the ad was shown.
  Future<bool> _present<T extends AdWithoutView>({
    required T ad,
    required AdFormat format,
    required String placement,
    required String reason,
    required void Function(FullScreenContentCallback<T> callback) attach,
    required Future<void> Function(OnUserEarnedRewardCallback onEarned) show,
    bool rewarded = false,
  }) async {
    final done = Completer<bool>();
    var shown = false;
    var earned = false;
    var dismissed = false;

    void finish(bool value) {
      if (!done.isCompleted) done.complete(value);
    }

    void earn() {
      if (earned) return;
      earned = true;
      _log(AnalyticsEvents.adReward, {'placement': placement, 'format': format.key});
      if (dismissed) finish(true);
    }

    void gone(T ad) {
      _fullScreenShowing = false;
      if (shown) {
        _counters = _counters.fullScreenShown(_clock()); // gaps count from the end of the ad
        _save();
      }
      unawaited(ad.dispose());
      if (format != AdFormat.appOpen) {
        _load(format); // next one; app open is requested on the next resume
      }
    }

    attach(FullScreenContentCallback<T>(
      onAdShowedFullScreenContent: (_) {
        shown = true;
        final now = _clock();
        _counters = format == AdFormat.interstitial ? _counters.interstitialShown(now) : _counters.fullScreenShown(now);
        if (format == AdFormat.appOpen) _lastAppOpenMs = now;
        _save();
        _log(AnalyticsEvents.adShown, {'format': format.key, 'placement': placement, 'reason': reason});
      },
      onAdDismissedFullScreenContent: (ad) {
        dismissed = true;
        gone(ad);
        if (!rewarded || earned) {
          finish(true);
        } else {
          Timer(_rewardGrace, () => finish(earned));
        }
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('ads: ${format.key} failed to show (${error.code}): ${error.message}');
        gone(ad);
        finish(rewarded ? earned : shown);
      },
    ));

    _fullScreenShowing = true;
    try {
      await show((_, _) => earn());
    } catch (e) {
      // show() is a platform call; if it throws, no callback ever arrives.
      debugPrint('ads: ${format.key} show() threw: $e');
      _fullScreenShowing = false;
      unawaited(ad.dispose());
      _load(format);
      finish(false);
    }
    return done.future;
  }

  // ================================================================ app open

  void _onLifecycle(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        // Only a real trip away counts, and its clock starts once: our own
        // full-screen ads also pause the activity.
        if (_fullScreenShowing || _backgroundedAtMs != null) return;
        _backgroundedAtMs = _clock();
      case AppLifecycleState.resumed:
        unawaited(_onResumed());
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  Future<void> _onResumed() async {
    final away = _backgroundedAtMs;
    _backgroundedAtMs = null;
    final suppressed = _suppressNextAppOpen;
    _suppressNextAppOpen = false;
    if (away == null || _fullScreenShowing) return;

    // A launch without network never got a consent answer; ask again, but
    // never over a board in progress (the answer may come with a form).
    if (_initDone.isCompleted && !_consentUpdated && !_boardActive) {
      await _updateConsent();
      if (_consentUpdated) await _onConsentChanged();
    }

    _ensureCounters();
    final decision = AdGate.evaluate(AdGateContext(
      trigger: AdTrigger.appResumed,
      nowMs: _clock(),
      counters: _counters,
      adsRemoved: _adsRemoved,
      adsEnabled: _adsEnabled,
      hasUnit: AdConfig.hasUnit(AdFormat.appOpen),
      loaded: _fresh(AdFormat.appOpen) != null,
      fullScreenShowing: _fullScreenShowing,
      backgroundedAtMs: away,
      suppressed: suppressed,
      lastAppOpenMs: _lastAppOpenMs,
      rules: rules,
    ));
    // Quick app switches are the common case and say nothing; skip them.
    if (decision.reason != AdGateReason.shortAway) _logGate(AdTrigger.appResumed, decision.reason);

    if (decision.format == AdFormat.appOpen) {
      final ad = _held.remove(AdFormat.appOpen);
      if (ad is AppOpenAd) {
        await _present<AppOpenAd>(
          ad: ad,
          format: AdFormat.appOpen,
          placement: 'resume',
          reason: decision.reason,
          attach: (cb) => ad.fullScreenContentCallback = cb,
          show: (_) => ad.show(),
        );
      }
    }

    // Hold one for the next qualifying return (never requested from the
    // background, and not at start-up where it would mostly expire unseen).
    if (_counters.completedBoards >= rules.freeBoards) _load(AdFormat.appOpen);
    // Anything that failed while we were away gets another chance.
    _load(AdFormat.rewarded);
  }

  // ================================================================= helpers

  void _ensureCounters() {
    if (_countersLoaded) return;
    _countersLoaded = true;
    try {
      _counters = _store.read();
    } catch (e) {
      debugPrint('ads: reading gate counters failed: $e');
    }
  }

  void _save() {
    final c = _counters;
    unawaited(_store.write(c).catchError((Object e) => debugPrint('ads: saving gate counters failed: $e')));
  }

  void _cancelPendingInterstitial() {
    _pendingInterstitial?.cancel();
    _pendingInterstitial = null;
  }

  void _logGate(AdTrigger trigger, String reason, {bool? daily}) => _log(AnalyticsEvents.adGate, {
        'trigger': trigger.key,
        'reason': reason,
        if (daily != null) 'daily': daily ? 1 : 0,
      });

  void _log(String event, Map<String, Object> params) {
    unawaited(_analytics.log(event, params).catchError((Object e) => debugPrint('ads: analytics failed: $e')));
  }

  static String _snake(String camel) =>
      camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');

  /// Releases timers, listeners and held ads.
  void dispose() {
    _lifecycle?.dispose();
    _cancelPendingInterstitial();
    for (final t in [..._retryTimers.values, ..._staggerTimers]) {
      t.cancel();
    }
    for (final f in AdFormat.values) {
      _drop(f);
    }
    unawaited(_changed.close());
  }
}
