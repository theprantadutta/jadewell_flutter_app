import 'dart:isolate';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../engine/engine.dart';
import 'game_clock.dart';
import 'game_view_state.dart';

/// Deals and solver-verifies a board. Overridden in tests with a synchronous
/// dealer.
typedef GameDealer = Future<GameState> Function(Layout layout, int seed, int parMs);

/// Deals on a background isolate so the solver never janks the board entry.
Future<GameState> dealInBackground(Layout layout, int seed, int parMs) async {
  if (kIsWeb) return GameState.newGame(layout, seed, parMs: parMs);
  try {
    return await Isolate.run(() => GameState.newGame(layout, seed, parMs: parMs));
  } on Object catch (e) {
    if (e is DealException) rethrow;
    debugPrint('game: background deal failed ($e), dealing on the UI isolate');
    return GameState.newGame(layout, seed, parMs: parMs);
  }
}

final gameDealerProvider = Provider<GameDealer>((ref) => dealInBackground);

/// Creates the board clock (tests override with [FakeGameClock]).
final gameClockFactoryProvider = Provider<GameClock Function()>((ref) => StopwatchGameClock.new);

/// Random 32-bit seeds for collection boards (tests override for determinism).
final gameSeedSourceProvider = Provider<int Function()>((ref) {
  final random = Random();
  return () => random.nextInt(1 << 32);
});

/// Extra free hints waiting for the next board ("Head start" reward). The
/// next game controller takes them when its board is ready.
final headStartBonusProvider = NotifierProvider<HeadStartBonusController, int>(HeadStartBonusController.new);

class HeadStartBonusController extends Notifier<int> {
  @override
  int build() => 0;

  void grant(int hints) => state += hints;

  /// Returns the pending bonus and clears it.
  int take() {
    final v = state;
    if (v != 0) state = 0;
    return v;
  }
}

/// The most recent cleared board, read by the cleared screen. Outlives the
/// game controller (which is released when the board is left).
final lastClearedProvider = NotifierProvider<LastClearedController, ClearedResult?>(LastClearedController.new);

class LastClearedController extends Notifier<ClearedResult?> {
  @override
  ClearedResult? build() => null;

  void set(ClearedResult result) => state = result;
}


/// Whether the most recent clear showed an interstitial (set when
/// `AdService.onBoardCleared` completes; reset on every new clear).
final clearInterstitialShownProvider =
    NotifierProvider<ClearInterstitialShown, bool>(ClearInterstitialShown.new);

class ClearInterstitialShown extends Notifier<bool> {
  @override
  bool build() => false;

  // A setter would read oddly at call sites; keep an explicit method.
  // ignore: use_setters_to_change_properties
  void set(bool shown) => state = shown;
}
