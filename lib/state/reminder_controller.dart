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
    debugDelay: kReminderDebugDelaySeconds > 0 ? Duration(seconds: kReminderDebugDelaySeconds) : null,
  );
  ref.onDispose(c.dispose);
  return c;
});

/// Result of the soft pre-prompt / OS dialog (`reminder_prompt` `result`).
enum ReminderPromptResult { accepted, declined, osDenied }

/// The daily-board reminder: schedules on background, cancels on open,
/// asks for permission at a good moment, and logs `reminder_*` events.
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
    this.policy = const ReminderPolicy(),
    this.promptPolicy = const ReminderPromptPolicy(),
    this.debugDelay,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Notification ids of the reminder chain (day 1 … day 3).
  static const baseId = 7101;

  /// SharedPreferences: the player answered the pre-prompt (or decided in
  /// Settings), so the cleared screen never asks again. Device-only.
  static const decidedKey = 'reminder.decided';

  final NotificationService service;
  final AnalyticsService analytics;
  final ReminderTexts texts;
  final SharedPreferences Function() prefs;
  final Future<AppSettings> Function() settings;
  final Future<void> Function(bool on) saveEnabled;
  final Future<PlayerStats> Function() stats;
  final Future<DailyStatus> Function() daily;
  final ReminderPolicy policy;
  final ReminderPromptPolicy promptPolicy;
  final Duration? debugDelay;
  final DateTime Function() _clock;

  StreamSubscription<String>? _tapSub;
  int _generation = 0;

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
        'message': plan.first.message.name,
      }));
    } catch (e) {
      debugPrint('reminder: scheduling failed: $e');
    }
  }

  void _logOpen(String payload) {
    final p = ReminderPayload.parse(payload);
    if (p == null) return;
    unawaited(analytics.log(AnalyticsEvents.reminderOpen, {'day': p.day, 'message': p.message.name}));
  }

  /// Taps on a reminder while the app was running (app.dart routes them).
  Stream<ReminderPayload> get taps =>
      service.taps.map(ReminderPayload.parse).where((p) => p != null).cast<ReminderPayload>();

  /// Cleared screen: may the soft pre-prompt appear after this clear?
  Future<bool> shouldOfferPrompt() async {
    if (!service.isSupported) return false;
    try {
      if (prefs().getBool(decidedKey) ?? false) return false;
      final s = await settings();
      final st = await stats();
      return promptPolicy.shouldOffer(
        supported: true,
        alreadyDecided: false,
        enabled: s.dailyReminder,
        permitted: await service.hasPermission(),
        boardsCleared: st.boardsCleared,
      );
    } catch (e) {
      debugPrint('reminder: prompt check failed: $e');
      return false;
    }
  }

  /// The player answered the pre-prompt: [accepted] shows the OS dialog.
  Future<ReminderPromptResult> answerPrompt({required bool accepted}) async {
    await prefs().setBool(decidedKey, true);
    final result = !accepted
        ? ReminderPromptResult.declined
        : await service.requestPermission()
            ? ReminderPromptResult.accepted
            : ReminderPromptResult.osDenied;
    if (result == ReminderPromptResult.accepted) await saveEnabled(true);
    _logPrompt(result, 'cleared');
    return result;
  }

  /// Settings → Daily reminder. Off cancels; on asks the OS when needed and
  /// resolves to whether reminders are now really on.
  Future<bool> setEnabled(bool on) async {
    await prefs().setBool(decidedKey, true);
    if (!on) {
      await saveEnabled(false);
      await service.cancel(_ids);
      return false;
    }
    final had = await service.hasPermission();
    final granted = had || await service.requestPermission();
    if (granted) await saveEnabled(true);
    if (!had) _logPrompt(granted ? ReminderPromptResult.accepted : ReminderPromptResult.osDenied, 'settings');
    return granted;
  }

  void _logPrompt(ReminderPromptResult r, String source) {
    final result = switch (r) {
      ReminderPromptResult.accepted => 'accepted',
      ReminderPromptResult.declined => 'declined',
      ReminderPromptResult.osDenied => 'os_denied',
    };
    unawaited(analytics.log(AnalyticsEvents.reminderPrompt, {'result': result, 'source': source}));
  }

  void dispose() {
    _tapSub?.cancel();
  }
}
