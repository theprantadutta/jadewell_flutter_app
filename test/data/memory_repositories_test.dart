import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/catalogue.dart';
import 'package:jadewell_flutter_app/data/models/progress.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';

GameResult daily(String date) => GameResult(
      layoutId: 'turtle',
      seed: 1,
      generatorVersion: 1,
      outcome: GameOutcome.cleared,
      timeMs: 1000,
      stars: 3,
      hintsUsed: 0,
      undos: 0,
      shufflesUsed: 0,
      tilesMatched: 144,
      longestStreak: 2,
      playedAt: DateTime.utc(2026, 11, 16, 12),
      dailyDate: date,
    );

void main() {
  test('memory daily repository: streak, weekDone and repair match the Drift rules', () async {
    var now = DateTime.utc(2026, 11, 17, 12);
    final progress = MemoryProgressRepository(clock: () => now);
    final repo = MemoryDailyRepository(
      const Catalogue(chapters: [], layouts: {}, dailyPool: ['turtle']),
      progress,
      clock: () => now,
    );
    await progress.recordResult(daily('2026-11-16'));
    await progress.recordResult(daily('2026-11-17'));
    await progress.recordResult(daily('2026-11-17'));
    var s = await repo.watchToday().first;
    expect(s.streak, 2);
    expect(s.weekDone, [true, true, false, false, false, false, false]);

    now = DateTime.utc(2026, 11, 19, 12);
    expect((await repo.watchToday().first).streak, 0);
    expect(await repo.canRepairStreak(), isTrue);
    expect(await repo.repairStreak(), isTrue);
    expect(await repo.repairStreak(), isFalse);
    s = await repo.watchToday().first;
    expect(s.streak, 2);
    expect((await progress.watch().first).bestStreak, 2);
  });
}
