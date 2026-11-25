import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/progress.dart';
import '../data/models/settings.dart';
import '../platform/analytics/analytics_service.dart';
import '../platform/notifications/notification_service.dart';
import 'app_providers.dart';
import 'data_providers.dart';
import 'platform_providers.dart';
import 'reminder_policy.dart';
import 'store_listing_controller.dart';

/// Title and body for a reminder. main.dart supplies the localised copy
/// (`app_en.arb` → `reminder*`); the default is for tests.
typedef ReminderTexts = ({String title, String body}) Function(ReminderMessage message, int streak);

final reminderTextsProvider = Provider<ReminderTexts>((ref) => (m, streak) => (title: m.name, body: 'streak $streak'));

/// Debug and profile builds only: `--dart-define=JW_REMINDER_DELAY_SECONDS=20`
/// makes the day-1 reminder fire 20 s after the app goes to the background
/// (days 2 and 3 another 20 s apart), skipping the 10:00–20:00 clamp, so a
/// device check takes seconds instead of a day.
const kReminderDebugDelaySeconds = kReleaseMode ? 0 : int.fromEnvironment('JW_REMINDER_DELAY_SECONDS');

/// Whether the OS currently allows notifications. Re-read with
/// `ref.invalidate` (the bridge does on every resume, in case the player
/// changed it in system settings).
final reminderPermissionProvider =
    FutureProvider.autoDispose<bool>((ref) => ref.watch(notificationServiceProvider).hasPermission());

final reminderControllerProvider = Provider<ReminderController>((ref) {
  final c = ReminderController(
    service: ref.watch(notificationServiceProvider),
    analytics: ref.watch(analyticsProvider),
    texts: ref.watch(reminderTextsProvider),
    prefs: () => ref.read(sharedPreferencesProvider),
    // One-shot reads straight from the repositories: a `.future` of a stream
    // provider nobody is watching may never resolve (Riverpod pauses it).
    settings: () => ref.read(settingsRepositoryProvider).read(),
    saveEnabled: (on) => ref.read(settingsProvider.notifier).change((s) => s.copyWith(dailyReminder: on)),
    stats: () => ref.read(statsRepositoryProvider).watch().first,
    daily: () async => (await ref.read(dailyRepositoryProvider.future)).watchToday().first,
    // Another one-time question this app session (the in-app review): the
    // primer waits for a later open.
    otherPromptThisSession: () => ref.read(reviewPrompterProvider).askedThisSession,
    debugDelay: kReminderDebugDelaySeconds > 0 ? Duration(seconds: kReminderDebugDelaySeconds) : null,
  );
  ref.onDispose(c.dispose);
  return c;
});

/// Result of the primer / OS dialog (`reminder_prompt` `result`).
enum ReminderPromptResult { accepted, declined, osDenied }

/// Where the primer was answered (`reminder_prompt` `source`).
enum ReminderPromptSource { home, settings }

