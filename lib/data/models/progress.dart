/// Why a layout is open.
enum UnlockSource { chapter, rewardedAd }

/// Per-layout player progress (Drift `layout_progress` + `saved_game`).
class LayoutProgress {
  const LayoutProgress({
    required this.layoutId,
    this.adUnlocked = false,
    this.bestTimeMs,
    this.bestStars = 0,
    this.clears = 0,
    this.lastPlayedAt,
    this.savedFraction,
  });

  final String layoutId;

  /// Unlocked early with a rewarded ad.
  final bool adUnlocked;
  final int? bestTimeMs;

  /// 0 = never cleared.
  final int bestStars;
  final int clears;
  final DateTime? lastPlayedAt;

  /// Fraction of tiles removed in the saved (resumable) game, or null if none.
  final double? savedFraction;

  bool get cleared => clears > 0;
  bool get hasSavedGame => savedFraction != null;

  LayoutProgress copyWith({
    bool? adUnlocked,
    int? bestTimeMs,
    int? bestStars,
    int? clears,
    DateTime? lastPlayedAt,
    double? savedFraction,
    bool clearSaved = false,
  }) =>
      LayoutProgress(
        layoutId: layoutId,
        adUnlocked: adUnlocked ?? this.adUnlocked,
        bestTimeMs: bestTimeMs ?? this.bestTimeMs,
        bestStars: bestStars ?? this.bestStars,
        clears: clears ?? this.clears,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        savedFraction: clearSaved ? null : (savedFraction ?? this.savedFraction),
      );
}

enum GameOutcome { cleared, abandoned }

/// One finished or abandoned game (Drift `game_results`).
class GameResult {
  const GameResult({
    required this.layoutId,
    required this.seed,
    required this.generatorVersion,
    required this.outcome,
    required this.timeMs,
    required this.stars,
    required this.hintsUsed,
    required this.undos,
    required this.shufflesUsed,
    required this.tilesMatched,
    required this.longestStreak,
    required this.playedAt,
    this.dailyDate,
    this.moveLog,
  });

  final String layoutId;
  final int seed;
  final int generatorVersion;
  final GameOutcome outcome;
  final int timeMs;

  /// 0 for abandoned games.
  final int stars;
  final int hintsUsed;
  final int undos;
  final int shufflesUsed;
  final int tilesMatched;
  final int longestStreak;
  final DateTime playedAt;

  /// UTC `YYYY-MM-DD` for daily games.
  final String? dailyDate;

  /// Encoded engine move log (daily games; submitted for verification).
  final String? moveLog;

  bool get isDaily => dailyDate != null;
}

/// What the cleared screen needs about personal bests.
class RecordOutcome {
  const RecordOutcome({required this.isNewBest, this.previousBestMs, required this.progress});
  final bool isNewBest;
  final int? previousBestMs;
  final LayoutProgress progress;
}

/// Aggregates for the statistics screen.
class PlayerStats {
  const PlayerStats({
    this.gamesPlayed = 0,
    this.boardsCleared = 0,
    this.tilesMatched = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.last7Days = const [0, 0, 0, 0, 0, 0, 0],
  });

  final int gamesPlayed;
  final int boardsCleared;
  final int tilesMatched;

  /// Daily-challenge day streak.
  final int currentStreak;
  final int bestStreak;

  /// Games per day, oldest first, last entry = today (local time).
  final List<int> last7Days;

  bool get isEmpty => gamesPlayed == 0;
}

/// Today's daily board for this player.
class DailyStatus {
  const DailyStatus({
    required this.date,
    required this.layoutId,
    required this.seed,
    this.firstClearMs,
    this.firstClearStars,
    this.streak = 0,
    this.weekDone = const [false, false, false, false, false, false, false],
  });

  /// UTC `YYYY-MM-DD`.
  final String date;
  final String layoutId;
  final int seed;
  final int? firstClearMs;
  final int? firstClearStars;
  final int streak;

  /// Mon..Sun of the current week: daily cleared that day.
  final List<bool> weekDone;

  bool get clearedToday => firstClearMs != null;
}
