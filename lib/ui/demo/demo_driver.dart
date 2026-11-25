import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../state/game/game_controller.dart';
import '../../state/game/game_launch.dart';
import '../../state/game/game_view_state.dart';
import '../router.dart';
import 'frame_stats.dart';

/// Demo mode: the app plays itself so frame timings can be measured on a
/// device without anyone touching it (docs/PERFORMANCE.md).
///
/// Debug and profile builds only, and only when built with
/// `--dart-define=JW_DEMO=true`; it is a compile-time `false` in release, so
/// none of this ships.
const kDemoMode = !kReleaseMode && bool.fromEnvironment('JW_DEMO');

/// Layouts the demo plays, in order: the largest (turtle, 144 tiles) first.
const _demoLayouts = ['turtle', 'fortress', 'pyramid', 'butterfly'];

/// Runs the demo loop above [child]: home → a full board (hints, undo,
/// shuffle) → cleared → leaderboard / stats / settings / daily, scrolling
/// each, then the next layout. Each step is a [FrameStats] segment; a total
/// per kind is printed after every loop. Runs until the app is closed.
///
/// While it runs, nothing is persisted or synced (main.dart swaps in the
/// in-memory repositories and turns ads off) so a demo never touches the
/// player's progress or the leaderboards.
class DemoDriver extends StatefulWidget {
  const DemoDriver({super.key, required this.child});

  final Widget child;

  @override
  State<DemoDriver> createState() => _DemoDriverState();
}

class _DemoDriverState extends State<DemoDriver> {
  bool _stopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  @override
  void dispose() {
    _stopped = true;
    super.dispose();
  }

  BuildContext? get _ctx => rootNavigatorKey.currentContext;
  GoRouter get _router => GoRouter.of(_ctx!);
  String get _path => _router.routerDelegate.currentConfiguration.uri.path;

  Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<bool> _waitFor(bool Function() test, {int timeoutMs = 15000}) async {
    for (var t = 0; t < timeoutMs; t += 100) {
      if (_stopped) return false;
      if (_ctx != null && test()) return true;
      await _wait(100);
    }
    return false;
  }

  Future<void> _run() async {
    debugPrint('JWPERF demo start');
    // Splash → home (or the starter board on a fresh install: skip it).
    await _waitFor(() => _path == AppRoutes.home || _path.startsWith('/game/'), timeoutMs: 20000);
    if (_stopped) return;
    if (_path != AppRoutes.home) _router.go(AppRoutes.home);
    await _wait(1500);

    final stats = FrameStats.instance;
    for (var loop = 1; !_stopped; loop++) {
      for (final layout in _demoLayouts) {
        if (_stopped) return;
        stats.begin('home');
        await _wait(1500);
        await _scrollTop();
        await _wait(800);

        await _playBoard(layout);
        if (_stopped) return;

        stats.begin('cleared:$layout');
        await _wait(6000); // the whole beat sheet: confetti, stars, odometers
        stats.begin('nav');
        _router.go(AppRoutes.home);
        await _wait(1200);

        for (final route in [AppRoutes.leaderboard, AppRoutes.stats, AppRoutes.settings, AppRoutes.daily]) {
          if (_stopped) return;
          stats.begin('screen:${route.substring(1)}');
          unawaited(_router.push(route));
          await _wait(1400);
          await _scrollTop();
          await _wait(600);
          _router.pop();
          await _wait(900);
        }
      }
      stats.report('loop$loop');
    }
  }

  Future<void> _playBoard(String layout) async {
    final stats = FrameStats.instance;
    stats.begin('deal:$layout');
    unawaited(_router.push(AppRoutes.game(layout)));
    final container = ProviderScope.containerOf(_ctx!, listen: false);
    final provider = gameControllerProvider(GameLaunch.layout(layout));
    final ready = await _waitFor(() {
      final s = container.read(provider);
      return s.phase == GamePhase.playing && s.game != null;
    });
    if (!ready) {
      debugPrint('JWPERF demo: $layout never became playable');
      return;
    }
    await _wait(1800); // let the deal animation finish inside its own segment
    stats.begin('game:$layout');
    await container.read(provider.notifier).demoPlay();
    // The screen hands over to /cleared after the last pair's exit.
    await _waitFor(() => _path.startsWith('/cleared'), timeoutMs: 20000);
  }

  /// Scrolls the current screen's main list to the bottom and back.
  Future<void> _scrollTop() async {
    final scrollable = _currentScrollable();
    if (scrollable == null) return;
    final pos = scrollable.position;
    if (pos.maxScrollExtent <= 0) return;
    await pos.animateTo(pos.maxScrollExtent, duration: const Duration(milliseconds: 1600), curve: Curves.easeInOut);
    await _wait(300);
    if (!scrollable.mounted) return;
    await pos.animateTo(0, duration: const Duration(milliseconds: 1200), curve: Curves.easeInOut);
  }

  /// The vertical scrollable with the most content on the top route.
  ScrollableState? _currentScrollable() {
    final root = _ctx;
    if (root == null) return null;
    ScrollableState? best;
    void visit(Element e) {
      if (e is StatefulElement && e.state is ScrollableState) {
        final s = e.state as ScrollableState;
        final route = ModalRoute.of(e);
        if (s.position.hasContentDimensions &&
            s.axisDirection == AxisDirection.down &&
            (route == null || route.isCurrent) &&
            (best == null || s.position.maxScrollExtent > best!.position.maxScrollExtent)) {
          best = s;
        }
      }
      e.visitChildren(visit);
    }

    root.visitChildElements(visit);
    return best;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
