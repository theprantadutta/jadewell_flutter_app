import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:test/test.dart';

import 'helpers.dart';

/// Plain exhaustive oracle for small boards: DFS over every matching free
/// pair with a memo of visited sets, no pruning or ordering tricks.
bool bruteForceSolvable(Layout layout, List<int> faces) {
  final seen = <int>{};
  bool go(int remaining) {
    if (remaining == 0) return true;
    if (!seen.add(remaining)) return false;
    final set = TileSet.of(layout.length, [
      for (var i = 0; i < layout.length; i++)
        if (remaining & (1 << i) != 0) i,
    ]);
    final free = layout.freeTiles(set);
    for (var x = 0; x < free.length; x++) {
      for (var y = x + 1; y < free.length; y++) {
        if (facesMatch(faces[free[x]], faces[free[y]]) && go(remaining & ~(1 << free[x]) & ~(1 << free[y]))) {
          return true;
        }
      }
    }
    return false;
  }

  return go((1 << layout.length) - 1);
}

/// Random face multiset for [pairs] pairs using up to [keys] match keys,
/// at most 4 tiles per key; key 0 is the flowers (distinct flower faces).
List<int> randomFaces(Xoshiro128 rng, int pairs, int keys) {
  final pool = <int>[
    for (var k = 0; k < keys; k++) ...[k, k],
  ];
  rng.shuffle(pool);
  final faces = <int>[];
  var flowerPairs = 0;
  for (final k in pool.take(pairs)) {
    if (k == 0) {
      faces.addAll([34 + 2 * flowerPairs, 35 + 2 * flowerPairs]);
      flowerPairs++;
    } else {
      faces.addAll([k, k]);
    }
  }
  rng.shuffle(faces);
  return faces;
}

