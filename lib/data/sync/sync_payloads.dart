import '../models/progress.dart';

/// Payloads of the outbox items pushed to `POST /sync/batch` (one place for
/// the wire format; keys are snake_case, times ISO-8601 UTC).
abstract final class SyncPayloads {
  static String iso(DateTime t) => t.toUtc().toIso8601String();

  static Map<String, Object?> gameResult(String resultId, GameResult r) => {
        'result_id': resultId,
        'layout_id': r.layoutId,
        'seed': r.seed,
        'generator_version': r.generatorVersion,
        'outcome': r.outcome.name,
        'time_ms': r.timeMs,
        'stars': r.stars,
        'hints_used': r.hintsUsed,
        'undos': r.undos,
        'shuffles_used': r.shufflesUsed,
        'tiles_matched': r.tilesMatched,
        'longest_streak': r.longestStreak,
        'played_at': iso(r.playedAt),
        'daily_date': r.dailyDate,
      };

  static Map<String, Object?> personalBest(String resultId, GameResult r, LayoutProgress p) => {
        'result_id': resultId,
        'layout_id': p.layoutId,
        'best_time_ms': p.bestTimeMs,
        'best_stars': p.bestStars,
        'clears': p.clears,
        'seed': r.seed,
        'generator_version': r.generatorVersion,
        'achieved_at': iso(r.playedAt),
      };

  static Map<String, Object?> dailyResult(String resultId, GameResult r) => {
        'result_id': resultId,
        'date': r.dailyDate,
        'layout_id': r.layoutId,
        'seed': r.seed,
        'generator_version': r.generatorVersion,
        'time_ms': r.timeMs,
        'stars': r.stars,
        'hints_used': r.hintsUsed,
        'undos': r.undos,
        'shuffles_used': r.shufflesUsed,
        'move_log': r.moveLog,
        'cleared_at': iso(r.playedAt),
      };

  static Map<String, Object?> stats({
    required int gamesPlayed,
    required int boardsCleared,
    required int tilesMatched,
    required int currentStreak,
    required int bestStreak,
    required String? lastDailyDate,
  }) =>
      {
        'games_played': gamesPlayed,
        'boards_cleared': boardsCleared,
        'tiles_matched': tilesMatched,
        'current_streak': currentStreak,
        'best_streak': bestStreak,
        'last_daily_date': lastDailyDate,
      };

  static Map<String, Object?> layoutUnlock(String layoutId, DateTime at) => {
        'layout_id': layoutId,
        'source': 'rewarded_ad',
        'unlocked_at': iso(at),
      };

  static Map<String, Object?> streakRepair({required String missedDate, required int streak, required DateTime at}) => {
        'missed_date': missedDate,
        'streak': streak,
        'repaired_at': iso(at),
      };

  static Map<String, Object?> reset(DateTime at) => {'reset_at': iso(at)};
}
