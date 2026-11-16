import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:jadewell_flutter_app/data/repositories/asset_catalogue_repository.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/game/game_controller.dart';
import 'package:jadewell_flutter_app/state/game/game_launch.dart';
import 'package:jadewell_flutter_app/state/game/game_providers.dart';
import 'package:jadewell_flutter_app/state/game/game_view_state.dart';
import 'package:jadewell_flutter_app/ui/l10n/generated/app_localizations.dart';
import 'package:jadewell_flutter_app/ui/router.dart';
import 'package:jadewell_flutter_app/ui/screens/cleared/cleared_screen.dart';
import 'package:jadewell_flutter_app/ui/screens/game/game_modals.dart';
import 'package:jadewell_flutter_app/ui/screens/game/game_screen.dart';
import 'package:jadewell_flutter_app/ui/screens/game/game_widgets.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_theme.dart';
import 'package:jadewell_flutter_app/ui/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:material_ui/material_ui.dart' as material_ui show GlobalMaterialLocalizations;

import '../ui/golden_helpers.dart';

/// Serves `assets/` from disk so the real catalogue loads without the
/// platform channel.
class _DiskBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => ByteData.sublistView(File(key).readAsBytesSync());
}

/// Set JW_SHOTS to a directory to dump full-screen screenshots (design review).
final _shotsDir = Platform.environment['JW_SHOTS'];

Future<void> _shot(WidgetTester tester, String name) async {
  if (_shotsDir == null) return;
  final element = tester.element(find.byKey(const ValueKey('screen')));
  await tester.runAsync(() async {
    final image = await captureImage(element);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_shotsDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _app(GoRouter router, Brightness brightness, MemoryProgressRepository repo) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    catalogueRepositoryProvider.overrideWithValue(AssetCatalogueRepository(bundle: _DiskBundle())),
    progressRepositoryProvider.overrideWithValue(repo),
    gameSeedSourceProvider.overrideWithValue(() => 42),
    gameDealerProvider.overrideWithValue((layout, seed, parMs) async => GameState.newGame(layout, seed, parMs: parMs)),
  ],
  child: RepaintBoundary(
    key: const ValueKey('screen'),
    child: MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        ...material_ui.GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildJwThemeData(brightness),
    ),
  ),
);

GoRouter _router(String initial) => GoRouter(
  initialLocation: initial,
  routes: [
    GoRoute(path: AppRoutes.home, builder: (_, _) => const Scaffold(body: Center(child: Text('home')))),
    GoRoute(path: '/game/:layoutId', builder: (_, s) => GameScreen(layoutId: s.pathParameters['layoutId']!)),
    GoRoute(path: '/cleared/:layoutId', builder: (_, s) => ClearedScreen(layoutId: s.pathParameters['layoutId']!)),
    GoRoute(path: AppRoutes.settings, builder: (_, _) => const Scaffold(body: Center(child: Text('settings')))),
  ],
);

