import 'package:flutter/foundation.dart';

import '../../data/models/catalogue.dart';
import '../../engine/commands.dart' as commands show hintAvailability, shuffleAvailability;
import '../../engine/engine.dart';
import 'game_launch.dart';

enum GamePhase {
  /// Catalogue, saved game or deal still loading.
  loading,

  /// A board is in play (possibly paused).
  playing,

  /// The last pair was matched; [GameViewState.result] is set.
  cleared,

  /// The layout could not be loaded or dealt.
  failed,
}

/// Why the clock is paused (beyond app focus and ads).
enum PauseReason {
  /// The player tapped the timer pill (or opened the quit confirmation).
  user,

  /// The app went to the background; the screen shows the pause card on return.
  background,
}

/// A rewarded ad is playing for this.
enum RewardBusy { hint, shuffle, secondChance }

/// What the cleared screen shows, produced when the board is cleared.
@immutable
class ClearedResult {
  const ClearedResult({
    required this.layoutId,
    required this.layoutName,
    required this.chapterId,
    required this.chapterName,
    required this.tileCount,
    required this.isDaily,
    required this.stats,
    required this.stars,
    required this.isNewBest,
    required this.previousBestMs,
    required this.firstClear,
    this.dailyDate,
  });

  final String layoutId;
  final String layoutName;
  final String chapterId;
  final String chapterName;
  final int tileCount;
  final bool isDaily;
  final ClearStats stats;

  /// 1–3 (from `starsFor` with the layout's par).
  final int stars;
  final bool isNewBest;
  final int? previousBestMs;

  /// The first time this layout was cleared (a new collection segment).
  final bool firstClear;
  final String? dailyDate;

  int get timeMs => stats.elapsedMs;

  /// How much faster than the previous best, if this is a new best.
  int? get improvementMs => isNewBest && previousBestMs != null ? previousBestMs! - timeMs : null;
}

/// Immutable view of one board for widgets. Widgets `select` the slice they
/// render (tiles left, pairs open, hint, paused, …) so nothing rebuilds per
/// frame; animations come from the controller's event stream instead.
@immutable
class GameViewState {
  const GameViewState({
    required this.launch,
    this.phase = GamePhase.loading,
    this.info,
    this.chapterName = '',
    this.game,
    this.dealId = 0,
    this.pauseReason,
    this.hint,
    this.combo = 0,
    this.busy,
    this.resumed = false,
    this.dailyDate,
    this.result,
    this.error,
  });

  final GameLaunch launch;
  final GamePhase phase;

  /// The resolved layout (for the daily, today's layout).
  final LayoutInfo? info;
  final String chapterName;
  final GameState? game;

  /// Bumps on every new deal and restart: the board replays its entry.
  final int dealId;

  /// Non-null while paused (pause card, quit confirmation, background).
  final PauseReason? pauseReason;

  /// The hinted pair while the hint is showing (clears after 2.1 s or a tap).
  final (int, int)? hint;

  /// Matches in a row with at most 4 s between each (chip from ×3).
  final int combo;

  /// A rewarded ad is playing.
  final RewardBusy? busy;

  /// The board was restored from a saved game.
  final bool resumed;

  /// UTC `YYYY-MM-DD` for the daily board.
  final String? dailyDate;
  final ClearedResult? result;
  final Object? error;

  bool get paused => pauseReason != null;
  bool get isDaily => launch.daily;
  String get layoutName => info?.name ?? '';
  int get tilesLeft => game == null ? 0 : game!.layout.length - game!.tilesMatched;
  int get totalTiles => game?.layout.length ?? 0;

  /// Matching free pairs right now (the "N pairs open" chip).
  int get pairsOpen => game?.availableMoves.length ?? 0;
  int get freeHintsLeft => game?.freeHintsLeft ?? 0;
  int get freeShufflesLeft => game?.freeShufflesLeft ?? 0;
  bool get canUndo => phase == GamePhase.playing && (game?.history.isNotEmpty ?? false);
  bool get deadlocked => phase == GamePhase.playing && (game?.isDeadlocked ?? false);

  HintAvailability get hintAvailability => game == null ? HintAvailability.none : commands.hintAvailability(game!);
  ShuffleAvailability get shuffleAvailability =>
      game == null ? ShuffleAvailability.none : commands.shuffleAvailability(game!);

  GameViewState copyWith({
    GamePhase? phase,
    LayoutInfo? info,
    String? chapterName,
    GameState? game,
    int? dealId,
    PauseReason? Function()? pauseReason,
    (int, int)? Function()? hint,
    int? combo,
    RewardBusy? Function()? busy,
    bool? resumed,
    String? dailyDate,
    ClearedResult? result,
    Object? error,
  }) => GameViewState(
    launch: launch,
    phase: phase ?? this.phase,
    info: info ?? this.info,
    chapterName: chapterName ?? this.chapterName,
    game: game ?? this.game,
    dealId: dealId ?? this.dealId,
    pauseReason: pauseReason != null ? pauseReason() : this.pauseReason,
    hint: hint != null ? hint() : this.hint,
    combo: combo ?? this.combo,
    busy: busy != null ? busy() : this.busy,
    resumed: resumed ?? this.resumed,
    dailyDate: dailyDate ?? this.dailyDate,
    result: result ?? this.result,
    error: error ?? this.error,
  );
}
