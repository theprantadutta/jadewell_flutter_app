import '../../engine/daily.dart';

/// UTC `YYYY-MM-DD` of [t]'s calendar day.
String utcDateKey(DateTime t) {
  final d = t.toUtc();
  return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// Day number (days since 1970-01-01) of a `YYYY-MM-DD` key.
int dayFromKey(String key) {
  final p = key.split('-');
  return utcDayNumber(DateTime.utc(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])));
}

/// `YYYY-MM-DD` of a day number.
String keyFromDay(int day) =>
    utcDateKey(DateTime.fromMillisecondsSinceEpoch(day * Duration.millisecondsPerDay, isUtc: true));

/// Daily streak state (Drift `streak` row; days are UTC day numbers).
class StreakSnapshot {
  const StreakSnapshot({
    this.current = 0,
    this.best = 0,
    this.lastDay,
    this.lastRepairAt,
    this.brokenStreak = 0,
    this.brokenAfterDay,
  });

  /// Stored streak; see [StreakRules.effective] for the displayed value.
  final int current;
  final int best;

  /// Last day cleared (or bridged by a repair).
  final int? lastDay;
  final DateTime? lastRepairAt;

  /// The streak lost when a clear followed exactly one missed day.
  final int brokenStreak;
  final int? brokenAfterDay;
}

/// A broken streak that a rewarded ad can restore right now.
class StreakRepairOffer {
  const StreakRepairOffer({required this.restoredStreak, required this.missedDate});

  /// The live streak after the repair.
  final int restoredStreak;

  /// UTC `YYYY-MM-DD` of the missed day the repair bridges.
  final String missedDate;
}

/// Daily streak = consecutive UTC days with a cleared daily. A repair
/// bridges exactly one missed day (yesterday), at most once per 7 days.
abstract final class StreakRules {
  static const repairCooldown = Duration(days: 7);

  /// The first clear of [day]'s daily.
  static StreakSnapshot onDailyClear(StreakSnapshot s, int day) {
    final last = s.lastDay;
    if (last != null && day <= last) return s; // already counted, or an older board
    int current;
    var brokenStreak = 0;
    int? brokenAfter;
    if (last == null) {
      current = 1;
    } else if (day == last + 1) {
      current = s.current + 1;
    } else {
      current = 1;
      if (day == last + 2 && s.current > 0) {
        brokenStreak = s.current;
        brokenAfter = last;
      }
    }
    return StreakSnapshot(
      current: current,
      best: current > s.best ? current : s.best,
      lastDay: day,
      lastRepairAt: s.lastRepairAt,
      brokenStreak: brokenStreak,
      brokenAfterDay: brokenAfter,
    );
  }

  /// The streak shown today: the stored one while it can still continue
  /// (cleared today or yesterday), else 0.
  static int effective(StreakSnapshot s, int today) {
    final last = s.lastDay;
    return last != null && last >= today - 1 ? s.current : 0;
  }

  static StreakRepairOffer? repairOffer(StreakSnapshot s, int today, DateTime now) {
    final lastRepair = s.lastRepairAt;
    if (lastRepair != null && now.difference(lastRepair) < repairCooldown) return null;
    final missed = keyFromDay(today - 1);
    // Missed yesterday, today not cleared yet.
    if (s.lastDay == today - 2 && s.current > 0) {
      return StreakRepairOffer(restoredStreak: s.current, missedDate: missed);
    }
    // Missed yesterday, already cleared today (streak restarted at 1).
    if (s.lastDay == today && s.brokenAfterDay == today - 2 && s.brokenStreak > 0) {
      return StreakRepairOffer(restoredStreak: s.brokenStreak + s.current, missedDate: missed);
    }
    return null;
  }

  /// Applies the repair, or returns null when [repairOffer] is null.
  static StreakSnapshot? repair(StreakSnapshot s, int today, DateTime now) {
    final offer = repairOffer(s, today, now);
    if (offer == null) return null;
    final current = offer.restoredStreak;
    return StreakSnapshot(
      current: current,
      best: current > s.best ? current : s.best,
      lastDay: s.lastDay == today ? today : today - 1,
      lastRepairAt: now,
    );
  }
}