/// Advances time in 16 ms frames so animations actually progress.
Future<void> _wait(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Finder _knob(int i) => find.descendant(of: find.byType(JwToolKnob).at(i), matching: find.byType(ClayPressable));

void main() {
  setUpAll(loadJwFonts);
  loadFaces();

  for (final brightness in Brightness.values) {
    testWidgets('play the turtle through to the cleared screen (${brightness.name})', (tester) async {
      tester.view
        ..physicalSize = const Size(780, 1688)
        ..devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final repo = MemoryProgressRepository();
      final router = _router(AppRoutes.game('turtle'));
      addTearDown(router.dispose);
      await tester.pumpWidget(_app(router, brightness, repo));
      for (var i = 0; i < 10; i++) {
        await _wait(tester, 50);
      }
      final container = ProviderScope.containerOf(tester.element(find.byType(GameScreen)));
      const launch = GameLaunch.layout('turtle');
      GameViewState state() => container.read(gameControllerProvider(launch));
      final c = container.read(gameControllerProvider(launch).notifier);
      expect(state().phase, GamePhase.playing);

      // Entry (≈ 1.9 s), then the full board (screen 04).
      await _wait(tester, 2200);
      await _shot(tester, '04_full_${brightness.name}');

      // A few matches and a selection (screen 03).
      for (var i = 0; i < 6; i++) {
        final (a, b) = findHint(state().game!)!;
        c
          ..tap(a)
          ..tap(b);
        await _wait(tester, 900);
      }
      c.tap(state().game!.freeTiles.first);
      await _wait(tester, 600);
      await _shot(tester, '03_selected_${brightness.name}');

      // Hint (screen 06).
      await tester.tap(_knob(0));
      await _wait(tester, 900);
      expect(state().hint, isNotNull);
      expect(find.textContaining('this pair is ready'), findsOneWidget);
      await _shot(tester, '06_hint_${brightness.name}');
      await _wait(tester, 1400);
      expect(state().hint, isNull);

      // Shuffle confirmation (screen 09), cancelled.
      await tester.tap(_knob(2));
      await _wait(tester, 500);
      expect(find.byType(ShuffleConfirmDialog), findsOneWidget);
      await _shot(tester, '09_shuffle_${brightness.name}');
      await tester.tap(find.text('Cancel'));
      await _wait(tester, 400);

      // Pause (screen 08) through the timer pill: tiles face down, clock stopped.
      await tester.tap(find.byType(GameTimerPill));
      await _wait(tester, 600);
      expect(find.byType(PausedCard), findsOneWidget);
      expect(c.clockRunning, isFalse);
      await _shot(tester, '08_paused_${brightness.name}');
      await tester.tap(find.text('Resume'));
      await _wait(tester, 400);
      expect(state().paused, isFalse);

      // Play to the end with the solver's hints (near end: screen 05).
      while (!state().game!.isCleared) {
        if (state().tilesLeft == 6) {
          await _wait(tester, 900);
          await _shot(tester, '05_near_end_${brightness.name}');
        }
        final (a, b) = findHint(state().game!)!;
        c
          ..tap(a)
          ..tap(b);
        await _wait(tester, 120);
      }
      expect(state().phase, GamePhase.cleared);
      await _wait(tester, 900);
      await _shot(tester, '10a_ghost_wave_${brightness.name}');

      // Hand-over to the cleared screen and its beat sheet.
      await _wait(tester, 800);
      await _wait(tester, 400);
      expect(find.byType(ClearedScreen), findsOneWidget);
      expect(repo.results.single.outcome.name, 'cleared');
      await _wait(tester, 900);
      await _shot(tester, '10b_cleared_mid_${brightness.name}');
      await _wait(tester, 1900);
      await _shot(tester, '10_cleared_${brightness.name}');
      expect(find.text('Turtle cleared'), findsOneWidget);
      expect(find.textContaining('Next:'), findsOneWidget);

      // Head start offer: skip it.
      await _wait(tester, 2000);
      expect(find.text('Head start'), findsOneWidget);
      await _shot(tester, '10c_head_start_${brightness.name}');
      await tester.tap(find.text('Skip'));
      await _wait(tester, 400);
      expect(container.read(headStartBonusProvider), 0);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  }

  testWidgets('a deadlocked board shows the no-moves sheet (screen 07)', (tester) async {
    tester.view
      ..physicalSize = const Size(780, 1688)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final layout = Layout.parse(File('assets/layouts/turtle.json').readAsStringSync());
    // Play the first available pair until the board jams.
    GameState? jammed;
    for (var seed = 1; jammed == null && seed < 200; seed++) {
      var g = GameState.newGame(layout, seed, parMs: 360000);
      while (!g.isCleared && !g.isDeadlocked) {
        final (a, b) = g.availableMoves.first;
        g = match(g, a, b, elapsedMs: g.lastElapsedMs + 2000).$1;
      }
      if (g.isDeadlocked && g.tilesMatched < 120) jammed = g;
    }
    expect(jammed, isNotNull);
    final repo = MemoryProgressRepository();
    await repo.saveGame('turtle', stateJson: jammed!.toJson(), elapsedMs: 552000, fractionCleared: 0.5);
    final router = _router(AppRoutes.game('turtle'));
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(router, Brightness.light, repo));
    for (var i = 0; i < 10; i++) {
      await _wait(tester, 50);
    }
    await _wait(tester, 2500);
    expect(find.byType(NoMovesSheet), findsOneWidget);
    await _shot(tester, '07_no_moves_light');
    await tester.tap(find.text('Shuffle tiles · free'));
    await _wait(tester, 800);
    final container = ProviderScope.containerOf(tester.element(find.byType(GameScreen)));
    expect(container.read(gameControllerProvider(const GameLaunch.layout('turtle'))).deadlocked, isFalse);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
