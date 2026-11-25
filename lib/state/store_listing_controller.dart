import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/progress.dart';
import '../platform/display/display_service.dart';
import '../platform/store_listing/store_listing_service.dart';
import 'app_providers.dart';
import 'data_providers.dart';
import 'platform_providers.dart';

// ───────────────────────────── Updates ─────────────────────────────

/// Play's update priority (0–5, set per release through the Play Developer
/// API) from which a launch check runs the blocking full-screen update.
/// Below it, the update downloads in the background and the player restarts
/// when they choose (Settings → App updates, or the toast).
const kImmediateUpdatePriority = 4;

/// Result of Settings → App updates.
enum ManualUpdateResult {
  /// Play's update screen opened, or the update is downloading.
  started,

  /// Already on the latest version.
  upToDate,

  /// The player said no in Play's dialog.
  declined,

  /// Play couldn't answer: not a Play install, no Play Store, or offline.
  unavailable,
}

final appUpdateProvider = NotifierProvider<AppUpdateController, UpdateState>(AppUpdateController.new);

/// Play in-app updates (Android).
///
/// [checkInBackground] runs after start-up and on resume: a priority ≥ 4
/// release opens Play's full-screen update; anything else asks once per
/// session to download in the background. When it's downloaded, Settings
/// shows "Restart to update" and [install] finishes it. Nothing is ever
/// installed without the player tapping.
class AppUpdateController extends Notifier<UpdateState> {
  bool _checking = false;
  bool _promptedThisSession = false;

  StoreListingService get _store => ref.read(storeListingProvider);

  @override
  UpdateState build() => UpdateState.unknown;

  /// Launch / resume check. Safe to call often: it asks at most once per
  /// session and never throws.
  Future<void> checkInBackground() async {
    if (!_store.supportsUpdates || _checking) return;
    _checking = true;
    try {
      final check = await _store.checkForUpdate();
      if (!ref.mounted) return;
      state = check.state;
      if (check.state != UpdateState.available || _promptedThisSession) return;
      _promptedThisSession = true;
      if (check.priority >= kImmediateUpdatePriority && check.immediateAllowed) {
        await _store.startImmediateUpdate();
      } else if (check.flexibleAllowed) {
        await _downloadInBackground();
      }
    } finally {
      _checking = false;
    }
  }

  /// Settings → App updates: check now and act on the answer.
  Future<ManualUpdateResult> checkFromSettings() async {
    if (!_store.supportsUpdates) return ManualUpdateResult.unavailable;
    final check = await _store.checkForUpdate();
    if (!ref.mounted) return ManualUpdateResult.unavailable;
    state = check.state;
    switch (check.state) {
      case UpdateState.downloaded:
        await install();
        return ManualUpdateResult.started;
      case UpdateState.downloading:
        return ManualUpdateResult.started;
      case UpdateState.upToDate:
        return ManualUpdateResult.upToDate;
      case UpdateState.unknown:
        return ManualUpdateResult.unavailable;
      case UpdateState.available:
        _promptedThisSession = true;
        // The player asked for it: the full-screen update is the direct path.
        if (check.immediateAllowed) {
          return switch (await _store.startImmediateUpdate()) {
            UpdateFlowResult.accepted => ManualUpdateResult.started,
            UpdateFlowResult.declined => ManualUpdateResult.declined,
            UpdateFlowResult.failed => ManualUpdateResult.unavailable,
          };
        }
        if (check.flexibleAllowed) {
          unawaited(_downloadInBackground());
          return ManualUpdateResult.started;
        }
        return ManualUpdateResult.unavailable;
    }
  }

  /// Restarts into a downloaded update.
  Future<void> install() => _store.completeFlexibleUpdate();

  Future<void> _downloadInBackground() async {
    state = UpdateState.downloading;
    final r = await _store.startFlexibleUpdate();
    if (!ref.mounted) return;
    state = switch (r) {
      UpdateFlowResult.accepted => UpdateState.downloaded,
      UpdateFlowResult.declined || UpdateFlowResult.failed => UpdateState.available,
    };
  }
}

// ───────────────────────────── Reviews ─────────────────────────────

/// When the in-app review sheet may appear after a cleared board.
///
/// Play and iOS cap how often the sheet really shows, and never say whether
/// it did, so Jadewell keeps its own, stricter rules: only after a good
/// clear (2+ stars), only once the player has cleared [minClears] boards,
/// at most once every [cooldown], and at most [maxAsks] times ever. Settings
/// → Rate Jadewell is always there for anyone who wants to.
class ReviewPolicy {
  const ReviewPolicy({
    this.minClears = 3,
    this.minStars = 2,
    this.cooldown = const Duration(days: 60),
    this.maxAsks = 4,
  });

  final int minClears;
  final int minStars;
  final Duration cooldown;
  final int maxAsks;

  bool shouldAsk({
    required int boardsCleared,
    required int stars,
    required DateTime now,
    required DateTime? lastAsk,
    required int asks,
  }) =>
      boardsCleared >= minClears &&
      stars >= minStars &&
      asks < maxAsks &&
      (lastAsk == null || now.difference(lastAsk) >= cooldown);
}

final reviewPrompterProvider = Provider<ReviewPrompter>(
  (ref) => ReviewPrompter(
    store: ref.watch(storeListingProvider),
    prefs: () => ref.read(sharedPreferencesProvider),
    // A one-shot repository read: `statsProvider.future` may never resolve
    // when nothing is watching the stream, which silently blocked the review
    // prompt and every cleared-screen offer after it.
    stats: () => ref.read(statsRepositoryProvider).watch().first,
  ),
);

class ReviewPrompter {
  ReviewPrompter({
    required this.store,
    required this.prefs,
    required this.stats,
    this.policy = const ReviewPolicy(),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const _lastAskKey = 'review.lastAskMs';
  static const _asksKey = 'review.asks';

  final StoreListingService store;
  final SharedPreferences Function() prefs;
  final Future<PlayerStats> Function() stats;
  final ReviewPolicy policy;
  final DateTime Function() _clock;
  bool _askedThisSession = false;

  /// The review sheet was requested in this app session (other one-time
  /// questions, like the reminder primer, wait for a later open).
  bool get askedThisSession => _askedThisSession;

  /// After a cleared board with [stars]: shows the review sheet when the
  /// policy allows. True when it asked (so the caller stacks nothing on top).
  Future<bool> maybeAskAfterClear({required int stars}) async {
    // No store to review in (tests, demo mode, iOS until it is listed).
    if (_askedThisSession || !store.canOpenStoreListing) return false;
    final prefs = this.prefs();
    final last = prefs.getInt(_lastAskKey);
    final now = _clock();
    final ok = policy.shouldAsk(
      boardsCleared: (await stats()).boardsCleared,
      stars: stars,
      now: now,
      lastAsk: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
      asks: prefs.getInt(_asksKey) ?? 0,
    );
    if (!ok) return false;
    _askedThisSession = true;
    await prefs.setInt(_lastAskKey, now.millisecondsSinceEpoch);
    await prefs.setInt(_asksKey, (prefs.getInt(_asksKey) ?? 0) + 1);
    await store.requestReview();
    return true;
  }
}

// ───────────────────────────── Display ─────────────────────────────

/// The display's rates, for Settings. Re-read with `ref.invalidate`.
final displayRatesProvider = FutureProvider.autoDispose<DisplayRates?>(
  (ref) => ref.watch(displayServiceProvider).read(),
);
