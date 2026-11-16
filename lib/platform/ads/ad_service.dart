/// Where a rewarded ad is offered (docs/ARCHITECTURE.md §7).
enum RewardedPlacement { hint, shuffle, unlockLayout, streakRepair }

/// Rewarded-interstitial offers (shown after an intro sheet with Skip).
enum RewardedInterstitialPlacement { headStart, secondChance }

/// AdMob behind an interface (docs/ADS.md). The real implementation is
/// `ad_service_impl.dart` (main.dart only); [FakeAdService] simulates ads so
/// screens and tests run anywhere.
abstract interface class AdService {
  /// Consent (UMP, then ATT on iOS), SDK start and preloads. Call after the
  /// first frame; never awaited by app start.
  Future<void> init();

  /// True once the player bought Remove ads (interstitials, app open and
  /// automatic rewarded interstitials stop; opt-in rewarded stays).
  bool get adsRemoved;

  /// Fed from the Remove ads entitlement (the IAP layer).
  void setAdsRemoved(bool removed);

  /// UMP says a privacy options entry point must be offered (Settings shows
  /// "Ad privacy choices" only then).
  bool get privacyOptionsRequired;

  /// Shows the UMP privacy options form so the player can change consent.
  Future<void> showPrivacyOptions();

  /// A board is on screen and playable. Cancels an interstitial still
  /// waiting to show for the previous clear, so no ad ever lands mid-board.
  void onBoardStarted();

  bool isRewardedReady(RewardedPlacement placement);

  /// Shows a rewarded ad. Completes true ONLY if the SDK's reward callback
  /// fired (never on open). Callers grant the reward themselves.
  Future<bool> showRewarded(RewardedPlacement placement);

  Future<bool> showRewardedInterstitial(RewardedInterstitialPlacement placement);

  /// Called when a board is cleared; the implementation's pure gate decides
  /// (frequency cap, first-2-boards rule, ads removed) and may show an
  /// interstitial. Completes as soon as the gate has decided: true if an
  /// interstitial will show (shortly after, over the cleared screen; the
  /// cleared screen then skips the "Head start" offer for this board).
  Future<bool> onBoardCleared({required bool isDaily});
}

/// Debug stand-in: rewarded ads "play" for 600 ms and always reward.
class FakeAdService implements AdService {
  FakeAdService({this.adsRemoved = false, this.privacyOptionsRequired = true});

  @override
  bool adsRemoved;

  @override
  bool privacyOptionsRequired;

  /// How many times the privacy options form was "shown".
  int privacyOptionsShown = 0;

  @override
  Future<void> init() async {}

  @override
  void setAdsRemoved(bool removed) => adsRemoved = removed;

  @override
  Future<void> showPrivacyOptions() async => privacyOptionsShown++;

  @override
  void onBoardStarted() {}

  @override
  bool isRewardedReady(RewardedPlacement placement) => true;

  @override
  Future<bool> showRewarded(RewardedPlacement placement) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return true;
  }

  @override
  Future<bool> showRewardedInterstitial(RewardedInterstitialPlacement placement) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    return true;
  }

  @override
  Future<bool> onBoardCleared({required bool isDaily}) async => false;
}
