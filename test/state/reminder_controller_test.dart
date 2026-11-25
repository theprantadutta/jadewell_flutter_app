import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/models/settings.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/state/reminder_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/settings/harness.dart' show RecordingAnalytics;
import 'fake_notifications.dart';

void main() {
  late FakeNotifications service;
  late RecordingAnalytics analytics;
  late SharedPreferences prefs;
  late AppSettings settings;
  late PlayerStats stats;
  late DailyStatus daily;
  var now = DateTime(2026, 11, 25, 21, 40);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    service = FakeNotifications(permitted: true);
    analytics = RecordingAnalytics();
    settings = const AppSettings();
    stats = const PlayerStats(gamesPlayed: 2, boardsCleared: 1);
    daily = const DailyStatus(date: '2026-11-25', layoutId: 'turtle', seed: 1);
    now = DateTime(2026, 11, 25, 21, 40);
  });

  ReminderController controller({Duration? debugDelay}) => ReminderController(
        service: service,
        analytics: analytics,
        texts: (m, streak) => (title: 'T:${m.name}:$streak', body: 'B:${m.name}'),
        prefs: () => prefs,
        settings: () async => settings,
        saveEnabled: (on) async => settings = settings.copyWith(dailyReminder: on),
        stats: () async => stats,
        daily: () async => daily,
        debugDelay: debugDelay,
        clock: () => now,
      );

  List<(String, Map<String, Object>)> events(String name) => [for (final e in analytics.events) if (e.$1 == name) e];

  test('background schedules the 3-day chain with the clamped time and copy; foreground cancels it', () async {
    daily = const DailyStatus(date: '2026-11-25', layoutId: 'turtle', seed: 1, firstClearMs: 90000, streak: 4);
    final c = controller();
    await c.onBackground();
    expect(service.pending.map((r) => r.id), [7101, 7102, 7103]);
    expect(service.pending.map((r) => r.at), [
      DateTime(2026, 11, 26, 20), // 21:40 + 24 h is past 20:00
      DateTime(2026, 11, 27, 20),
      DateTime(2026, 11, 28, 20),
    ]);
    expect(service.pending.first.title, 'T:streak:4');
    expect(service.pending.first.payload, 'reminder:1:streak');
    expect(service.pending[1].title, 'T:comeback:4');
    expect(events(AnalyticsEvents.reminderScheduled).single.$2, {'hours_ahead': 22, 'variant': 'streak'});

    // Re-scheduling replaces, never adds.
    await c.onBackground();
    expect(service.pending, hasLength(3));

    await c.onForeground();
    expect(service.pending, isEmpty);
    expect(service.cancelled.last, [7101, 7102, 7103]);
  });

  test('nothing is scheduled without permission, with the setting off, or before the first board', () async {
    service.permitted = false;
    await controller().onBackground();
    expect(service.pending, isEmpty);

    service.permitted = true;
    settings = settings.copyWith(dailyReminder: false);
    await controller().onBackground();
    expect(service.pending, isEmpty);

    settings = settings.copyWith(dailyReminder: true);
    stats = const PlayerStats();
    await controller().onBackground();
    expect(service.pending, isEmpty);
    expect(events(AnalyticsEvents.reminderScheduled), isEmpty);
  });

  test('coming back before the schedule finished leaves nothing armed', () async {
    final c = controller();
    final pending = c.onBackground();
    await c.onForeground();
    await pending;
    expect(service.pending, isEmpty);
  });

  test('debug delay fires the chain seconds apart', () async {
    await controller(debugDelay: const Duration(seconds: 20)).onBackground();
    expect(service.pending.map((r) => r.at.difference(now).inSeconds), [20, 40, 60]);
  });

  test('a cold launch or a tap from a reminder logs reminder_open', () async {
    service.launchPayload = 'reminder:2:comeback';
    final c = controller();
    await c.start();
    expect(events(AnalyticsEvents.reminderOpen).single.$2, {'day': 2, 'variant': 'comeback'});
    service.tapController.add('reminder:1:daily');
    service.tapController.add('something else');
    await Future<void>.delayed(Duration.zero);
    expect(events(AnalyticsEvents.reminderOpen).last.$2, {'day': 1, 'variant': 'daily'});
    expect(events(AnalyticsEvents.reminderOpen), hasLength(2));
    c.dispose();
  });

  group('primer', () {
    setUp(() => service.permitted = false);

    test('first ask after a clear; "Not now" records it without the OS dialog', () async {
      final c = controller();
      expect(await c.homePromptAttempt(), 1);
      expect(await c.answerPrompt(accepted: false, source: ReminderPromptSource.home), ReminderPromptResult.declined);
      expect(service.requests, 0);
      expect(prefs.getInt(ReminderController.asksKey), 1);
      expect(prefs.getInt(ReminderController.lastAskKey), now.millisecondsSinceEpoch);
      expect(prefs.getInt(ReminderController.clearsAtAskKey), 1);
      expect(events(AnalyticsEvents.reminderPrompt).single.$2, {'result': 'declined', 'source': 'home', 'attempt': 1});
    });

    test('second ask: 3 days and 3 clears after "Not now", then never again', () async {
      await controller().answerPrompt(accepted: false, source: ReminderPromptSource.home);
      now = now.add(const Duration(days: 3));
      expect(await controller().homePromptAttempt(), isNull); // no new clears yet
      stats = const PlayerStats(gamesPlayed: 5, boardsCleared: 4);
      final c = controller();
      expect(await c.homePromptAttempt(), 2);
      await c.answerPrompt(accepted: false, source: ReminderPromptSource.home);
      expect(events(AnalyticsEvents.reminderPrompt).last.$2['attempt'], 2);
      now = now.add(const Duration(days: 60));
      stats = const PlayerStats(gamesPlayed: 50, boardsCleared: 40);
      expect(await controller().homePromptAttempt(), isNull);
    });

    test('at most once per app session', () async {
      final c = controller();
      c.markPrimerShown();
      expect(await c.homePromptAttempt(), isNull);
      expect(await controller().homePromptAttempt(), 1);
    });

    test('waits when the review sheet was requested this session', () async {
      var reviewed = true;
      final c = ReminderController(
        service: service,
        analytics: analytics,
        texts: (m, streak) => (title: '', body: ''),
        prefs: () => prefs,
        settings: () async => settings,
        saveEnabled: (on) async {},
        stats: () async => stats,
        daily: () async => daily,
        otherPromptThisSession: () => reviewed,
        clock: () => now,
      );
      expect(await c.homePromptAttempt(), isNull);
      reviewed = false;
      expect(await c.homePromptAttempt(), 1);
    });

    test('yes asks the OS: accepted closes it; os_denied closes it too', () async {
      expect(await controller().answerPrompt(accepted: true, source: ReminderPromptSource.home), ReminderPromptResult.accepted);
      expect(service.requests, 1);
      expect(settings.dailyReminder, isTrue);
      expect(prefs.getBool(ReminderController.acceptedKey), isTrue);

      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = FakeNotifications(grantOnRequest: false);
      expect(await controller().answerPrompt(accepted: true, source: ReminderPromptSource.home), ReminderPromptResult.osDenied);
      expect(prefs.getBool(ReminderController.osDeniedKey), isTrue);
      now = now.add(const Duration(days: 30));
      stats = const PlayerStats(gamesPlayed: 20, boardsCleared: 20);
      expect(await controller().homePromptAttempt(), isNull);
      expect(await controller().settingsNeedsPrimer(), isFalse); // Settings asks the OS directly now
      expect(events(AnalyticsEvents.reminderPrompt).map((e) => e.$2['result']), ['accepted', 'os_denied']);
    });

    test('not before the first clear, nor when already allowed or switched off', () async {
      stats = const PlayerStats(gamesPlayed: 1);
      expect(await controller().homePromptAttempt(), isNull);
      stats = const PlayerStats(gamesPlayed: 1, boardsCleared: 1);
      service.permitted = true;
      expect(await controller().homePromptAttempt(), isNull);
      service.permitted = false;
      settings = settings.copyWith(dailyReminder: false);
      expect(await controller().homePromptAttempt(), isNull);
    });

    test('an answered old cleared-screen ask counts as the first answer', () async {
      await prefs.setBool(ReminderController.legacyDecidedKey, true);
      expect(await controller().homePromptAttempt(), isNull);
      expect(prefs.getInt(ReminderController.asksKey), 1);
      expect(prefs.containsKey(ReminderController.legacyDecidedKey), isFalse);
      now = now.add(const Duration(days: 3));
      stats = const PlayerStats(gamesPlayed: 4, boardsCleared: 4);
      expect(await controller().homePromptAttempt(), 2);
    });
  });

  group('Settings toggle', () {
    test('primer first only while the OS permission is missing', () async {
      service.permitted = false;
      expect(await controller().settingsNeedsPrimer(), isTrue);
      service.permitted = true;
      expect(await controller().settingsNeedsPrimer(), isFalse);
    });

    test('"Not now" from Settings counts as an answer', () async {
      service.permitted = false;
      await controller().answerPrompt(accepted: false, source: ReminderPromptSource.settings);
      expect(events(AnalyticsEvents.reminderPrompt).single.$2, {'result': 'declined', 'source': 'settings', 'attempt': 1});
      expect(await controller().homePromptAttempt(), isNull);
    });

    test('off saves and cancels; on with permission just saves', () async {
      final c = controller();
      expect(await c.setEnabled(false), isFalse);
      expect(settings.dailyReminder, isFalse);
      expect(service.cancelled.last, [7101, 7102, 7103]);
      expect(await c.setEnabled(true), isTrue);
      expect(service.requests, 0);
      expect(settings.dailyReminder, isTrue);
      expect(events(AnalyticsEvents.reminderPrompt), isEmpty);
    });

    test('after an OS refusal: asks the OS directly and stays off if it refuses again', () async {
      service = FakeNotifications(grantOnRequest: false);
      await prefs.setBool(ReminderController.osDeniedKey, true);
      settings = settings.copyWith(dailyReminder: false);
      expect(await controller().setEnabled(true), isFalse);
      expect(service.requests, 1);
      expect(settings.dailyReminder, isFalse);
      expect(events(AnalyticsEvents.reminderPrompt).single.$2, {'result': 'os_denied', 'source': 'settings', 'attempt': 1});
    });
  });
}
