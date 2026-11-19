import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/settings.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/game/game_providers.dart';
import 'package:jadewell_flutter_app/state/game/game_view_state.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_face_spec.dart';
import 'package:jadewell_flutter_app/ui/screens/cleared/cleared_screen.dart';
import 'package:jadewell_flutter_app/ui/screens/game/game_modals.dart';
import 'package:jadewell_flutter_app/ui/screens/onboarding/onboarding_screen.dart';
import 'package:jadewell_flutter_app/ui/screens/splash/splash_screen.dart';
import 'package:jadewell_flutter_app/ui/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

import '../ui/golden_helpers.dart' show loadJwFonts;
import 'home/screen_harness.dart';

/// The game-flow screens (splash, onboarding, game modals, cleared) must lay
/// out without overflow on the phone frame (390 × 844) and the tablet
/// (Tab A9, ≈ 600 × 1005), at text scale 1.0 and 1.3, in both themes. Any
/// overflow is a FlutterError, which fails the test.
const _sizes = [Size(360, 780), Size(390, 844), Size(600, 1005)];
const _scales = [1.0, 1.3];

void _forEachConfig(void Function(String name, Size size, double scale, Brightness b) body) {
  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final b in Brightness.values) {
        body('${size.width.toInt()}x${size.height.toInt()} @$scale ${b.name}', size, scale, b);
      }
    }
  }
}

void _textScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

Future<void> _settle(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _FixedCleared extends LastClearedController {
  _FixedCleared(this.result);
  final ClearedResult result;
  @override
  ClearedResult? build() => result;
}

ClearedResult _result({required String name, required bool newBest, int stars = 3}) => ClearedResult(
  layoutId: 'turtle',
  layoutName: name,
  chapterId: 'classics',
  chapterName: 'Classics',
  tileCount: 144,
  isDaily: false,
  stats: ClearStats(
    elapsedMs: 4087000,
    hintsUsed: 12,
    shufflesUsed: 1,
    rewardedShuffles: 0,
    undos: 3,
    longestStreak: 144,
    tilesMatched: 144,
    parMs: 360000,
    stars: stars,
  ),
  stars: stars,
  isNewBest: newBest,
  previousBestMs: newBest ? 4300000 : 4000000,
  firstClear: !newBest,
);

void main() {
  setUpAll(loadJwFonts);
  final faces = TileFaceSpec.parse(File(TileFaceSpec.assetPath).readAsStringSync());

  _forEachConfig((name, size, scale, brightness) {
    testWidgets('game modals fit ($name)', (tester) async {
      _textScale(tester, scale);
      Future<bool> watch() async => true;
      final modals = <(Widget, bool)>[
        (const PausedCard(time: '1:08:12', meta: 'Butterfly Garden · Creatures · 144 tiles left'), false),
        (const NoMovesSheet(tilesLeft: 144, canUndo: true), true),
        (const ShuffleConfirmDialog(tilesLeft: 144, freeLeft: 2), false),
        (RewardOfferSheet(title: 'Out of free hints', body: 'Watch a short video for another hint?', watch: watch, icon: JwIcons.hint), true),
        (RewardOfferSheet(title: 'Out of free shuffles', body: 'Watch a short video for another shuffle?', watch: watch, icon: JwIcons.shuffle), true),
        (const QuitDialog(), false),
      ];
      for (final (modal, bottom) in modals) {
        await pumpScreen(
          tester,
          initial: '/m',
          size: size,
          brightness: brightness,
          screens: {
            // The same placement as showGameModal.
            '/m': (_) => Material(
              type: MaterialType.transparency,
              child: SafeArea(
                child: bottom ? Align(alignment: Alignment.bottomCenter, child: modal) : Center(child: SingleChildScrollView(child: modal)),
              ),
            ),
          },
          overrides: const [],
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('rewarded intro sheet fits ($name)', (tester) async {
      _textScale(tester, scale);
      await pumpScreen(
        tester,
        initial: '/m',
        size: size,
        brightness: brightness,
        screens: {
          '/m': (_) => Material(
            type: MaterialType.transparency,
            child: SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: RewardedIntroSheet(
                  title: 'Head start',
                  body: 'Watch a video for +2 hints on your next board',
                  icon: JwIcons.hint,
                  watch: () async => false,
                ),
              ),
            ),
          ),
        },
        overrides: const [],
      );
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cleared screen fits ($name)', (tester) async {
      _textScale(tester, scale);
      for (final r in [
        _result(name: 'Butterfly Garden Extended Edition', newBest: true),
        _result(name: 'Turtle', newBest: false, stars: 2),
      ]) {
        await pumpScreen(
          tester,
          initial: '/cleared/turtle',
          size: size,
          brightness: brightness,
          screens: {'/cleared/turtle': (_) => const ClearedScreen(layoutId: 'turtle')},
          overrides: [
            catalogueRepositoryProvider.overrideWithValue(FakeCatalogueRepository(testCatalogue())),
            progressRepositoryProvider.overrideWithValue(MemoryProgressRepository()),
            adServiceProvider.overrideWithValue(InstantAdService(reward: false)),
            analyticsProvider.overrideWithValue(RecordingAnalytics()),
            lastClearedProvider.overrideWith(() => _FixedCleared(r)),
          ],
        );
        // The whole beat sheet, then the Head start sheet on top.
        await _settle(tester, ClearedBeats.end + 1200);
        expect(find.text('Board cleared!'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 6));
      }
    });

    testWidgets('onboarding fits ($name)', (tester) async {
      _textScale(tester, scale);
      await pumpScreen(
        tester,
        initial: '/onboarding',
        size: size,
        brightness: brightness,
        screens: {'/onboarding': (_) => const OnboardingScreen()},
        overrides: [
          settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository()),
          analyticsProvider.overrideWithValue(RecordingAnalytics()),
          onboardingFacesProvider.overrideWith((ref) async => faces),
        ],
      );
      await tester.pumpAndSettle();
      for (var page = 0; page < 2; page++) {
        await tester.tap(find.byKey(const ValueKey('onboarding-next')));
        await tester.pumpAndSettle();
      }
      expect(find.text('3 of 3'), findsOneWidget);
    });

    testWidgets('splash fits ($name)', (tester) async {
      _textScale(tester, scale);
      await pumpScreen(
        tester,
        initial: '/',
        size: size,
        brightness: brightness,
        screens: {
          '/': (_) => const SplashScreen(),
          '/home': (_) => const Scaffold(body: Text('home')),
        },
        overrides: [
          settingsRepositoryProvider.overrideWithValue(MemorySettingsRepository(const AppSettings(onboardingDone: true))),
          analyticsProvider.overrideWithValue(RecordingAnalytics()),
        ],
      );
      await _settle(tester, 560);
      expect(find.text('Jadewell'), findsOneWidget);
      // Past the hold, then the hand-over to home.
      await _settle(tester, 600);
      await tester.pumpAndSettle();
      expect(find.text('home'), findsOneWidget);
    });
  });
}
