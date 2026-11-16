import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/stats/stats_screen.dart';
import 'package:jadewell_flutter_app/ui/widgets/empty_state/jw_empty_state.dart';

import '../../ui/golden_helpers.dart' show loadJwFonts;
import '../home/screen_harness.dart';

void main() {
  setUpAll(loadJwFonts);

  Future<void> pumpStats(WidgetTester tester, PlayerStats stats, Map<String, LayoutProgress> progress) async {
    await pumpScreen(
      tester,
      initial: '/stats',
      screens: {'/stats': (_) => StatsScreen(clock: () => DateTime(2026, 11, 15))},
      overrides: [
        catalogueRepositoryProvider.overrideWithValue(FakeCatalogueRepository(testCatalogue())),
        statsProvider.overrideWith((ref) => Stream.value(stats)),
        progressProvider.overrideWith((ref) => Stream.value(progress)),
      ],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty stats show zeros and the empty state', (tester) async {
    await pumpStats(tester, const PlayerStats(), const {});
    expect(find.byType(JwEmptyState), findsOneWidget);
    expect(find.text('Your story starts here'), findsOneWidget);
    expect(find.text('0'), findsNWidgets(4));
    expect(find.text('Last 7 days'), findsNothing);
    await tester.tap(find.text('Play your first board'));
    await tester.pumpAndSettle();
    expect(find.text('route:/game/pyramid'), findsOneWidget);
  });

  testWidgets('filled stats: cards, chart and sorted best times', (tester) async {
    await pumpStats(
      tester,
      const PlayerStats(
        gamesPlayed: 58,
        boardsCleared: 41,
        tilesMatched: 6212,
        currentStreak: 5,
        bestStreak: 12,
        last7Days: [3, 5, 2, 6, 4, 7, 5],
      ),
      const {
        'fortress': LayoutProgress(layoutId: 'fortress', bestTimeMs: 662000, clears: 1, bestStars: 1),
        'pyramid': LayoutProgress(layoutId: 'pyramid', bestTimeMs: 228000, clears: 2, bestStars: 3),
        'turtle': LayoutProgress(layoutId: 'turtle', savedFraction: 0.2),
      },
    );
    expect(find.byType(JwEmptyState), findsNothing);
    expect(find.text('58'), findsOneWidget);
    expect(find.text('6,212'), findsOneWidget);
    expect(find.text('day streak · best 12'), findsOneWidget);
    expect(find.text('32 games'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Fortress'), 200);
    expect(tester.getTopLeft(find.text('Pyramid')).dy, lessThan(tester.getTopLeft(find.text('Fortress')).dy));
    expect(find.text('3:48'), findsOneWidget);
    expect(find.text('11:02'), findsOneWidget);
    expect(find.text('Turtle'), findsNothing);
  });
}
