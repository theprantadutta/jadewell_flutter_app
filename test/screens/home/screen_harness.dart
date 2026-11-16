import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jadewell_flutter_app/data/models/catalogue.dart';
import 'package:jadewell_flutter_app/data/repositories/repositories.dart';
import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:jadewell_flutter_app/platform/ads/ad_service.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/ui/l10n/generated/app_localizations.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui/material_ui.dart' as material_ui show GlobalMaterialLocalizations;

/// Shared harness for the Phase 6 screen tests.

Layout _row(String id, int n) => Layout.fromPositions(id, [for (var i = 0; i < n; i++) Position(i * 2, 0, 0)]);

LayoutInfo _info(String id, String name, String chapter, int order, {int requires = 0, String difficulty = 'easy'}) =>
    LayoutInfo(
      id: id,
      name: name,
      chapterId: chapter,
      order: order,
      difficulty: difficulty,
      parMs: 60000,
      layout: _row(id, 4 + order * 2),
      requiresChapterClears: requires,
    );

/// Classics (always) · Creatures (3 Classics clears; Dragon needs 1 Creature
/// clear) · Wonders (8 total clears) · one daily layout.
Catalogue testCatalogue() {
  final layouts = <String, LayoutInfo>{
    'pyramid': _info('pyramid', 'Pyramid', 'classics', 1),
    'turtle': _info('turtle', 'Turtle', 'classics', 2, difficulty: 'medium'),
    'fortress': _info('fortress', 'Fortress', 'classics', 3, difficulty: 'hard'),
    'bridge': _info('bridge', 'Bridge', 'classics', 4),
    'crab': _info('crab', 'Crab', 'creatures', 1),
    'dragon': _info('dragon', 'Dragon', 'creatures', 2, requires: 1),
    'spiral': _info('spiral', 'Spiral', 'wonders', 1),
    'temple': _info('temple', 'Temple', 'wonders', 2, requires: 1),
    'lotus': _info('lotus', 'Lotus', 'daily', 5, difficulty: 'medium'),
  };
  return Catalogue(
    chapters: const [
      ChapterInfo(id: 'classics', name: 'Classics', order: 1, unlock: UnlockAlways(), layoutIds: ['pyramid', 'turtle', 'fortress', 'bridge']),
      ChapterInfo(id: 'creatures', name: 'Creatures', order: 2, unlock: UnlockChapterClears('classics', 2), layoutIds: ['crab', 'dragon']),
      ChapterInfo(id: 'wonders', name: 'Wonders', order: 3, unlock: UnlockTotalClears(8), layoutIds: ['spiral', 'temple']),
    ],
    layouts: layouts,
    dailyPool: const ['lotus'],
  );
}

class FakeCatalogueRepository implements CatalogueRepository {
  FakeCatalogueRepository(this.catalogue);
  final Catalogue catalogue;
  @override
  Future<Catalogue> load() async => catalogue;
}

class RecordingAnalytics implements AnalyticsService {
  final events = <(String, Map<String, Object>)>[];
  @override
  Future<void> log(String event, [Map<String, Object> params = const {}]) async => events.add((event, params));
  @override
  Future<void> screen(String name) async {}
  Iterable<String> get names => events.map((e) => e.$1);
}

class InstantAdService implements AdService {
  InstantAdService({this.reward = true});
  final bool reward;
  final shown = <RewardedPlacement>[];
  @override
  bool get adsRemoved => false;
  @override
  Future<void> init() async {}
  @override
  bool isRewardedReady(RewardedPlacement placement) => true;
  @override
  Future<bool> showRewarded(RewardedPlacement placement) async {
    shown.add(placement);
    return reward;
  }

  @override
  Future<bool> showRewardedInterstitial(RewardedInterstitialPlacement placement) async => reward;
  @override
  Future<void> onBoardCleared({required bool isDaily}) async {}
}

/// Pumps [initial] inside a themed router app with stub routes for every
/// destination these screens navigate to (rendered as `route:<path>`).
Future<void> pumpScreen(
  WidgetTester tester, {
  required String initial,
  required Map<String, WidgetBuilder> screens,
  required List<Override> overrides,
  Brightness brightness = Brightness.light,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      for (final e in screens.entries) GoRoute(path: e.key, builder: (context, _) => e.value(context)),
      GoRoute(path: '/:a', builder: (_, s) => Scaffold(body: Text('route:${s.uri}'))),
      GoRoute(path: '/:a/:b', builder: (_, s) => Scaffold(body: Text('route:${s.uri}'))),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        routerConfig: router,
        theme: buildJwThemeData(brightness),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          ...material_ui.GlobalMaterialLocalizations.delegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ),
  );
}
