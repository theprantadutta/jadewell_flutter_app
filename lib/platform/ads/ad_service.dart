/// Where a rewarded ad is offered (docs/ARCHITECTURE.md §7).
enum RewardedPlacement { hint, shuffle, unlockLayout, streakRepair }

/// Rewarded-interstitial offers (shown after an intro sheet with Skip).
enum RewardedInterstitialPlacement { headStart, secondChance }

/// AdMob behind an interface. Phase 8 adds the real implementation; until then
/// the debug implementation simulates ads so the flows can be built and tested.
abstract interface class AdService {
  Future<void> init();

  /// True once the player bought Remove ads (interstitials, app open and
  /// automatic rewarded interstitials stop; opt-in rewarded stays).
  bool get adsRemoved;

  bool isRewardedReady(RewardedPlacement placement);

  /// Shows a rewarded ad. Completes true ONLY if the SDK's reward callback
  /// fired (never on open). Callers grant the reward themselves.
  Future<bool> showRewarded(RewardedPlacement placement);

  Future<bool> showRewardedInterstitial(RewardedInterstitialPlacement placement);

  /// Called when a board is cleared; the implementation's pure gate decides
  /// (frequency cap, first-2-boards rule, ads removed) and may show one.
  Future<void> onBoardCleared({required bool isDaily});
}

/// Debug stand-in: rewarded ads "play" for 600 ms and always reward.
class FakeAdService implements AdService {
  FakeAdService({this.adsRemoved = false});

  @override
  bool adsRemoved;

  @override
  Future<void> init() async {}

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
  Future<void> onBoardCleared({required bool isDaily}) async {}
}
