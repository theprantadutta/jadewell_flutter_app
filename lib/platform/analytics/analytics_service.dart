/// Analytics behind an interface (brief §7). Implementations: no-op,
/// debug-print (debug/profile) and Firebase (release only), swapped via
/// `analyticsProvider`. Never put PII in params.
abstract interface class AnalyticsService {
  Future<void> log(String event, [Map<String, Object> params = const {}]);
  Future<void> screen(String name);
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

  // Daily-board reminder (local notifications, docs/ANALYTICS.md).
  // `notification_open` is reserved by Firebase, hence `reminder_open`.
  static const reminderPrompt = 'reminder_prompt'; // result (accepted / declined / os_denied), source
  static const reminderScheduled = 'reminder_scheduled'; // hours_ahead, message
  static const reminderOpen = 'reminder_open'; // day, message

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
  static const adLoadFailed = 'ad_load_failed'; // format, code
  static const adRevenue = 'ad_revenue'; // format, value_micros, currency, precision
}

class NoOpAnalytics implements AnalyticsService {
  const NoOpAnalytics();
  @override
  Future<void> log(String event, [Map<String, Object> params = const {}]) async {}
  @override
  Future<void> screen(String name) async {}
}
