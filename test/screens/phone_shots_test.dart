// Phone-width screenshots of the collection and meta screens (390 pt wide,
// full length), light and dark, for side-by-side review against
// design/screens. Opt-in, writes outside the repo's tracked files:
//
//   JW_SHOTS=1 flutter test test/screens/phone_shots_test.dart --update-goldens
//
// Output: build/phone_shots/<screen>_<light|dark>.png
import 'dart:io';

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

import '../ui/golden_helpers.dart' show loadJwFonts;
import 'home/screen_harness.dart';

final bool _enabled = Platform.environment.containsKey('JW_SHOTS');

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

late Catalogue _catalogue;

/// Loads every [Image] on screen for real, then repaints.
Future<void> _settleImages(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
}

Future<void> _shot(WidgetTester tester, String name) async {
  await _settleImages(tester);
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('../../build/phone_shots/$name.png'));
}

Future<MemoryProgressRepository> _homeRepo({required bool populated}) async {
  final repo = MemoryProgressRepository();
  if (populated) {
    await repo.recordResult(_clear('pyramid', 228000, 2));
    await repo.recordResult(_clear('fortress', 662000, 3));
    await repo.recordResult(_clear('crab', 375000, 1));
    await repo.saveGame('turtle', stateJson: const {}, elapsedMs: 1000, fractionCleared: 0.4);
  }
  return repo;
}

void main() {
  setUpAll(() async {
    await loadJwFonts();
    _catalogue = await AssetCatalogueRepository().load();
  });

  for (final b in Brightness.values) {
    final theme = b == Brightness.light ? 'light' : 'dark';
    for (final populated in const [true, false]) {
      testWidgets('home ${populated ? '11' : '17a'} $theme', skip: !_enabled, (tester) async {
        await pumpScreen(
          tester,
          initial: '/home',
          brightness: b,
          size: const Size(390, 2060),
          screens: {'/home': (_) => const HomeScreen()},
          overrides: [
            catalogueRepositoryProvider.overrideWithValue(FakeCatalogueRepository(_catalogue)),
            progressRepositoryProvider.overrideWithValue(await _homeRepo(populated: populated)),
            dailyProvider.overrideWith(
              (ref) => Stream.value(const DailyStatus(date: '2026-11-15', layoutId: 'lotus', seed: 7, streak: 5)),
            ),
            analyticsProvider.overrideWithValue(RecordingAnalytics()),
            adServiceProvider.overrideWithValue(InstantAdService()),
          ],
        );
        await tester.pumpAndSettle();
        await _shot(tester, populated ? 'home_$theme' : 'empty_collection_$theme');
      });
    }
  }
}
