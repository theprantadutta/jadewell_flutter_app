/// Analytics behind an interface (brief §7). Implementations: no-op,
/// debug-print (debug/profile) and Firebase (release only), swapped via
/// `analyticsProvider`. Never put PII in params.
abstract interface class AnalyticsService {
  Future<void> log(String event, [Map<String, Object> params = const {}]);
  Future<void> screen(String name);

  /// Sets (or clears, with null) a user property. Names and values are
  /// sanitised like events (names ≤ 24 chars, values ≤ 36 chars).
  Future<void> setUserProperty(String name, String? value);
}

/// User property names in one place. Each is registered as a user-scoped
/// custom dimension in GA4 (docs/ANALYTICS.md).
abstract final class AnalyticsUserProperties {
  static const account = 'account'; // guest, google, apple
  static const adsRemoved = 'ads_removed'; // 0, 1
  static const onboardingDone = 'onboarding_done'; // 0, 1
  static const theme = 'theme'; // system, light, dark
}

/// Event names in one place so they stay consistent.
abstract final class AnalyticsEvents {
  static const appOpen = 'app_open';
  static const onboardingStep = 'onboarding_step';
  static const onboardingComplete = 'onboarding_complete';
  static const layoutStart = 'layout_start';
  static const boardCleared = 'board_cleared';
  static const boardAbandon = 'board_abandon';
  static const hintUsed = 'hint_used';
  static const undoUsed = 'undo_used';
  static const shuffleUsed = 'shuffle_used';
  static const deadlockShown = 'deadlock_shown';
  static const dailyStart = 'daily_start';
  static const dailyComplete = 'daily_complete';
  static const starsEarned = 'stars_earned';
  static const layoutUnlockAd = 'layout_unlock_ad';
  static const friendAdded = 'friend_added';
  static const streakRepaired = 'streak_repaired';
  static const settingsChanged = 'settings_changed';
  static const accountLinked = 'account_linked';
  static const secondChance = 'second_chance';

  // Remove ads (IAP). iap_error carries a short `code` only.
  static const iapView = 'iap_view';
  static const iapStart = 'iap_start';
  static const iapSuccess = 'iap_success';
  static const iapCancel = 'iap_cancel';
  static const iapPending = 'iap_pending';
  static const iapRestore = 'iap_restore';
  static const iapError = 'iap_error';

  // Ads (docs/ADS.md). `ad_reward` is reserved by Firebase, hence the prefix.
  static const adGate = 'ad_gate'; // trigger, reason: every gate decision
  static const adShown = 'ad_shown'; // format, placement, reason
  static const adReward = 'jw_ad_reward'; // placement, format
  static const adLoadFailed = 'ad_load_failed'; // format, code, message
  static const adRevenue = 'ad_revenue'; // format, value_micros, currency, precision
}

class NoOpAnalytics implements AnalyticsService {
  const NoOpAnalytics();
  @override
  Future<void> log(String event, [Map<String, Object> params = const {}]) async {}
  @override
  Future<void> screen(String name) async {}
  @override
  Future<void> setUserProperty(String name, String? value) async {}
}
