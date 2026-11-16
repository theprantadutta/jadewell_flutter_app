import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/repositories/repositories.dart';
import 'package:jadewell_flutter_app/platform/ads/ad_service.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/daily/countdown.dart';
import 'package:jadewell_flutter_app/ui/screens/daily/daily_screen.dart';
import 'package:jadewell_flutter_app/ui/screens/daily/daily_top_three.dart';
import 'package:jadewell_flutter_app/ui/screens/home/layout_labels.dart' show formatClock;
import 'package:material_ui/material_ui.dart' show ValueKey;

import '../../ui/golden_helpers.dart' show loadJwFonts;
import '../home/screen_harness.dart';

void main() {
  setUpAll(loadJwFonts);

  group('countdown', () {
    test('formats H:MM:SS with unpadded hours', () {
      expect(formatCountdown(const Duration(hours: 1, minutes: 15, seconds: 7)), '1:15:07');
      expect(formatCountdown(const Duration(hours: 23, minutes: 59, seconds: 59)), '23:59:59');
      expect(formatCountdown(const Duration(seconds: 5)), '0:00:05');
      expect(formatCountdown(const Duration(seconds: -3)), '0:00:00');
    });

    test('counts down to the next UTC midnight', () {
      expect(untilNextUtcMidnight(DateTime.utc(2026, 11, 15, 22, 44, 53)), const Duration(hours: 1, minutes: 15, seconds: 7));
      expect(untilNextUtcMidnight(DateTime.utc(2026, 12, 31)), const Duration(days: 1));
      // A local time is converted first.
      final local = DateTime.utc(2026, 11, 15, 12).toLocal();
      expect(untilNextUtcMidnight(local), const Duration(hours: 12));
    });

    test('best-time clock format', () {
      expect(formatClock(228000), '3:48');
      expect(formatClock(662000), '11:02');
      expect(formatClock(3723000), '1:02:03');
    });
  });

  Future<void> pumpDaily(
    WidgetTester tester,
    DailyStatus status, {
    List<DailyTopEntry> top = const [],
    _FakeDailyRepository? repo,
    InstantAdService? ads,
    RecordingAnalytics? analytics,
  }) async {
    await pumpScreen(
      tester,
      initial: '/daily',
      screens: {'/daily': (_) => const DailyScreen()},
      overrides: [
        catalogueRepositoryProvider.overrideWithValue(FakeCatalogueRepository(testCatalogue())),
        dailyProvider.overrideWith((ref) => Stream.value(status)),
        dailyTopThreeProvider.overrideWith((ref) async => top),
        dailyRepositoryProvider.overrideWith((ref) async => repo ?? _FakeDailyRepository(null)),
        adServiceProvider.overrideWithValue(ads ?? InstantAdService()),
        analyticsProvider.overrideWithValue(analytics ?? RecordingAnalytics()),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('not yet played: play button, streak and the empty top-3 row', (tester) async {
    await pumpDaily(
      tester,
      const DailyStatus(
        date: '2026-11-15',
        layoutId: 'lotus',
        seed: 1,
        streak: 5,
        weekDone: [true, true, true, true, true, false, false],
      ),
    );
    expect(find.text('Lotus'), findsOneWidget);
    expect(find.text('Sunday 15 November'), findsOneWidget);
    expect(find.text('14 tiles · Medium · everyone plays the same deal'), findsOneWidget);
    expect(find.text('days'), findsOneWidget);
    expect(find.text('15'), findsOneWidget); // today's bead
    expect(find.text('Be the first today'), findsOneWidget);
    expect(find.text("Play today's board"), findsOneWidget);
    await tester.tap(find.text("Play today's board"));
    await tester.pumpAndSettle();
    expect(find.text('route:/daily/play'), findsOneWidget);
  });

  testWidgets('cleared today: time, stars and the unranked replay', (tester) async {
    await pumpDaily(
      tester,
      const DailyStatus(date: '2026-11-15', layoutId: 'lotus', seed: 1, firstClearMs: 298000, firstClearStars: 3, streak: 1),
      top: const [DailyTopEntry(rank: 1, name: 'Mira K.', timeMs: 298000)],
    );
    expect(find.text('Cleared in 4:58'), findsOneWidget);
    expect(find.text('Play again (unranked)'), findsOneWidget);
    expect(find.text('Mira K.'), findsOneWidget);
    expect(find.text('day'), findsOneWidget);
  });

  testWidgets('streak repair offer: rewarded ad repairs and logs', (tester) async {
    final repo = _FakeDailyRepository(const StreakRepairOffer(restoredStreak: 6, missedDate: '2026-11-14'));
    final ads = InstantAdService();
    final analytics = RecordingAnalytics();
    await pumpDaily(
      tester,
      const DailyStatus(date: '2026-11-15', layoutId: 'lotus', seed: 1),
      repo: repo,
      ads: ads,
      analytics: analytics,
    );
    expect(find.text('Keep your 6-day streak?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('streak-repair-watch')));
    await tester.pumpAndSettle();
    expect(ads.shown, [RewardedPlacement.streakRepair]);
    expect(repo.repairs, 1);
    expect(analytics.names, contains(AnalyticsEvents.streakRepaired));
    expect(find.text('Keep your 6-day streak?'), findsNothing);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('streak repair: no reward, no repair', (tester) async {
    final repo = _FakeDailyRepository(const StreakRepairOffer(restoredStreak: 3, missedDate: '2026-11-14'));
    await pumpDaily(
      tester,
      const DailyStatus(date: '2026-11-15', layoutId: 'lotus', seed: 1),
      repo: repo,
      ads: InstantAdService(reward: false),
    );
    await tester.tap(find.byKey(const ValueKey('streak-repair-watch')));
    await tester.pumpAndSettle();
    expect(repo.repairs, 0);
    expect(find.text('Keep your 3-day streak?'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });
}

class _FakeDailyRepository implements DailyRepository {
  _FakeDailyRepository(this._offer);

  StreakRepairOffer? _offer;
  int repairs = 0;
  final _offers = StreamController<StreakRepairOffer?>.broadcast();

  @override
  Stream<DailyStatus> watchToday() => const Stream.empty();

  @override
  Stream<StreakRepairOffer?> watchRepairOffer() async* {
    yield _offer;
    yield* _offers.stream;
  }

  @override
  Future<bool> canRepairStreak() async => _offer != null;

  @override
  Future<bool> repairStreak() async {
    if (_offer == null) return false;
    repairs++;
    _offer = null;
    _offers.add(null);
    return true;
  }
}