/// The daily-board reminder: schedules on background, cancels on open,
/// decides when Home may open the primer, asks the OS only after a yes, and
/// logs `reminder_*` events.
/// Decisions are [ReminderPolicy] / [ReminderPromptPolicy]; this class only
/// gathers their inputs and talks to the [NotificationService].
class ReminderController {
  ReminderController({
    required this.service,
    required this.analytics,
    required this.texts,
    required this.prefs,
    required this.settings,
    required this.saveEnabled,
    required this.stats,
    required this.daily,
    this.otherPromptThisSession,
    this.policy = const ReminderPolicy(),
    this.promptPolicy = const ReminderPromptPolicy(),
    this.debugDelay,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Notification ids of the reminder chain (day 1 … day 3).
  static const baseId = 7101;

  /// SharedPreferences (device-only) for [ReminderAskHistory]: answers so
  /// far, when the last one was given, `boardsCleared` then, and whether
  /// the player said yes / the OS dialog said no.
  static const asksKey = 'reminder.asks';
  static const lastAskKey = 'reminder.lastAskMs';
  static const clearsAtAskKey = 'reminder.clearsAtAsk';
  static const acceptedKey = 'reminder.accepted';
  static const osDeniedKey = 'reminder.osDenied';

  /// The old one-shot cleared-screen ask: true once it was answered (or the
  /// player decided in Settings). Migrated to one answer given at the first
  /// read, so that player gets at most one more ask, 3 days and 3 clears on.
  static const legacyDecidedKey = 'reminder.decided';

  final NotificationService service;
  final AnalyticsService analytics;
  final ReminderTexts texts;
  final SharedPreferences Function() prefs;
  final Future<AppSettings> Function() settings;
  final Future<void> Function(bool on) saveEnabled;
  final Future<PlayerStats> Function() stats;
  final Future<DailyStatus> Function() daily;
  final bool Function()? otherPromptThisSession;
  final ReminderPolicy policy;
  final ReminderPromptPolicy promptPolicy;
  final Duration? debugDelay;
  final DateTime Function() _clock;

  StreamSubscription<String>? _tapSub;
  int _generation = 0;
  bool _primerShownThisSession = false;

  Iterable<int> get _ids => [for (var i = 0; i < policy.maxUnanswered; i++) baseId + i];

  /// Start-up: wires taps, logs a cold launch from a reminder, and clears
  /// whatever is pending (the player is here).
  Future<void> start() async {
    if (!service.isSupported) return;
    await service.init();
    _tapSub ??= service.taps.listen(_logOpen);
    final launch = await service.takeLaunchPayload();
    if (launch != null) _logOpen(launch);
    await onForeground();
  }

  /// The app is in front again: nothing should fire while the player plays.
  Future<void> onForeground() async {
    if (!service.isSupported) return;
    _generation++; // a slow onBackground() must not re-arm after this
    await service.cancel(_ids);
  }

  /// The app went to the background: replace the pending reminders with a
  /// fresh plan (possibly none).
  Future<void> onBackground() async {
    if (!service.isSupported) return;
    final gen = ++_generation;
    try {
      final s = await settings();
      final permitted = s.dailyReminder && await service.hasPermission();
      final st = await stats();
      DailyStatus? d;
      try {
        d = await daily();
      } catch (_) {
        d = null; // no catalogue: generic copy
      }
      final now = _clock();
      var plan = policy.plan(
        now: now,
        enabled: s.dailyReminder,
        permitted: permitted,
        gamesPlayed: st.gamesPlayed,
        streak: d?.streak ?? st.currentStreak,
        clearedToday: d?.clearedToday ?? false,
      );
      final delay = debugDelay;
      if (delay != null) {
        plan = [
          for (final p in plan)
            PlannedReminder(day: p.day, at: now.add(delay * p.day), message: p.message, streak: p.streak),
        ];
      }
      if (gen != _generation) return; // back in front already
      if (plan.isEmpty) {
        await service.cancel(_ids);
        return;
      }
      await service.schedule(
        [
          for (final p in plan)
            () {
              final t = texts(p.message, p.streak);
              return LocalReminder(id: baseId + p.day - 1, at: p.at, title: t.title, body: t.body, payload: p.payload);
            }(),
        ],
        ids: _ids,
      );
      unawaited(analytics.log(AnalyticsEvents.reminderScheduled, {
        'hours_ahead': plan.first.at.difference(now).inMinutes ~/ 60,
        'variant': plan.first.message.name,
      }));
    } catch (e) {
      debugPrint('reminder: scheduling failed: $e');
    }
  }

  void _logOpen(String payload) {
    final p = ReminderPayload.parse(payload);
    if (p == null) return;
    unawaited(analytics.log(AnalyticsEvents.reminderOpen, {'day': p.day, 'variant': p.message.name}));
  }

  /// Taps on a reminder while the app was running (app.dart routes them).
  Stream<ReminderPayload> get taps =>
      service.taps.map(ReminderPayload.parse).where((p) => p != null).cast<ReminderPayload>();

  ReminderAskHistory _history() {
    final p = prefs();
    final last = p.getInt(lastAskKey);
    return ReminderAskHistory(
      asks: p.getInt(asksKey) ?? 0,
      lastAsk: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
      clearsAtLastAsk: p.getInt(clearsAtAskKey) ?? 0,
      closed: (p.getBool(acceptedKey) ?? false) || (p.getBool(osDeniedKey) ?? false),
    );
  }

  Future<void> _migrateLegacy() async {
    final p = prefs();
    if (!(p.getBool(legacyDecidedKey) ?? false)) return;
    if (!p.containsKey(asksKey)) {
      await p.setInt(asksKey, 1);
      await p.setInt(lastAskKey, _clock().millisecondsSinceEpoch);
      await p.setInt(clearsAtAskKey, (await stats()).boardsCleared);
    }
    await p.remove(legacyDecidedKey);
  }

  /// Records one answer (Home or Settings) and returns its ask number.
  Future<int> _recordAsk() async {
    await _migrateLegacy();
    final p = prefs();
    final attempt = (p.getInt(asksKey) ?? 0) + 1;
    await p.setInt(asksKey, attempt);
    await p.setInt(lastAskKey, _clock().millisecondsSinceEpoch);
    try {
      await p.setInt(clearsAtAskKey, (await stats()).boardsCleared);
    } catch (e) {
      debugPrint('reminder: stats read failed: $e');
    }
    return attempt;
  }

  /// Home: the ask number (1 or 2) if the primer may open now, else null.
  /// At most once per app session, and never in the same session as
  /// another one-time question.
  Future<int?> homePromptAttempt() async {
    if (!service.isSupported || _primerShownThisSession) return null;
    try {
      if (otherPromptThisSession?.call() ?? false) return null;
      await _migrateLegacy();
      final s = await settings();
      final st = await stats();
      return promptPolicy.attempt(
        supported: true,
        enabled: s.dailyReminder,
        permitted: await service.hasPermission(),
        boardsCleared: st.boardsCleared,
        history: _history(),
        now: _clock(),
      );
    } catch (e) {
      debugPrint('reminder: prompt check failed: $e');
      return null;
    }
  }

  /// Home is opening the primer: nothing else this session.
  void markPrimerShown() => _primerShownThisSession = true;

  /// Settings, switching the reminder on: the primer goes first unless the
  /// OS already allows notifications or already said no once (then the
  /// switch asks the OS directly and points to the phone's settings).
  Future<bool> settingsNeedsPrimer() async {
    if (!service.isSupported) return false;
    if (prefs().getBool(osDeniedKey) ?? false) return false;
    return !await service.hasPermission();
  }

  /// The player answered the primer: only [accepted] shows the OS dialog.
  Future<ReminderPromptResult> answerPrompt({required bool accepted, required ReminderPromptSource source}) async {
    _primerShownThisSession = true;
    final attempt = await _recordAsk();
    final result = !accepted
        ? ReminderPromptResult.declined
        : await service.requestPermission()
            ? ReminderPromptResult.accepted
            : ReminderPromptResult.osDenied;
    await _recordOutcome(result);
    _logPrompt(result, source, attempt);
    return result;
  }

  Future<void> _recordOutcome(ReminderPromptResult result) async {
    switch (result) {
      case ReminderPromptResult.accepted:
        await prefs().setBool(acceptedKey, true);
        await saveEnabled(true);
      case ReminderPromptResult.osDenied:
        await prefs().setBool(osDeniedKey, true);
      case ReminderPromptResult.declined:
        break;
    }
  }

  /// Settings → Daily reminder, past the primer ([settingsNeedsPrimer]).
  /// Off cancels; on asks the OS when needed and resolves to whether
  /// reminders are now really on.
  Future<bool> setEnabled(bool on) async {
    if (!on) {
      await saveEnabled(false);
      await service.cancel(_ids);
      return false;
    }
    if (await service.hasPermission()) {
      await saveEnabled(true);
      return true;
    }
    final attempt = await _recordAsk();
    final result = await service.requestPermission() ? ReminderPromptResult.accepted : ReminderPromptResult.osDenied;
    await _recordOutcome(result);
    _logPrompt(result, ReminderPromptSource.settings, attempt);
    return result == ReminderPromptResult.accepted;
  }

  void _logPrompt(ReminderPromptResult r, ReminderPromptSource source, int attempt) {
    final result = switch (r) {
      ReminderPromptResult.accepted => 'accepted',
      ReminderPromptResult.declined => 'declined',
      ReminderPromptResult.osDenied => 'os_denied',
    };
    unawaited(analytics.log(AnalyticsEvents.reminderPrompt, {'result': result, 'source': source.name, 'attempt': attempt}));
  }

  void dispose() {
    _tapSub?.cancel();
  }
}
