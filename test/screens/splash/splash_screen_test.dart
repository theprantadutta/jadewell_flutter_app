import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/catalogue.dart';
import 'package:jadewell_flutter_app/data/models/settings.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/splash/splash_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../home/screen_harness.dart';

void main() {
  Future<(RecordingAnalytics, MemorySettingsRepository)> pump(WidgetTester tester, AppSettings settings, {Catalogue? catalogue}) async {
    final analytics = RecordingAnalytics();
    final repo = MemorySettingsRepository(settings);
    await pumpScreen(
      tester,
      initial: '/',
      screens: {
        '/': (_) => const SplashScreen(),
        '/home': (_) => const Scaffold(body: Text('home')),
      },
      overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        catalogueRepositoryProvider.overrideWithValue(FakeCatalogueRepository(catalogue ?? testCatalogue())),
        analyticsProvider.overrideWithValue(analytics),
      ],
    );
    return (analytics, repo);
  }

  Future<void> finish(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
  }

  testWidgets('first run: wordmark, app_open once, then straight into the starter board', (tester) async {
    final (analytics, repo) = await pump(tester, const AppSettings());
    expect(find.text('Jadewell'), findsOneWidget);
    expect(find.text('MAHJONG SOLITAIRE'), findsOneWidget);
    await finish(tester);
    expect(find.text('route:/game/sprout'), findsOneWidget);
    expect(analytics.names.where((n) => n == AnalyticsEvents.appOpen), hasLength(1));
    // First run is done once the board is reached: the next launch goes home.
    expect((await repo.read()).onboardingDone, isTrue);
    final done = analytics.events.singleWhere((e) => e.$1 == AnalyticsEvents.onboardingComplete);
    expect(done.$2, {'flow': 'play_first', 'skipped': false, 'step': 0});
    expect(analytics.names, isNot(contains(AnalyticsEvents.onboardingStep)));
  });

  testWidgets('returning player goes home, no first-run events', (tester) async {
    final (analytics, _) = await pump(tester, const AppSettings(onboardingDone: true));
    await finish(tester);
    expect(find.text('home'), findsOneWidget);
    expect(analytics.names, isNot(contains(AnalyticsEvents.onboardingComplete)));
  });

  testWidgets('first run without a starter board goes home and tries again next launch', (tester) async {
    final c = testCatalogue();
    final (analytics, repo) = await pump(
      tester,
      const AppSettings(),
      catalogue: Catalogue(chapters: c.chapters, layouts: c.layouts, dailyPool: c.dailyPool),
    );
    await finish(tester);
    expect(find.text('home'), findsOneWidget);
    expect((await repo.read()).onboardingDone, isFalse);
    expect(analytics.names, isNot(contains(AnalyticsEvents.onboardingComplete)));
  });
}
