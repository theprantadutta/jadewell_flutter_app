import 'dart:convert';
import 'dart:io';

import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

String hex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Move log that plays the dealer's own solution, 2 s per pair.
List<MoveLogEntry> solutionLog(Deal d) => [
  for (var k = 0; k < d.solution.length; k++) LogMatch(d.solution[k].$1, d.solution[k].$2, (k + 1) * 2000),
];

void main() {
  final turtle = loadLayout('turtle');

  group('encoding', () {
    test('round trip of every entry kind, edge values included', () {
      final entries = <MoveLogEntry>[
        const LogHint(HintKind.credit),
        const LogMatch(0, 143, 0),
        const LogMatch(127, 128, 127),
        const LogShuffle(ShuffleKind.credit, 0, 128),
        const LogShuffle(ShuffleKind.rewarded, 0xFFFFFFFF, 100000),
        const LogShuffle(ShuffleKind.deadlock, 0x80000000, 100000),
        const LogUndo(),
        const LogHint(HintKind.rewarded),
        const LogMatch(5, 6, 0xFFFFFFFF),
      ];
      final encoded = encodeMoveLog(entries);
      expect(encoded, isNot(contains('=')));
      expect(encoded, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(decodeMoveLog(encoded), entries);
      expect(decodeMoveLogBytes(encodeMoveLogBytes(entries)), entries);
      expect(encodeMoveLog(const []), 'AQ');
      expect(decodeMoveLog('AQ'), isEmpty);
    });

    test('exact bytes (documented example in docs/ENGINE.md)', () {
      final bytes = encodeMoveLogBytes(const [
        LogMatch(3, 140, 1500),
        LogHint(HintKind.credit),
        LogShuffle(ShuffleKind.credit, 0xDEADBEEF, 2000),
        LogUndo(),
      ]);
      expect(hex(bytes), '0100038c01dc0b0401efbeaddef40306');
      expect(base64Url.encode(bytes).replaceAll('=', ''), 'AQADjAHcCwQB776t3vQDBg');
    });

    test('padding is optional when decoding', () {
      const entries = [LogMatch(1, 2, 3)];
      final encoded = encodeMoveLog(entries);
      expect(decodeMoveLog(base64Url.normalize(encoded)), entries);
    });

    test('rejects malformed input', () {
      expect(() => decodeMoveLogBytes(const []), throwsFormatException);
      expect(() => decodeMoveLogBytes(const [2]), throwsFormatException, reason: 'version');
      expect(() => decodeMoveLogBytes(const [1, 0, 3]), throwsFormatException, reason: 'truncated');
      expect(() => decodeMoveLogBytes(const [1, 9]), throwsFormatException, reason: 'unknown tag');
      expect(() => decodeMoveLogBytes(const [1, 0, 0x80, 0x80, 0x80, 0x80, 0x80, 1, 1]), throwsFormatException);
      expect(
        () => decodeMoveLogBytes(const [1, 0, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F, 1, 1]),
        throwsFormatException,
        reason: 'varint above 2^32 - 1',
      );
      expect(() => decodeMoveLogBytes(const [1, 1, 0, 0]), throwsFormatException, reason: 'short sub-seed');
      expect(() => decodeMoveLog('!!!'), throwsFormatException);
    });

    test('encoder refuses time going backwards', () {
      expect(() => encodeMoveLog(const [LogMatch(1, 2, 10), LogMatch(3, 4, 5)]), throwsArgumentError);
    });

    test('a full 72-match log stays compact', () {
      final d = deal(turtle, 42);
      final encoded = encodeMoveLog(solutionLog(d));
      expect(encoded.length, lessThan(600));
    });
  });

  group('replay', () {
    test("accepts the dealer's solution and reports time and stars", () {
      for (final seed in [0, 42, 0xFFFFFFFF, dailySeed(DateTime.utc(2026, 11, 16), 'turtle', 1)]) {
        final d = deal(turtle, seed);
        final r = replay(turtle, seed, kGeneratorVersion, encodeMoveLog(solutionLog(d)));
        expect(r.legal, isTrue, reason: '$r');
        expect(r.cleared, isTrue);
        expect(r.finalTimeMs, 144000);
        expect(r.stars, 3);
      }
    });

    test('accepts a real game log with hints, undo and shuffles and matches its state', () {
      var s = GameState.newGame(turtle, 2026);
      var t = 0;
      s = hint(s).$1;
      for (final (a, b) in deal(turtle, 2026).solution.take(12)) {
        s = match(s, a, b, elapsedMs: t += 3000).$1;
      }
      s = undo(s).$1;
      s = shuffle(s, free: false, rewarded: true, elapsedMs: t += 1000).$1;
      s = undo(s).$1;
      s = shuffle(s, free: false, rewarded: false, elapsedMs: t += 1000).$1;
      s = hint(s, rewarded: true).$1;
      final rest = solve(turtle, s.faces, remaining: s.remaining) as SolveSolvable;
      for (final (a, b) in rest.solution) {
        s = match(s, a, b, elapsedMs: t += 3000).$1;
      }
      expect(s.isCleared, isTrue);
      final r = replay(turtle, 2026, kGeneratorVersion, encodeMoveLog(s.moveLog));
      expect(r.legal, isTrue, reason: '$r');
      expect(r.cleared, isTrue);
      expect(r.finalTimeMs, s.lastElapsedMs);
      expect(r.state!.hintsUsed, 2);
      expect(r.state!.rewardedShuffles, 1);
      expect(r.state!.faces, s.faces);
      expect(r.stars, clearStats(s).stars);
      expect(r.stars, 2, reason: 'a rewarded shuffle costs the 3rd star');
    });

    test('partial log: legal but not cleared', () {
      final d = deal(turtle, 5);
      final r = replay(turtle, 5, kGeneratorVersion, encodeMoveLog(solutionLog(d).take(10).toList()));
      expect(r.legal, isTrue);
      expect(r.cleared, isFalse);
      expect(r.finalTimeMs, isNull);
      expect(r.stars, isNull);
    });

    test('rejects an illegal match (blocked tile)', () {
      final s = GameState.newGame(turtle, 8, verify: false);
      final blocked = [
        for (var i = 0; i < 144; i++)
          if (!s.isFree(i)) i,
      ];
      final a = blocked.first;
      final b = [
        for (var i = 0; i < 144; i++)
          if (i != a && facesMatch(s.faces[i], s.faces[a])) i,
      ].first;
      final r = replay(turtle, 8, kGeneratorVersion, encodeMoveLog([LogMatch(a, b, 1000)]));
      expect(r.legal, isFalse);
      expect(r.errorIndex, 0);
    });

    test('rejects a non-matching pair and out-of-range positions', () {
      final s = GameState.newGame(turtle, 8, verify: false);
      final free = s.freeTiles;
      final pair = [
        for (final a in free)
          for (final b in free)
            if (a < b && !facesMatch(s.faces[a], s.faces[b])) (a, b),
      ].first;
      expect(replay(turtle, 8, 1, encodeMoveLog([LogMatch(pair.$1, pair.$2, 1)])).legal, isFalse);
      expect(replay(turtle, 8, 1, encodeMoveLog(const [LogMatch(200, 201, 1)])).legal, isFalse);
    });

    test('rejects a forged shuffle sub-seed and a deadlock shuffle without deadlock', () {
      final good = shuffleSeed(8, 0);
      expect(replay(turtle, 8, 1, encodeMoveLog([LogShuffle(ShuffleKind.credit, good, 10)])).legal, isTrue);
      final forged = replay(turtle, 8, 1, encodeMoveLog([LogShuffle(ShuffleKind.credit, good ^ 1, 10)]));
      expect(forged.legal, isFalse);
      expect(forged.error, contains('sub-seed'));
      final fake = replay(turtle, 8, 1, encodeMoveLog([LogShuffle(ShuffleKind.deadlock, good, 10)]));
      expect(fake.legal, isFalse);
      expect(fake.error, contains('deadlock'));
    });

    test('rejects undo with empty history, entries after the clear, other generator versions, garbage', () {
      expect(replay(turtle, 8, 1, encodeMoveLog(const [LogUndo()])).legal, isFalse);
      final d = deal(turtle, 9);
      final after = replay(turtle, 9, 1, encodeMoveLog([...solutionLog(d), const LogHint(HintKind.credit)]));
      expect(after.legal, isFalse);
      expect(after.errorIndex, 72);
      expect(replay(turtle, 9, 2, encodeMoveLog(solutionLog(d))).legal, isFalse);
      expect(replay(turtle, 9, 1, 'not a log').legal, isFalse);
    });

    test('rejects a hint on a deadlocked board; accepts the deadlock shuffle there', () {
      // Random play on the turtle runs into deadlocks quickly.
      for (var seed = 0; seed < 50; seed++) {
        final rng = Xoshiro128(seed);
        var s = GameState.newGame(turtle, seed, verify: false);
        while (!s.isCleared && !s.isDeadlocked) {
          final moves = s.availableMoves;
          final (a, b) = moves[rng.nextInt(moves.length)];
          s = match(s, a, b, elapsedMs: s.lastElapsedMs + 1000).$1;
        }
        if (!s.isDeadlocked) continue;
        final r = replay(turtle, seed, 1, encodeMoveLog([...s.moveLog, const LogHint(HintKind.credit)]));
        expect(r.legal, isFalse);
        expect(r.error, contains('deadlock'));
        final ok = replay(
          turtle,
          seed,
          1,
          encodeMoveLog([...s.moveLog, LogShuffle(ShuffleKind.deadlock, shuffleSeed(seed, 0), s.lastElapsedMs)]),
        );
        expect(ok.legal, isTrue, reason: '$ok');
        return;
      }
      fail('no deadlock reached');
    });
  });

  group('fixtures/deals/move_logs.json', () {
    test('replays to the recorded result', () {
      final json =
          jsonDecode(File('$repoRoot/fixtures/deals/move_logs.json').readAsStringSync()) as Map<String, Object?>;
      for (final e in (json['logs'] as List<Object?>).cast<Map<String, Object?>>()) {
        final r = replay(
          loadLayout(e['layoutId'] as String),
          e['seed'] as int,
          e['generatorVersion'] as int,
          e['log'] as String,
        );
        expect(r.legal, e['legal']);
        expect(r.cleared, e['cleared']);
        expect(r.finalTimeMs, e['finalTimeMs']);
        expect(r.stars, e['stars']);
        expect(hex(base64Url.decode(base64Url.normalize(e['log'] as String))), e['bytesHex']);
      }
      final ex = json['example'] as Map<String, Object?>;
      expect(ex['bytesHex'], '0100038c01dc0b0401efbeaddef40306');
    });
  });
}
