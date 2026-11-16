import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/settings.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/splash/splash_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../home/screen_harness.dart';

void main() {
  Future<RecordingAnalytics> pump(WidgetTester tester, AppSettings settings) async {
    final analytics = RecordingAnalytics();
    await pumpScreen(
      tester,
      initial: '/',
      screens: {
        '/': (_) => const SplashScreen(),
        '/onboarding': (_) => const Scaffold(body: Text('onboarding')),
        '/home': (_) => const Scaffold(body: Text('home')),
      },
      overrides: [
        settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository(settings)),
        analyticsProvider.overrideWithValue(analytics),
      ],
    );
    return analytics;
  }

  testWidgets('first run: wordmark, app_open once, then onboarding within ~600 ms', (tester) async {
    final analytics = await pump(tester, const AppSettings());
    expect(find.text('Jadewell'), findsOneWidget);
    expect(find.text('MAHJONG SOLITAIRE'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('onboarding'), findsOneWidget);
    expect(analytics.names.where((n) => n == AnalyticsEvents.appOpen), hasLength(1));
  });

  testWidgets('returning player goes home', (tester) async {
    await pump(tester, const AppSettings(onboardingDone: true));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });
}
