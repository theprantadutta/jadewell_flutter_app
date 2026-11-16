import 'dart:typed_data';

import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:test/test.dart';

/// Equality, hashing and descriptions of the small value types the UI and
/// state layer compare and log.
void main() {
  test('events', () {
    final events = <GameEvent>[
      const Selected(1),
      const Deselected(1),
      const Matched(1, 2, [3]),
      const Mismatch(1, 2),
      const Blocked(1, [2]),
      const Shuffled(7, ShuffleKind.credit, [1, 2]),
      const Undone(MatchEntry(1, 2), [3]),
      const HintShown(1, 2),
      const Deadlock(),
      const Cleared(
        ClearStats(
          elapsedMs: 1,
          hintsUsed: 0,
          shufflesUsed: 0,
          rewardedShuffles: 0,
          undos: 0,
          longestStreak: 1,
          tilesMatched: 2,
          parMs: 10,
          stars: 3,
        ),
      ),
      const Rejected(RejectReason.gameOver),
    ];
    for (final e in events) {
      expect(e.toString(), isNotEmpty);
    }
    expect(const Selected(1), const Selected(1));
    expect(const Selected(1).hashCode, const Selected(1).hashCode);
    expect(const Deselected(2), isNot(const Deselected(3)));
    expect(const Deselected(2).hashCode, const Deselected(2).hashCode);
    expect(const Mismatch(1, 2).hashCode, const Mismatch(1, 2).hashCode);
    expect(const HintShown(1, 2).hashCode, const HintShown(1, 2).hashCode);
    expect(const Deadlock().hashCode, const Deadlock().hashCode);
    expect(const Rejected(RejectReason.gameOver).hashCode, const Rejected(RejectReason.gameOver).hashCode);
  });

  test('history and log entries', () {
    expect(const MatchEntry(1, 2), const MatchEntry(1, 2));
    expect(const MatchEntry(1, 2).hashCode, const MatchEntry(1, 2).hashCode);
    expect(const MatchEntry(1, 2).toString(), contains('1'));
    expect(ShuffleEntry(Int8List(2), 5, ShuffleKind.rewarded).toString(), contains('rewarded'));
    final logs = <MoveLogEntry>[
      const LogMatch(1, 2, 3),
      const LogShuffle(ShuffleKind.deadlock, 4, 5),
      const LogHint(HintKind.rewarded),
      const LogUndo(),
    ];
    for (final e in logs) {
      expect(e.toString(), isNotEmpty);
      expect(e.hashCode, e.hashCode);
    }
    expect(const LogMatch(1, 2, 3).hashCode, const LogMatch(1, 2, 3).hashCode);
    expect(
      const LogShuffle(ShuffleKind.deadlock, 4, 5).hashCode,
      const LogShuffle(ShuffleKind.deadlock, 4, 5).hashCode,
    );
    expect(const LogHint(HintKind.credit).hashCode, const LogHint(HintKind.credit).hashCode);
    expect(const LogUndo().hashCode, const LogUndo().hashCode);
  });

  test('positions, options, tiles, sets, results', () {
    expect(const Position(1, 2, 3).hashCode, const Position(1, 2, 3).hashCode);
    expect(const Position(1, 2, 3).toString(), '(1,2,3)');
    expect(const Position(1, 2, 3).toJson(), {'x': 1, 'y': 2, 'z': 3});
    expect(DealerOptions.production.hashCode, const DealerOptions(spreadCandidates: 2).hashCode);
    expect(DealerOptions.production.toString(), contains('spreadCandidates: 2'));
    expect(kFaces[0].toString(), 'C1');
    expect(kFaces[0].copies, 4);
    expect(kFaces[34].copies, 1);
    final set = TileSet.of(64, [1, 40]);
    expect(set.hashCode, TileSet.of(64, [40, 1]).hashCode);
    expect(set.toString(), 'TileSet[1, 40]');
    expect(set.words, hasLength(2));
    expect(TileSet.fromWords(set.words), set);
    expect(set.isNotEmpty, isTrue);
    expect(const SolveUnsolvable(3).toString(), contains('unsolvable'));
    expect(const SolveUnknown(3).toString(), contains('unknown'));
    expect(const SolveSolvable([(1, 2)], 3).toString(), contains('solvable'));
    expect(DealException('x').toString(), contains('x'));
    expect(LayoutException('id', ['bad']).toString(), contains('bad'));
    expect(const ReplayResult(legal: true, cleared: false).toString(), contains('legal'));
    expect(const ReplayResult(legal: false, cleared: false, error: 'e', errorIndex: 0).toString(), contains('illegal'));
  });
}
