import 'dart:convert';

import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Row of four loose tiles with faces [1, 1, 2, 2] laid out so every tile is free.
(Layout, GameState) looseFour({int? parMs}) {
  final l = tinyLayout([(0, 0, 0), (4, 0, 0), (8, 0, 0), (12, 0, 0)], parMs: parMs);
  return (l, gameWithFaces(l, [1, 1, 2, 2], parMs: parMs));
}

/// Crossed stacks plus two loose Cs: only C–C can be matched, then deadlock.
/// Stack 1 at x=0: bottom A(1), top B(2). Stack 2 at x=4: bottom B(2), top A(1).
(Layout, GameState) crossedStacks() {
  final l = tinyLayout([(0, 0, 0), (0, 0, 1), (4, 0, 0), (4, 0, 1), (8, 0, 0), (12, 0, 0)]);
  final faces = List.filled(6, 0);
  faces[idx(l, 0, 0, 0)] = 1;
  faces[idx(l, 0, 0, 1)] = 2;
  faces[idx(l, 4, 0, 0)] = 2;
  faces[idx(l, 4, 0, 1)] = 1;
  faces[idx(l, 8, 0, 0)] = 3;
  faces[idx(l, 12, 0, 0)] = 3;
  return (l, gameWithFaces(l, faces));
}