void main() {
  group('known unsolvable fixtures', () {
    test('identical pair stacked on each other', () {
      final l = tinyLayout([(0, 0, 0), (0, 0, 1)]);
      expect(solve(l, [5, 5]), isA<SolveUnsolvable>());
    });

    test('interleaved row A B A B', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (4, 0, 0), (6, 0, 0)]);
      expect(solve(l, [1, 2, 1, 2]), isA<SolveUnsolvable>());
    });

    test('crossed stacks', () {
      final l = tinyLayout([(0, 0, 0), (0, 0, 1), (4, 0, 0), (4, 0, 1), (8, 0, 0), (12, 0, 0)]);
      // Stack 1: bottom A, top B. Stack 2: bottom B, top A. Two loose Cs.
      final faces = List.filled(6, 0);
      faces[idx(l, 0, 0, 0)] = 1;
      faces[idx(l, 0, 0, 1)] = 2;
      faces[idx(l, 4, 0, 0)] = 2;
      faces[idx(l, 4, 0, 1)] = 1;
      faces[idx(l, 8, 0, 0)] = 3;
      faces[idx(l, 12, 0, 0)] = 3;
      expect(solve(l, faces), isA<SolveUnsolvable>());
    });

    test('a key whose four tiles are the turtle cap and three tiles under it', () {
      final turtle = loadLayout('turtle');
      final d = deal(turtle, 7, options: DealerOptions.unbiased);
      final faces = d.faces.toList();
      // Put the four copies of one face on the cap and three of the z3 tiles, swapping
      // the faces that were there into the old places of that face.
      final target = faces[143];
      final spots = [143, idx(turtle, 6, 12, 3), idx(turtle, 8, 12, 3), idx(turtle, 6, 14, 3)];
      final copies = [
        for (var i = 0; i < 144; i++)
          if (faces[i] == target) i,
      ];
      final others = [
        for (final s in spots)
          if (faces[s] != target) s,
      ];
      final freeCopies = [
        for (final c in copies)
          if (!spots.contains(c)) c,
      ];
      for (var k = 0; k < others.length; k++) {
        final tmp = faces[others[k]];
        faces[others[k]] = target;
        faces[freeCopies[k]] = tmp;
      }
      expect([for (final s in spots) faces[s]], everyElement(target));
      expect(solve(turtle, faces), isA<SolveUnsolvable>());
    });

    test('odd count of a key', () {
      final l = tinyLayout([(0, 0, 0), (4, 0, 0)]);
      expect(solve(l, [1, 2]), isA<SolveUnsolvable>());
    });

    test('hand-built boards that need real search to refute (cross-checked by brute force)', () {
      // Two rows of four under a bridge of two; found by searching random face
      // assignments for unsolvable boards where the first moves look fine.
      final l = tinyLayout([
        (0, 0, 0), (2, 0, 0), (4, 0, 0), (6, 0, 0), //
        (0, 2, 0), (2, 2, 0), (4, 2, 0), (6, 2, 0), //
        (1, 1, 1), (3, 1, 1), (5, 1, 1), (3, 1, 2),
      ]);
      var found = 0;
      final rng = Xoshiro128(2024);
      for (var trial = 0; trial < 3000 && found < 25; trial++) {
        final faces = randomFaces(rng, 6, 3);
        final r = solve(l, faces);
        final truth = bruteForceSolvable(l, faces);
        expect(r is SolveSolvable, truth, reason: 'faces $faces');
        expect(r, isNot(isA<SolveUnknown>()));
        if (r is SolveUnsolvable && r.nodes > 1) found++;
      }
      expect(found, greaterThan(0));
    });
  });

  group('solver agrees with a brute-force oracle on random small boards', () {
    final shapes = <String, List<(int, int, int)>>{
      'pyramid': [
        for (var y = 0; y < 3; y++)
          for (var x = 0; x < 4; x++) (2 * x, 2 * y, 0),
        (1, 1, 1),
        (3, 1, 1),
        (5, 1, 1),
        (1, 3, 1),
        (3, 3, 1),
        (5, 3, 1),
        (3, 2, 2),
        (11, 0, 0),
      ],
      'rows': [
        for (var x = 0; x < 6; x++) (2 * x, 0, 0),
        for (var x = 0; x < 6; x++) (2 * x + 1, 2, 0),
        (4, 0, 1),
        (6, 0, 1),
        (5, 2, 1),
        (7, 2, 1),
      ],
      'stacks': [
        for (var s = 0; s < 4; s++) ...[(4 * s, 0, 0), (4 * s, 0, 1), (4 * s, 0, 2)],
        (0, 4, 0),
        (2, 4, 0),
        (4, 4, 0),
        (6, 4, 0),
      ],
    };
    shapes.forEach((name, tiles) {
      test(name, () {
        final l = tinyLayout(tiles);
        final rng = Xoshiro128(name.length * 977);
        var solvable = 0, unsolvable = 0;
        for (var trial = 0; trial < 400; trial++) {
          final pairs = l.length ~/ 2;
          final minKeys = (pairs + 1) ~/ 2;
          final faces = randomFaces(rng, pairs, minKeys + rng.nextInt(3));
          final truth = bruteForceSolvable(l, faces);
          final r = solve(l, faces);
          expect(r, isNot(isA<SolveUnknown>()));
          expect(r is SolveSolvable, truth, reason: '$name faces $faces');
          if (r is SolveSolvable) {
            expect(isValidSolution(l, faces, r.solution), isTrue);
            solvable++;
          } else {
            unsolvable++;
          }
        }
        expect(solvable, greaterThan(20));
        expect(unsolvable, greaterThan(20));
      });
    });
  });

  group('budget', () {
    test('exceeding the budget yields unknown, never a verdict', () {
      final turtle = loadLayout('turtle');
      final d = deal(turtle, 3, options: DealerOptions.unbiased);
      final r = solve(turtle, d.faces, budget: 5);
      expect(r, isA<SolveUnknown>());
      expect((r as SolveUnknown).budgetExceeded, isTrue);
      expect(r.nodes, lessThanOrEqualTo(5));
    });

    test('a solvable verdict comes with a valid solution', () {
      final turtle = loadLayout('turtle');
      final d = deal(turtle, 11, options: DealerOptions.unbiased);
      final r = solve(turtle, d.faces);
      expect(r, isA<SolveSolvable>());
      expect(isValidSolution(turtle, d.faces, (r as SolveSolvable).solution), isTrue);
    });

    test('solves a partial board given as a remaining set', () {
      final turtle = loadLayout('turtle');
      final d = deal(turtle, 12, options: DealerOptions.unbiased);
      var rem = turtle.all;
      for (final (a, b) in d.solution.take(30)) {
        rem = rem.removeAll([a, b]);
      }
      final r = solve(turtle, d.faces, remaining: rem);
      expect(r, isA<SolveSolvable>());
      expect((r as SolveSolvable).solution, hasLength(42));
    });

    test('empty board is trivially solvable', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0)]);
      expect(solve(l, [1, 1], remaining: TileSet.empty(2)), isA<SolveSolvable>());
    });
  });
}
