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

  group('pre-prompt', () {
    setUp(() => service.permitted = false);

    test('offered once: declining records the decision without the OS dialog', () async {
      final c = controller();
      expect(await c.shouldOfferPrompt(), isTrue);
      expect(await c.answerPrompt(accepted: false), ReminderPromptResult.declined);
      expect(service.requests, 0);
      expect(await c.shouldOfferPrompt(), isFalse);
      expect(events(AnalyticsEvents.reminderPrompt).single.$2, {'result': 'declined', 'source': 'cleared'});
    });

    test('Yes asks the OS: accepted or os_denied', () async {
      expect(await controller().answerPrompt(accepted: true), ReminderPromptResult.accepted);
      expect(service.requests, 1);
      expect(settings.dailyReminder, isTrue);

      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = FakeNotifications(grantOnRequest: false);
      expect(await controller().answerPrompt(accepted: true), ReminderPromptResult.osDenied);
      expect(events(AnalyticsEvents.reminderPrompt).map((e) => e.$2['result']), ['accepted', 'os_denied']);
    });

    test('not after the 3rd clear, nor when already allowed or switched off', () async {
      stats = const PlayerStats(gamesPlayed: 3, boardsCleared: 3);
      expect(await controller().shouldOfferPrompt(), isFalse);
      stats = const PlayerStats(gamesPlayed: 1, boardsCleared: 1);
      service.permitted = true;
      expect(await controller().shouldOfferPrompt(), isFalse);
      service.permitted = false;
      settings = settings.copyWith(dailyReminder: false);
      expect(await controller().shouldOfferPrompt(), isFalse);
    });
  });

  group('Settings toggle', () {
    test('off saves and cancels; on asks the OS when needed', () async {
      service.permitted = false;
      final c = controller();
      expect(await c.setEnabled(false), isFalse);
      expect(settings.dailyReminder, isFalse);
      expect(service.cancelled.last, [7101, 7102, 7103]);

      expect(await c.setEnabled(true), isTrue);
      expect(service.requests, 1);
      expect(settings.dailyReminder, isTrue);
      expect(events(AnalyticsEvents.reminderPrompt).single.$2, {'result': 'accepted', 'source': 'settings'});
      // Deciding in Settings also retires the cleared-screen ask.
      service.permitted = false;
      expect(await c.shouldOfferPrompt(), isFalse);
    });

    test('on with the OS refusing stays off', () async {
      service = FakeNotifications(grantOnRequest: false);
      settings = settings.copyWith(dailyReminder: false);
      expect(await controller().setEnabled(true), isFalse);
      expect(settings.dailyReminder, isFalse);
    });
  });
}