void main() {
  group('selection model', () {
    test('tap free A selects, tap A again deselects', () {
      final (_, s0) = looseFour();
      final (s1, e1) = select(s0, 0);
      expect(e1, [const Selected(0)]);
      expect(s1.selected, 0);
      final (s2, e2) = select(s1, 0);
      expect(e2, [const Deselected(0)]);
      expect(s2.selected, isNull);
    });

    test('tap matching B matches; non-matching B mismatches and becomes the selection', () {
      final (_, s0) = looseFour();
      final s1 = select(s0, 0).$1;
      final (s2, e2) = select(s1, 2);
      expect(e2, [const Mismatch(0, 2), const Selected(2)]);
      expect(s2.selected, 2);
      expect(s2.removed.isEmpty, isTrue);
      final (s3, e3) = select(s2, 3, elapsedMs: 1200);
      expect(e3.first, isA<Matched>());
      final m = e3.first as Matched;
      expect((m.a, m.b), (2, 3));
      expect(s3.selected, isNull);
      expect(s3.removed.toList(), [2, 3]);
      expect(s3.tilesMatched, 2);
      expect(s3.history, [const MatchEntry(2, 3)]);
      expect(s3.moveLog, [const LogMatch(2, 3, 1200)]);
    });

    test('tap blocked tile gives Blocked with blockers, selection unchanged', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (4, 0, 0), (2, 0, 1)]);
      final s0 = gameWithFaces(l, [1, 2, 1, 2]);
      final s1 = select(s0, 0).$1;
      final (s2, e2) = select(s1, 1);
      expect(e2, hasLength(1));
      final b = e2.single as Blocked;
      expect(b.tile, 1);
      expect(b.blockers, [0, 2, 3]);
      expect(s2.selected, 0);
    });

    test('taps on removed or out-of-range positions do nothing', () {
      final (_, s0) = looseFour();
      final s1 = match(s0, 0, 1).$1;
      expect(identical(select(s1, 0).$1, s1), isTrue);
      expect(select(s1, 0).$2, isEmpty);
      expect(select(s1, 99).$2, isEmpty);
      expect(select(s1, -1).$2, isEmpty);
    });

    test('Matched reports freed tiles', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (4, 0, 0), (8, 0, 0)]);
      // Middle tile 1 is side-blocked; removing 0 and 3 frees it.
      final s0 = gameWithFaces(l, [5, 6, 6, 5]);
      final (_, e) = match(s0, 0, 3);
      expect((e.first as Matched).freed, [1]);
    });

    test('streaks: consecutive matches, reset by mismatch and undo', () {
      final l = tinyLayout([for (var x = 0; x < 6; x++) (4 * x, 0, 0)]);
      var s = gameWithFaces(l, [1, 1, 2, 2, 3, 3]);
      s = match(s, 0, 1).$1;
      s = match(s, 2, 3).$1;
      expect((s.currentStreak, s.longestStreak), (2, 2));
      s = select(s, 4).$1;
      s = undo(s).$1;
      expect((s.currentStreak, s.longestStreak), (0, 2));
      s = match(s, 2, 3).$1;
      s = select(select(s, 4).$1, 0).$1; // 0 is removed: no-op
      s = select(s, 5).$1; // completes 4–5
      expect((s.currentStreak, s.longestStreak), (2, 2));
    });
  });

  group('clear and stars', () {
    test('clearing emits Cleared with stats and stars', () {
      final (_, s0) = looseFour(parMs: 10000);
      var (s, _) = match(s0, 0, 1, elapsedMs: 3000);
      s = hint(s).$1;
      final (s2, e) = match(s, 2, 3, elapsedMs: 8000);
      expect(s2.isCleared, isTrue);
      expect(e, hasLength(2));
      final stats = (e.last as Cleared).stats;
      expect(stats.elapsedMs, 8000);
      expect(stats.hintsUsed, 1);
      expect(stats.tilesMatched, 4);
      expect(stats.stars, 3);
      expect(stats.longestStreak, 2);
      // Nothing works after the clear.
      expect(undo(s2).$2, [const Rejected(RejectReason.gameOver)]);
      expect(hint(s2).$2, [const Rejected(RejectReason.gameOver)]);
      expect(shuffle(s2, free: false, rewarded: false).$2, [const Rejected(RejectReason.gameOver)]);
      expect(select(s2, 0).$2, isEmpty);
      expect(hintAvailability(s2), HintAvailability.none);
      expect(shuffleAvailability(s2), ShuffleAvailability.none);
    });

    test('no par → no stars', () {
      final (_, s0) = looseFour();
      final e = match(match(s0, 0, 1).$1, 2, 3).$2;
      expect((e.last as Cleared).stats.stars, isNull);
    });

    test('starsFor table', () {
      int st(int t, int h, int r) => starsFor(timeMs: t, parMs: 1000, hintsUsed: h, rewardedShuffles: r);
      expect(st(1000, 1, 0), 3);
      expect(st(1000, 0, 0), 3);
      expect(st(1001, 0, 0), 2);
      expect(st(1000, 2, 0), 2);
      expect(st(1000, 0, 1), 2);
      expect(st(1500, 9, 0), 2); // time ≤ 1.5 × par
      expect(st(1501, 3, 0), 2); // hints ≤ 3
      expect(st(1501, 4, 0), 1);
      expect(st(99999, 4, 5), 1);
    });

    test('undo and free shuffles never cost stars; rewarded shuffles do', () {
      final (_, s0) = crossedStacks();
      var s = s0.copyWith(); // par set below via clearStats
      s = match(s, idx(s.layout, 8, 0, 0), idx(s.layout, 12, 0, 0), elapsedMs: 100).$1;
      expect(s.isDeadlocked, isTrue);
      s = shuffle(s, free: true, rewarded: false, elapsedMs: 200).$1;
      s = undo(s).$1;
      s = shuffle(s, free: true, rewarded: false, elapsedMs: 300).$1;
      expect(s.rewardedShuffles, 0);
      expect(s.undos, 1);
      final moves = s.availableMoves;
      s = match(s, moves.first.$1, moves.first.$2, elapsedMs: 400).$1;
      final last = s.availableMoves.first;
      final stats = (match(s, last.$1, last.$2, elapsedMs: 500).$2.last as Cleared).stats;
      expect(starsFor(timeMs: stats.elapsedMs, parMs: 1000, hintsUsed: 0, rewardedShuffles: stats.rewardedShuffles), 3);
      expect(stats.shufflesUsed, 2);
      expect(stats.undos, 1);
    });
  });

  group('deadlock', () {
    test('detected after a match', () {
      final (l, s0) = crossedStacks();
      final (s1, e) = match(s0, idx(l, 8, 0, 0), idx(l, 12, 0, 0));
      expect(e, [isA<Matched>(), const Deadlock()]);
      expect(s1.isDeadlocked, isTrue);
      expect(s1.availableMoves, isEmpty);
    });

    test('hint is never offered on deadlock and consumes nothing', () {
      final (l, s0) = crossedStacks();
      final s1 = match(s0, idx(l, 8, 0, 0), idx(l, 12, 0, 0)).$1;
      expect(hintAvailability(s1), HintAvailability.noMoves);
      final (s2, e) = hint(s1);
      expect(e, [const Deadlock()]);
      expect(identical(s2, s1), isTrue);
      expect(findHint(s1), isNull);
      // Even with no credits left, deadlock wins over the ad offer.
      final broke = s1.copyWith(freeHintsLeft: 0);
      expect(hintAvailability(broke), HintAvailability.noMoves);
      expect(hint(broke).$2, [const Deadlock()]);
    });

    test('free deadlock shuffle makes it solvable; undo restores the deadlock', () {
      final (l, s0) = crossedStacks();
      final s1 = match(s0, idx(l, 8, 0, 0), idx(l, 12, 0, 0)).$1;
      expect(shuffleAvailability(s1), ShuffleAvailability.deadlockFree);
      final (s2, e2) = shuffle(s1, free: true, rewarded: false);
      expect(e2.single, isA<Shuffled>());
      expect((e2.single as Shuffled).kind, ShuffleKind.deadlock);
      expect(s2.isDeadlocked, isFalse);
      expect(solve(l, s2.faces, remaining: s2.remaining), isA<SolveSolvable>());
      expect(s2.freeShufflesLeft, kFreeShufflesPerBoard);
      expect(s2.shufflesUsed, 1);
      final (s3, e3) = undo(s2);
      expect(e3, [isA<Undone>(), const Deadlock()]);
      expect(s3.faces, s1.faces);
      expect(s3.isDeadlocked, isTrue);
    });

    test('free shuffle is refused while moves exist', () {
      final (_, s0) = looseFour();
      expect(shuffle(s0, free: true, rewarded: false).$2, [const Rejected(RejectReason.notDeadlocked)]);
      expect(() => shuffle(s0, free: true, rewarded: true), throwsArgumentError);
    });

    test('shuffle impossible when the remaining tiles are stacked', () {
      final l = tinyLayout([(0, 0, 0), (0, 0, 1), (4, 0, 0), (8, 0, 0)]);
      final faces = List.filled(4, 0);
      faces[idx(l, 0, 0, 0)] = 7;
      faces[idx(l, 0, 0, 1)] = 7;
      faces[idx(l, 4, 0, 0)] = 8;
      faces[idx(l, 8, 0, 0)] = 8;
      final s = match(gameWithFaces(l, faces), idx(l, 4, 0, 0), idx(l, 8, 0, 0)).$1;
      expect(s.isDeadlocked, isTrue);
      expect(shuffle(s, free: true, rewarded: false).$2, [const Rejected(RejectReason.shuffleImpossible)]);
    });
  });

  group('shuffle on the turtle', () {
    final turtle = loadLayout('turtle');

    test('credits, rewarded, grants; sub-seeds follow the shuffle count; multiset kept; solvable', () {
      var s = GameState.newGame(turtle, 42);
      expect(s.verifiedBySolver, isTrue);
      final d = deal(turtle, 42);
      for (final (a, b) in d.solution.take(20)) {
        s = match(s, a, b).$1;
      }
      final facesBefore = s.remainingFaces..sort();
      s = select(s, s.freeTiles.first).$1;
      final (s1, e1) = shuffle(s, free: false, rewarded: false);
      expect(e1.first, Deselected(s.selected!));
      final sh = e1[1] as Shuffled;
      expect(sh.subSeed, shuffleSeed(42, 0));
      expect(sh.positions, s.remaining.toList());
      expect(s1.remainingFaces..sort(), facesBefore);
      expect(s1.removed, s.removed);
      expect(s1.faces, isNot(s.faces));
      expect(solve(turtle, s1.faces, remaining: s1.remaining), isA<SolveSolvable>());
      expect(s1.freeShufflesLeft, 1);

      final s2 = undo(s1).$1;
      expect(s2.faces, s.faces);
      expect(s2.freeShufflesLeft, 1, reason: 'undo does not refund');
      final s3 = shuffle(s2, free: false, rewarded: false).$1;
      expect((s3.history.last as ShuffleEntry).subSeed, shuffleSeed(42, 1));
      expect(s3.freeShufflesLeft, 0);
      expect(shuffleAvailability(s3), ShuffleAvailability.needsReward);
      expect(shuffle(s3, free: false, rewarded: false).$2, [const Rejected(RejectReason.noShuffleCredits)]);
      final s4 = shuffle(s3, free: false, rewarded: true).$1;
      expect(s4.rewardedShuffles, 1);
      expect((s4.history.last as ShuffleEntry).subSeed, shuffleSeed(42, 2));
      final s5 = grantShuffle(s4).$1;
      expect(s5.freeShufflesLeft, 1);
      expect(shuffleAvailability(s5), ShuffleAvailability.free);
      expect(s5.shufflesUsed, 3);
      expect(s5.shuffleCount, 3);
    });

    test('shuffles from many states are solver-verified', () {
      for (var seed = 0; seed < 25; seed++) {
        var s = GameState.newGame(turtle, seed, options: DealerOptions.unbiased);
        final d = deal(turtle, seed, options: DealerOptions.unbiased);
        for (final (a, b) in d.solution.take((seed * 7) % 70)) {
          s = match(s, a, b).$1;
        }
        final (s1, e) = shuffle(s, free: false, rewarded: true);
        expect(e.whereType<Shuffled>(), hasLength(1), reason: 'seed $seed');
        expect(solve(turtle, s1.faces, remaining: s1.remaining), isA<SolveSolvable>(), reason: 'seed $seed');
      }
    });
  });

  group('hint', () {
    final turtle = loadLayout('turtle');

    test('suggests a legal pair that keeps the board solvable', () {
      for (var seed = 0; seed < 20; seed++) {
        var s = GameState.newGame(turtle, seed);
        final d = deal(turtle, seed);
        for (final (a, b) in d.solution.take(seed * 3)) {
          s = match(s, a, b).$1;
        }
        final (s1, e) = hint(s);
        final h = e.single as HintShown;
        expect(s.availableMoves, contains((h.a, h.b)));
        final after = match(s, h.a, h.b).$1;
        expect(solve(turtle, after.faces, remaining: after.remaining), isA<SolveSolvable>());
        expect(s1.hintsUsed, 1);
        expect(s1.freeHintsLeft, kFreeHintsPerBoard - 1);
        expect(s1.moveLog.last, const LogHint(HintKind.credit));
        expect(s1.faces, s.faces);
      }
    });

    test('falls back to any pair when the solver budget is tiny', () {
      final s = GameState.newGame(turtle, 5);
      final h = findHint(s, budget: 1)!;
      expect(s.availableMoves, contains(h));
    });

    test('credits, reward and grants', () {
      var s = GameState.newGame(turtle, 9);
      for (var i = 0; i < kFreeHintsPerBoard; i++) {
        expect(hintAvailability(s), HintAvailability.free);
        s = hint(s).$1;
      }
      expect(hintAvailability(s), HintAvailability.needsReward);
      expect(hint(s).$2, [const Rejected(RejectReason.noHintCredits)]);
      s = hint(s, rewarded: true).$1;
      expect(s.hintsUsed, 4);
      expect(s.moveLog.last, const LogHint(HintKind.rewarded));
      s = grantHint(s, count: 2).$1;
      expect(s.freeHintsLeft, 2);
    });
  });

  group('undo', () {
    test('restores the pair, reports reblocked tiles, drops the selection', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (4, 0, 0), (8, 0, 0)]);
      var s = gameWithFaces(l, [5, 6, 6, 5]);
      s = match(s, 0, 3).$1;
      s = select(s, 1).$1;
      final (s1, e) = undo(s);
      expect(e[0], const Deselected(1));
      final u = e[1] as Undone;
      expect(u.entry, const MatchEntry(0, 3));
      expect(u.reblocked, [1]);
      expect(s1.removed.isEmpty, isTrue);
      expect(s1.selected, isNull);
      expect(s1.undos, 1);
      expect(s1.tilesMatched, 0);
      expect(s1.moveLog.last, const LogUndo());
    });

    test('empty history is rejected', () {
      final (_, s0) = looseFour();
      expect(undo(s0).$2, [const Rejected(RejectReason.nothingToUndo)]);
    });

    test('unlimited undo back to the start', () {
      final turtle = loadLayout('turtle');
      final start = GameState.newGame(turtle, 77);
      var s = start;
      for (final (a, b) in deal(turtle, 77).solution.take(40)) {
        s = match(s, a, b).$1;
      }
      s = shuffle(s, free: false, rewarded: false).$1;
      while (s.history.isNotEmpty) {
        s = undo(s).$1;
      }
      expect(s.faces, start.faces);
      expect(s.removed.isEmpty, isTrue);
      expect(s.undos, 41);
    });
  });

  group('match command', () {
    test('rejects illegal pairs', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (4, 0, 0), (2, 0, 1)]);
      final s = gameWithFaces(l, [1, 2, 1, 2]);
      expect(match(s, 0, 0).$2, [const Rejected(RejectReason.illegalMove)]);
      expect(match(s, 1, 3).$2, [const Rejected(RejectReason.illegalMove)], reason: 'blocked');
      expect(match(s, 0, 3).$2, [const Rejected(RejectReason.illegalMove)], reason: 'faces differ');
      expect(match(s, 0, 9).$2, [const Rejected(RejectReason.illegalMove)]);
      expect(match(s, 0, 2).$2.first, isA<Matched>());
    });

    test('elapsed time never goes backwards in the log', () {
      final (_, s0) = looseFour();
      final s1 = match(s0, 0, 1, elapsedMs: 5000).$1;
      final s2 = match(s1, 2, 3, elapsedMs: 4000).$1;
      expect(s2.moveLog.last, const LogMatch(2, 3, 5000));
    });
  });

  group('newGame', () {
    test('deterministic and verified', () {
      final turtle = loadLayout('turtle');
      final a = GameState.newGame(turtle, 1234);
      final b = GameState.newGame(turtle, 1234);
      expect(a.faces, b.faces);
      expect(a.verifiedBySolver, isTrue);
      expect(a.parMs, 360000);
      expect(a.freeHintsLeft, 3);
      expect(a.freeShufflesLeft, 2);
      expect(a.generatorVersion, kGeneratorVersion);
      expect(GameState.newGame(turtle, 1234, verify: false).verifiedBySolver, isFalse);
    });

    test('JSON snapshot round trip', () {
      final turtle = loadLayout('turtle');
      var s = GameState.newGame(turtle, 31);
      for (final (a, b) in deal(turtle, 31).solution.take(10)) {
        s = match(s, a, b, elapsedMs: 1000).$1;
      }
      s = hint(s).$1;
      s = shuffle(s, free: false, rewarded: false, elapsedMs: 2000).$1;
      s = select(s, s.freeTiles.first).$1;
      final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>;
      final r = GameState.fromJson(turtle, json);
      expect(r.faces, s.faces);
      expect(r.removed, s.removed);
      expect(r.selected, s.selected);
      expect(r.history.length, s.history.length);
      expect((r.history.last as ShuffleEntry).previousFaces, (s.history.last as ShuffleEntry).previousFaces);
      expect(r.moveLog, s.moveLog);
      expect(r.toJson(), s.toJson());
      // And the restored state keeps playing identically.
      final u1 = undo(r).$1, u2 = undo(s).$1;
      expect(u1.faces, u2.faces);
      expect(() => GameState.fromJson(loadLayout('turtle'), {...json, 'generatorVersion': 2}), throwsFormatException);
      expect(
        () => GameState.fromJson(turtle, {
          ...json,
          'faces': [1, 2],
        }),
        throwsFormatException,
      );
    });
  });
}
