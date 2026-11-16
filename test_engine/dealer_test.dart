import 'dart:convert';
import 'dart:io';

import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

Map<int, int> keyCounts(Iterable<int> faces) {
  final m = <int, int>{};
  for (final f in faces) {
    m[matchKeyOf(f)] = (m[matchKeyOf(f)] ?? 0) + 1;
  }
  return m;
}

void main() {
  final turtle = loadLayout('turtle');

  group('deal', () {
    test('deterministic for a seed, different across seeds', () {
      final a = deal(turtle, 42, options: DealerOptions.unbiased);
      final b = deal(turtle, 42, options: DealerOptions.unbiased);
      expect(a.faces, b.faces);
      expect(a.solution, b.solution);
      final c = deal(turtle, 43, options: DealerOptions.unbiased);
      expect(c.faces, isNot(a.faces));
    });

    test('options are part of the deal', () {
      final a = deal(turtle, 42, options: DealerOptions.unbiased);
      final b = deal(turtle, 42, options: DealerOptions.production);
      expect(a.faces, isNot(b.faces));
      expect(DealerOptions.production.spreadCandidates, 2);
      expect(DealerOptions.production, const DealerOptions(spreadCandidates: 2));
    });

    test('full layout gets the full 144 multiset; every solution pair matches and is valid', () {
      for (var seed = 0; seed < 50; seed++) {
        final d = deal(turtle, seed, options: DealerOptions.unbiased);
        expect(d.faces.toList()..sort(), fullTileSet());
        expect(d.solution, hasLength(72));
        final covered = <int>{
          for (final (a, b) in d.solution) ...[a, b],
        };
        expect(covered, hasLength(144));
        for (final (a, b) in d.solution) {
          expect(facesMatch(d.faces[a], d.faces[b]), isTrue);
        }
        expect(isValidSolution(turtle, d.faces, d.solution), isTrue);
        expect(d.generatorVersion, kGeneratorVersion);
        expect(d.layoutId, 'turtle');
      }
    });

    test('smaller layouts get n/2 pairs drawn from the 72, keys paired', () {
      final l = tinyLayout([for (var x = 0; x < 10; x++) (2 * x, 0, 0)]);
      for (var seed = 0; seed < 30; seed++) {
        final d = deal(l, seed, options: DealerOptions.unbiased);
        expect(d.faces, hasLength(10));
        expect(keyCounts(d.faces).values.every((c) => c.isEven), isTrue);
        // A sub-multiset of the full set.
        final full = fullTileSet();
        for (final f in d.faces) {
          expect(full.remove(f), isTrue);
        }
        expect(isValidSolution(l, d.faces, d.solution), isTrue);
      }
    });

    test('dead-end-prone layout still deals (backtracking / reseed) and terminates', () {
      // A stack of three plus three loose tiles: each stack tile must pair with a
      // loose tile, so pairing two loose tiles early dead-ends.
      final l = tinyLayout([(0, 0, 0), (0, 0, 1), (0, 0, 2), (4, 0, 0), (8, 0, 0), (12, 0, 0)]);
      var backtracked = 0;
      for (var seed = 0; seed < 300; seed++) {
        final d = deal(l, seed, options: DealerOptions.unbiased);
        expect(isValidSolution(l, d.faces, d.solution), isTrue);
        if (d.deadEnds > 0) backtracked++;
      }
      expect(backtracked, greaterThan(50));
    });

    test('impossible layouts terminate with DealException', () {
      final sw = Stopwatch()..start();
      // Two tiles stacked: never two free tiles.
      expect(() => deal(tinyLayout([(0, 0, 0), (0, 0, 1)]), 1), throwsA(isA<DealException>()));
      // A stack of three and one loose tile: the last two are always stacked.
      expect(() => deal(tinyLayout([(0, 0, 0), (0, 0, 1), (0, 0, 2), (4, 0, 0)]), 1), throwsA(isA<DealException>()));
      expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('generation always terminates on every bundled layout (attempt counts)', () {
      for (final f in bundledLayoutFiles()) {
        final l = Layout.parse(f.readAsStringSync());
        var maxAttempt = 0;
        for (var seed = 0; seed < 200; seed++) {
          final d = deal(l, seed);
          if (d.attempt > maxAttempt) maxAttempt = d.attempt;
        }
        expect(maxAttempt, lessThan(DealerOptions.production.maxAttempts), reason: l.id);
      }
    });

    test('spread bias spreads pairs out (only when asked for)', () {
      double meanSpread(DealerOptions o) {
        var total = 0, count = 0;
        for (var seed = 0; seed < 200; seed++) {
          final d = deal(turtle, seed, options: o);
          for (final (a, b) in d.solution) {
            total += spreadScore(turtle.positions[a], turtle.positions[b]);
            count++;
          }
        }
        return total / count;
      }

      final unbiased = meanSpread(DealerOptions.unbiased);
      final production = meanSpread(DealerOptions.production);
      final strong = meanSpread(const DealerOptions(spreadCandidates: 4));
      expect(production, greaterThan(unbiased * 1.1));
      expect(strong, greaterThan(production));
    });

    test('spreadScore', () {
      expect(spreadScore(const Position(0, 0, 0), const Position(1, 1, 1)), 0);
      expect(spreadScore(const Position(0, 0, 0), const Position(2, 0, 0)), 4);
      expect(spreadScore(const Position(0, 0, 0), const Position(3, 4, 2)), 25);
    });
  });

  group('dealSubBoard (shuffle)', () {
    test('keeps the face multiset, touches only the sub-board, is solvable', () {
      for (var seed = 0; seed < 40; seed++) {
        final d = deal(turtle, seed, options: DealerOptions.unbiased);
        var rem = turtle.all;
        for (final (a, b) in d.solution.take(seed % 60)) {
          rem = rem.removeAll([a, b]);
        }
        final faces = [for (final p in rem.toList()) d.faces[p]];
        final sub = dealSubBoard(turtle, rem, faces, deriveSeed(seed, 99), options: DealerOptions.unbiased)!;
        final newFaces = [for (final p in rem.toList()) sub.faces[p]];
        expect(newFaces..sort(), faces..sort());
        for (var i = 0; i < turtle.length; i++) {
          if (!rem.contains(i)) expect(sub.faces[i], -1);
        }
        expect(isValidSolution(turtle, sub.faces, sub.solution), isTrue);
        expect(solve(turtle, sub.faces, remaining: rem), isA<SolveSolvable>());
      }
    });

    test('flowers and seasons re-pair freely', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (4, 0, 0), (6, 0, 0)]);
      final sub = dealSubBoard(l, l.all, [34, 37, 39, 40], 5, options: DealerOptions.unbiased)!;
      expect(isValidSolution(l, sub.faces, sub.solution), isTrue);
    });

    test('returns null when the positions admit no removal order', () {
      final l = tinyLayout([(0, 0, 0), (0, 0, 1), (4, 0, 0), (8, 0, 0)]);
      final stacked = TileSet.of(4, [idx(l, 0, 0, 0), idx(l, 0, 0, 1)]);
      expect(dealSubBoard(l, stacked, [3, 3], 1), isNull);
    });

    test('rejects face multisets that do not fit', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (4, 0, 0), (6, 0, 0)]);
      expect(() => dealSubBoard(l, l.all, [1, 1], 1), throwsArgumentError);
      expect(() => dealSubBoard(l, l.all, [1, 1, 2, 3], 1), throwsArgumentError);
    });
  });

  group('cross-language fixtures', () {
    final json = jsonDecode(File('$repoRoot/fixtures/deals/turtle.json').readAsStringSync()) as Map<String, Object?>;

    test('positions are the canonical order', () {
      final positions = (json['positions'] as List<Object?>).cast<Map<String, Object?>>();
      expect([for (final p in positions) Position(p['x'] as int, p['y'] as int, p['z'] as int)], turtle.positions);
    });

    for (final key in ['deals', 'unbiasedDeals']) {
      test('$key match the engine', () {
        final deals = (json[key] as List<Object?>).cast<Map<String, Object?>>();
        expect(deals, isNotEmpty);
        for (final e in deals) {
          expect(e['generatorVersion'], kGeneratorVersion);
          expect(e['layoutVersion'], turtle.version);
          final d = deal(
            turtle,
            e['seed'] as int,
            options: DealerOptions(spreadCandidates: e['spreadCandidates'] as int),
          );
          expect(d.faces.toList(), e['faces'], reason: 'seed ${e['seed']}');
          expect(
            [
              for (final (a, b) in d.solution) [a, b],
            ],
            e['solution'],
            reason: 'seed ${e['seed']}',
          );
          expect(d.attempt, e['attempt']);
        }
      });
    }

    test('shuffles match the engine', () {
      for (final e in (json['shuffles'] as List<Object?>).cast<Map<String, Object?>>()) {
        final removed = TileSet.of(turtle.length, (e['removed'] as List<Object?>).cast<int>());
        final rem = turtle.all.removeAll(removed.toList());
        final before = (e['facesBefore'] as List<Object?>).cast<int>();
        final sub = dealSubBoard(turtle, rem, [for (final p in rem.toList()) before[p]], e['subSeed'] as int)!;
        final after = List.of(before);
        for (final p in rem.toList()) {
          after[p] = sub.faces[p];
        }
        expect(after, e['facesAfter']);
        expect(shuffleSeed(e['seed'] as int, 0), e['subSeed']);
      }
    });
  });
}
