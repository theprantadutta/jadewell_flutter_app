import 'package:shared_preferences/shared_preferences.dart';

import 'ad_gate.dart';

/// [AdGateCounters] in SharedPreferences (device-only, never synced: the
/// cadence belongs to this install).
class SharedPrefsAdGateStore implements AdGateStore {
  SharedPrefsAdGateStore(this._prefs);

  final SharedPreferences _prefs;

  static const kCompletedBoards = 'ads.completed_boards';
  static const kBoardsSinceInterstitial = 'ads.boards_since_interstitial';
  static const kLastInterstitialMs = 'ads.last_interstitial_ms';
  static const kLastFullScreenMs = 'ads.last_fullscreen_ms';

  @override
  AdGateCounters read() => AdGateCounters(
        completedBoards: _prefs.getInt(kCompletedBoards) ?? 0,
        boardsSinceInterstitial: _prefs.getInt(kBoardsSinceInterstitial) ?? 0,
        lastInterstitialMs: _prefs.getInt(kLastInterstitialMs),
        lastFullScreenMs: _prefs.getInt(kLastFullScreenMs),
      );

  @override
  Future<void> write(AdGateCounters c) async {
    await _prefs.setInt(kCompletedBoards, c.completedBoards);
    await _prefs.setInt(kBoardsSinceInterstitial, c.boardsSinceInterstitial);
    await _setOrRemove(kLastInterstitialMs, c.lastInterstitialMs);
    await _setOrRemove(kLastFullScreenMs, c.lastFullScreenMs);
  }

  Future<void> _setOrRemove(String key, int? value) =>
      value == null ? _prefs.remove(key) : _prefs.setInt(key, value);
}
