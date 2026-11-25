import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/platform/store_listing/store_listing_service.dart';
import 'package:jadewell_flutter_app/state/app_providers.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/state/reminder_controller.dart';
import 'package:jadewell_flutter_app/state/store_listing_controller.dart';
import 'package:jadewell_flutter_app/ui/screens/home/home_screen.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../state/fake_notifications.dart';
import '../../ui/golden_helpers.dart' show loadJwFonts;
import '../meta_checks.dart';
import 'screen_harness.dart';

GameResult _clear(String id) => GameResult(
      layoutId: id,
      seed: 1,
      generatorVersion: 1,
      outcome: GameOutcome.cleared,
      timeMs: 60000,
      stars: 3,
      hintsUsed: 0,
      undos: 0,
      shufflesUsed: 0,
      tilesMatched: 4,
      longestStreak: 1,
      playedAt: DateTime(2026, 11, 15),
    );

/// A review prompter that reports whether it asked this session.
class _Review extends ReviewPrompter {
  _Review(this.asked, SharedPreferences prefs)
      : super(store: const NoOpStoreListing(), prefs: () => prefs, stats: () async => const PlayerStats());

  final bool asked;

  @override
  bool get askedThisSession => asked;
}

void main() {
  setUpAll(loadJwFonts);

  late SharedPreferences prefs;
  late FakeNotifications notifications;
  late RecordingAnalytics analytics;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    notifications = FakeNotifications();
    analytics = RecordingAnalytics();
  });

  Future<void> pump(
    WidgetTester tester, {
    int clears = 1,
    bool reviewed = false,
    Size size = const Size(390, 844),
  }) async {
    final repo = MemoryProgressRepository();
    for (var i = 0; i < clears; i++) {
      await repo.recordResult(_clear(i == 0 ? 'sprout' : 'pyramid'));
    }
    await pumpScreen(
      tester,
      initial: '/home',
      size: size,
      screens: {'/home': (_) => const HomeScreen()},
      overrides: [
        catalogueRepositoryProvider.overrideWithValue(FakeCatalogueRepository(testCatalogue())),
        progressRepositoryProvider.overrideWithValue(repo),
        statsRepositoryProvider.overrideWithValue(repo),
        dailyProvider.overrideWith(
          (ref) => Stream.value(const DailyStatus(date: '2026-11-15', layoutId: 'lotus', seed: 7)),
        ),
        analyticsProvider.overrideWithValue(analytics),
        adServiceProvider.overrideWithValue(InstantAdService()),
        sharedPreferencesProvider.overrideWithValue(prefs),
        notificationServiceProvider.overrideWithValue(notifications),
        reviewPrompterProvider.overrideWithValue(_Review(reviewed, prefs)),
      ],
    );
    await tester.pump();
  }

  /// Past the 900 ms settle delay and the sheet's entrance.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 950));
    await tester.pumpAndSettle();
  }

  const title = 'Never miss a daily board';

  testWidgets('after the first clear (the warm-up): the primer opens on Home after a settle delay', (tester) async {
    await pump(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(title), findsNothing);
    await settle(tester);
    expect(find.text(title), findsOneWidget);
    for (final t in [
      'A fresh board every day',
      'Keep your streak',
      'Quiet and in your control',
      'Turn on reminders',
      'Not now',
    ]) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(notifications.requests, 0); // the OS dialog only after a yes
  });

  testWidgets('"Not now" closes it without the OS dialog and records the first ask', (tester) async {
    await pump(tester);
    await settle(tester);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text(title), findsNothing);
    expect(notifications.requests, 0);
    expect(prefs.getInt(ReminderController.asksKey), 1);
    expect(
      analytics.events.where((e) => e.$1 == 'reminder_prompt').single.$2,
      {'result': 'declined', 'source': 'home', 'attempt': 1},
    );
  });

  testWidgets('"Turn on reminders" asks the OS and confirms', (tester) async {
    await pump(tester);
    await settle(tester);
    await tester.tap(find.text('Turn on reminders'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(notifications.requests, 1);
    expect(find.text('Daily reminder is on'), findsOneWidget);
    expect(
      analytics.events.where((e) => e.$1 == 'reminder_prompt').single.$2,
      {'result': 'accepted', 'source': 'home', 'attempt': 1},
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
  });

  testWidgets('not before the first clear', (tester) async {
    await pump(tester, clears: 0);
    await settle(tester);
    expect(find.text(title), findsNothing);
  });

  testWidgets('not in a session where the review sheet was requested', (tester) async {
    await pump(tester, reviewed: true);
    await settle(tester);
    expect(find.text(title), findsNothing);
  });

  testWidgets('not when the OS already allows notifications', (tester) async {
    notifications.permitted = true;
    await pump(tester);
    await settle(tester);
    expect(find.text(title), findsNothing);
  });

  testWidgets('not while something is on top of Home', (tester) async {
    await pump(tester);
    unawaited(GoRouter.of(tester.element(find.byType(HomeScreen))).push('/settings'));
    await settle(tester);
    expect(find.text('route:/settings'), findsOneWidget);
    expect(find.text(title), findsNothing);
  });

  testWidgets('after "Not now": not again until 3 days and 3 more clears', (tester) async {
    await prefs.setInt(ReminderController.asksKey, 1);
    await prefs.setInt(ReminderController.lastAskKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(ReminderController.clearsAtAskKey, 1);
    await pump(tester, clears: 5);
    await settle(tester);
    expect(find.text(title), findsNothing);
  });

  for (final size in layoutSizes.entries) {
    for (final scale in textScales) {
      testWidgets('reminder primer · ${size.key} · text ${scale}x: no overflow', (tester) async {
        setTextScale(tester, scale);
        await pump(tester, size: size.value);
        await settle(tester);
        expect(find.text(title), findsOneWidget);
        await expectNoOverflow(tester);
        await tester.ensureVisible(find.text('Not now'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Not now'));
        await tester.pumpAndSettle();
      });
    }
  }
}
