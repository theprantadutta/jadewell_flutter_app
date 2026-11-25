import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

  /// Settings → How to play: the screen is pushed over settings.
  Future<(MemorySettingsRepository, RecordingAnalytics)> pump(WidgetTester tester) async {
    final settings = MemorySettingsRepository();
    final analytics = RecordingAnalytics();
    await pumpScreen(
      tester,
      initial: '/settings',
      screens: {
        '/settings': (context) => Scaffold(
              body: Center(
                child: TextButton(onPressed: () => context.push('/how-to-play'), child: const Text('settings')),
              ),
            ),
        '/how-to-play': (_) => const OnboardingScreen(),
      },
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        analyticsProvider.overrideWithValue(analytics),
        onboardingFacesProvider.overrideWith((ref) async => faces),
      ],
    );
    await tester.tap(find.text('settings'));
    await tester.pumpAndSettle();
    return (settings, analytics);
  }

  testWidgets('How to play: Next x2 then Got it goes back, touching no first-run state', (tester) async {
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
    expect(find.text('Got it'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next')));
    await tester.pumpAndSettle();

    expect(find.text('settings'), findsOneWidget);
    expect((await settings.read()).onboardingDone, isFalse);
    final open = analytics.events.single;
    expect(open.$1, AnalyticsEvents.howToPlayOpen);
    expect(open.$2, {'source': 'settings'});
  });

  testWidgets('Close goes back immediately', (tester) async {
    final (_, analytics) = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsOneWidget);
    expect(analytics.names, isNot(contains(AnalyticsEvents.onboardingComplete)));
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
