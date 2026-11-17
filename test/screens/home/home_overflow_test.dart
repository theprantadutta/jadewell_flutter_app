import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/catalogue.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/repositories/asset_catalogue_repository.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/platform/ads/ad_service.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/home/home_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../../ui/golden_helpers.dart' show loadJwFonts;
import 'screen_harness.dart';

/// Every layout card state with the real catalogue (real names), at phone
/// (390 × 844) and tablet (600 × 1005, the Tab A9 at 1.33 dpr) widths and
/// at 100 % and 130 % text: any RenderFlex overflow fails the test.
GameResult _clear(String id, int ms, int stars) => GameResult(
      layoutId: id,
      seed: 1,
      generatorVersion: 1,
      outcome: GameOutcome.cleared,
      timeMs: ms,
      stars: stars,
      hintsUsed: 0,
      undos: 0,
      shufflesUsed: 0,
      tilesMatched: 4,
      longestStreak: 1,
      playedAt: DateTime(2026, 11, 15),
    );

Future<void> _pumpHome(WidgetTester tester, {required Size size, required double textScale, required bool populated}) async {
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final repo = MemoryProgressRepository();
  if (populated) {
    await repo.recordResult(_clear('pyramid', 228000, 3));
    await repo.recordResult(_clear('fortress', 3662000, 2)); // over an hour: h:mm:ss
    await repo.recordResult(_clear('crab', 375000, 1));
    await repo.saveGame('turtle', stateJson: const {}, elapsedMs: 1000, fractionCleared: 0.4);
    await repo.saveGame('bridge', stateJson: const {}, elapsedMs: 1000, fractionCleared: 0);
  }
  await pumpScreen(
    tester,
    initial: '/home',
    size: size,
    screens: {'/home': (_) => const HomeScreen()},
    overrides: [
      catalogueRepositoryProvider.overrideWithValue(FakeCatalogueRepository(_catalogue)),
      progressRepositoryProvider.overrideWithValue(repo),
      dailyProvider.overrideWith(
        (ref) => Stream.value(const DailyStatus(date: '2026-11-15', layoutId: 'lotus', seed: 7, streak: 12)),
      ),
      analyticsProvider.overrideWithValue(RecordingAnalytics()),
      adServiceProvider.overrideWithValue(InstantAdService()),
    ],
  );
  await tester.pumpAndSettle();
}

/// Scrolls the whole collection so every section gets laid out.
Future<void> _scrollThrough(WidgetTester tester) async {
  final list = find.byType(Scrollable).first;
  for (var i = 0; i < 14; i++) {
    await tester.drag(list, const Offset(0, -400));
    await tester.pumpAndSettle();
  }
}

late Catalogue _catalogue;

void main() {
  setUpAll(() async {
    await loadJwFonts();
    TestWidgetsFlutterBinding.ensureInitialized();
    _catalogue = await AssetCatalogueRepository().load();
  });

  const sizes = {'phone': Size(390, 844), 'tablet': Size(600, 1005)};
  for (final size in sizes.entries) {
    for (final scale in const [1.0, 1.3]) {
      for (final populated in const [true, false]) {
        testWidgets('home ${populated ? 'populated' : 'first run'} · ${size.key} · text ${scale}x: no overflow', (tester) async {
          await _pumpHome(tester, size: size.value, textScale: scale, populated: populated);
          expect(find.byType(HomeScreen), findsOneWidget);
          await _scrollThrough(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
