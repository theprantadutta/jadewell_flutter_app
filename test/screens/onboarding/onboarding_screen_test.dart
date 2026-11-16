import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_face_spec.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_widget.dart';
import 'package:jadewell_flutter_app/ui/screens/onboarding/onboarding_illustrations.dart';
import 'package:jadewell_flutter_app/ui/screens/onboarding/onboarding_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../ui/golden_helpers.dart' show loadJwFonts;
import '../home/screen_harness.dart';

void main() {
  setUpAll(loadJwFonts);
  final faces = TileFaceSpec.parse(File(TileFaceSpec.assetPath).readAsStringSync());

  Future<(MemorySettingsRepository, RecordingAnalytics)> pump(WidgetTester tester) async {
    final settings = MemorySettingsRepository();
    final analytics = RecordingAnalytics();
    await pumpScreen(
      tester,
      initial: '/onboarding',
      screens: {
        '/onboarding': (_) => const OnboardingScreen(),
        '/home': (_) => const Scaffold(body: Text('home')),
      },
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        analyticsProvider.overrideWithValue(analytics),
        onboardingFacesProvider.overrideWith((ref) async => faces),
      ],
    );
    await tester.pumpAndSettle();
    return (settings, analytics);
  }

  testWidgets('Next x2 then Start sets onboardingDone and goes home', (tester) async {
    final (settings, analytics) = await pump(tester);
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('Match identical pairs'), findsOneWidget);
    expect(find.byType(TileWidget), findsNWidgets(4));

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    expect(find.text('Covered from above'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('Start playing'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();

    expect((await settings.read()).onboardingDone, isTrue);
    expect(find.text('home'), findsOneWidget);
    expect(analytics.events.where((e) => e.$1 == AnalyticsEvents.onboardingStep).map((e) => e.$2['step']), [1, 2, 3]);
    expect(analytics.names, contains(AnalyticsEvents.onboardingComplete));
  });

  testWidgets('Skip finishes immediately', (tester) async {
    final (settings, analytics) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();
    expect((await settings.read()).onboardingDone, isTrue);
    expect(find.text('home'), findsOneWidget);
    final done = analytics.events.singleWhere((e) => e.$1 == AnalyticsEvents.onboardingComplete);
    expect(done.$2['skipped'], isTrue);
  });

  test('solvable board marks edge tiles free and covered tiles blocked', () {
    final all = SolvableIllustration.positions;
    final top = all.singleWhere((t) => t.z == 2);
    expect(SolvableIllustration.isFree(top, all), isTrue);
    final covered = all.firstWhere((t) => t.z == 1);
    expect(SolvableIllustration.isFree(covered, all), isFalse);
    final rowStart = all.firstWhere((t) => t.z == 0 && t.y == 0);
    expect(SolvableIllustration.isFree(rowStart, all), isTrue);
    final middle = all.firstWhere((t) => t.z == 0 && t.y == 0 && t.x == 6);
    expect(SolvableIllustration.isFree(middle, all), isFalse);
  });
}
