import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/db/streak_rules.dart';

void main() {
  final d = dayFromKey('2026-11-16'); // a Monday
  final now = DateTime.utc(2026, 11, 16, 12);

  test('date keys round-trip', () {
    expect(keyFromDay(d), '2026-11-16');
    expect(keyFromDay(d - 16), '2026-10-31');
    expect(utcDateKey(DateTime.utc(2026, 1, 2, 23, 59)), '2026-01-02');
  });

  group('onDailyClear', () {
    test('starts, increments on consecutive days, ignores repeats and older boards', () {
      var s = StreakRules.onDailyClear(const StreakSnapshot(), d);
      expect((s.current, s.best, s.lastDay), (1, 1, d));
      s = StreakRules.onDailyClear(s, d + 1);
      expect((s.current, s.best), (2, 2));
      expect(identical(StreakRules.onDailyClear(s, d + 1), s), isTrue);
      expect(identical(StreakRules.onDailyClear(s, d - 3), s), isTrue);
    });

    test('a gap restarts at 1 and keeps best', () {
      var s = const StreakSnapshot(current: 5, best: 7, lastDay: 100);
      s = StreakRules.onDailyClear(s, 103);
      expect((s.current, s.best, s.brokenStreak), (1, 7, 0));
    });

    test('exactly one missed day remembers the broken streak', () {
      final s = StreakRules.onDailyClear(const StreakSnapshot(current: 5, best: 5, lastDay: 100), 102);
      expect((s.current, s.brokenStreak, s.brokenAfterDay), (1, 5, 100));
    });
  });

  group('effective', () {
    test('alive when cleared today or yesterday, else 0', () {
      final s = StreakSnapshot(current: 4, best: 4, lastDay: d - 1);
      expect(StreakRules.effective(s, d), 4);
      expect(StreakRules.effective(s, d + 1), 0);
      expect(StreakRules.effective(const StreakSnapshot(), d), 0);
    });
  });

  group('repair', () {
    test('missed yesterday, not cleared today: keeps the streak alive', () {
      final s = StreakSnapshot(current: 6, best: 6, lastDay: d - 2);
      final offer = StreakRules.repairOffer(s, d, now)!;
      expect(offer.restoredStreak, 6);
      expect(offer.missedDate, '2026-11-15');
      final r = StreakRules.repair(s, d, now)!;
      expect((r.current, r.lastDay, r.lastRepairAt), (6, d - 1, now));
      expect(StreakRules.effective(r, d), 6);
      expect(StreakRules.onDailyClear(r, d).current, 7);
    });

    test('missed yesterday, already cleared today: restores broken + today', () {
      final s = StreakRules.onDailyClear(StreakSnapshot(current: 6, best: 6, lastDay: d - 2), d);
      expect(s.current, 1);
      final offer = StreakRules.repairOffer(s, d, now)!;
      expect(offer.restoredStreak, 7);
      final r = StreakRules.repair(s, d, now)!;
      expect((r.current, r.best, r.lastDay, r.brokenStreak), (7, 7, d, 0));
      expect(StreakRules.repairOffer(r, d, now), isNull);
    });

    test('two or more missed days cannot be repaired', () {
      expect(StreakRules.repairOffer(StreakSnapshot(current: 6, lastDay: d - 3), d, now), isNull);
      final s = StreakRules.onDailyClear(StreakSnapshot(current: 6, lastDay: d - 3), d);
      expect(StreakRules.repairOffer(s, d, now), isNull);
    });

    test('nothing to repair when the streak is alive or empty', () {
      expect(StreakRules.repairOffer(StreakSnapshot(current: 3, lastDay: d - 1), d, now), isNull);
      expect(StreakRules.repairOffer(const StreakSnapshot(), d, now), isNull);
    });

    test('at most once per 7 days', () {
      final s = StreakSnapshot(current: 6, lastDay: d - 2, lastRepairAt: now.subtract(const Duration(days: 6, hours: 23)));
      expect(StreakRules.repairOffer(s, d, now), isNull);
      expect(StreakRules.repair(s, d, now), isNull);
      final later = StreakSnapshot(current: 6, lastDay: d - 2, lastRepairAt: now.subtract(const Duration(days: 7)));
      expect(StreakRules.repairOffer(later, d, now), isNotNull);
    });
  });
}
