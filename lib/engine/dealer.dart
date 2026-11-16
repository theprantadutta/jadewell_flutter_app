/// Reverse-construction dealer (brief §5.4): simulated removal from the full
/// layout, so every deal is solvable by construction.
///
/// The exact procedure is specified in docs/ENGINE.md §Dealer; any change to
/// it (or to the PRNG, the pair list or the options below) changes boards and
/// requires a new [kGeneratorVersion].
library;

import 'dart:typed_data';

import 'layout.dart';
import 'prng.dart';
import 'tile_set.dart';
import 'tiles.dart';

/// Version of the deal algorithm. Stored with every deal and hashed into the
/// daily seed so daily boards never change across app updates.
const int kGeneratorVersion = 1;

/// Tunables of the dealer. Part of the deal definition: the same seed with
/// different options gives a different board.
final class DealerOptions {
  const DealerOptions({this.spreadCandidates = 1, this.maxDeadEnds = 32, this.maxAttempts = 64})
    : assert(spreadCandidates >= 1);

  /// No spread bias: the second tile of each pair is uniform. Used by tests
  /// unless a test is about the bias.
  static const DealerOptions unbiased = DealerOptions();

  /// What the app, the daily board and the server use for generator v1:
  /// a slight spread bias (best of 2 draws for the second tile).
  static const DealerOptions production = DealerOptions(spreadCandidates: 2);

  /// The second tile of a pair is the best of this many uniform draws (with
  /// replacement) by [spreadScore]. 1 = no bias.
  final int spreadCandidates;

  /// Dead ends tolerated per attempt before reseeding.
  final int maxDeadEnds;

  /// Attempts (seeds) tried before giving up.
  final int maxAttempts;

  @override
  bool operator ==(Object other) =>
      other is DealerOptions &&
      other.spreadCandidates == spreadCandidates &&
      other.maxDeadEnds == maxDeadEnds &&
      other.maxAttempts == maxAttempts;

  @override
  int get hashCode => Object.hash(spreadCandidates, maxDeadEnds, maxAttempts);

  @override
  String toString() =>
      'DealerOptions(spreadCandidates: $spreadCandidates, maxDeadEnds: $maxDeadEnds, maxAttempts: $maxAttempts)';
}

/// Thrown when no attempt produced a complete construction (the positions
/// admit no full removal order, e.g. two tiles stacked on each other).
final class DealException implements Exception {
  DealException(this.message);

  final String message;

  @override
  String toString() => 'DealException: $message';
}

/// A dealt board.
final class Deal {
  Deal._({
    required this.layoutId,
    required this.seed,
    required this.attempt,
    required this.faces,
    required this.solution,
    required this.options,
    required this.deadEnds,
  });

  final String layoutId;

  /// Seed asked for.
  final int seed;

  /// Attempt that succeeded (0 = [seed] itself, k ≥ 1 = `deriveSeed(seed, k)`).
  final int attempt;

  /// Face id per position index. For a sub-board deal, positions outside the
  /// sub-board hold −1.
  final Int8List faces;

  /// Construction order: removing these pairs front to back clears the
  /// (sub-)board. This is the solution the solver must independently confirm.
  final List<(int, int)> solution;

  final DealerOptions options;

  /// Dead ends met (and backtracked from) by the successful attempt.
  final int deadEnds;

  int get generatorVersion => kGeneratorVersion;
}

/// Spread score of a candidate pair: 0 when the footprints overlap
/// (`|dx| < 2 && |dy| < 2`, i.e. stacked), else `dx² + dy²` in half-units.
int spreadScore(Position a, Position b) {
  final dx = b.x - a.x, dy = b.y - a.y;
  if (dx.abs() < 2 && dy.abs() < 2) return 0;
  return dx * dx + dy * dy;
}

/// Seed for attempt [attempt] of a deal for [seed].
int attemptSeed(int seed, int attempt) => attempt == 0 ? seed & kMask32 : deriveSeed(seed, attempt);

/// Deals [layout] for [seed]. Throws [DealException] if the layout admits no
/// complete removal order.
Deal deal(Layout layout, int seed, {DealerOptions options = DealerOptions.production}) {
  final pairCount = layout.length ~/ 2;
  final result = _dealOn(layout, layout.all, seed, options, (rng) {
    final pairs = List.of(kCanonicalPairs);
    rng.shuffle(pairs);
    return pairs.sublist(0, pairCount);
  });
  if (result == null) {
    throw DealException('no complete construction for "${layout.id}" in ${options.maxAttempts} attempts');
  }
  return result;
}

/// Re-deals [faces] onto the positions in [remaining] (shuffle, brief §5.5)
/// with the same construction routine, seeded by [subSeed].
///
/// [faces] is the multiset of the remaining tiles' faces (any order; every
/// match key must occur an even number of times, [faces].length must equal
/// [remaining].length). Returns null when no attempt succeeds, which happens
/// when the remaining positions admit no complete removal order at all.
Deal? dealSubBoard(
  Layout layout,
  TileSet remaining,
  Iterable<int> faces,
  int subSeed, {
  DealerOptions options = DealerOptions.production,
}) {
  final pairs = facePairs(faces);
  if (pairs.length * 2 != remaining.length) {
    throw ArgumentError('${pairs.length * 2} faces for ${remaining.length} positions');
  }
  return _dealOn(layout, remaining, subSeed, options, (rng) {
    final shuffled = List.of(pairs);
    rng.shuffle(shuffled);
    return shuffled;
  });
}

Deal? _dealOn(
  Layout layout,
  TileSet positions,
  int seed,
  DealerOptions options,
  List<(int, int)> Function(Xoshiro128 rng) shuffledPairs,
) {
  for (var attempt = 0; attempt < options.maxAttempts; attempt++) {
    final rng = Xoshiro128(attemptSeed(seed, attempt));
    final built = _construct(layout, positions, rng, options);
    if (built == null) continue;
    final (order, deadEnds) = built;
    final pairs = shuffledPairs(rng);
    final faces = Int8List(layout.length)..fillRange(0, layout.length, -1);
    for (var k = 0; k < order.length; k++) {
      final (a, b) = order[k];
      final (fa, fb) = pairs[k];
      faces[a] = fa;
      faces[b] = fb;
    }
    return Deal._(
      layoutId: layout.id,
      seed: seed & kMask32,
      attempt: attempt,
      faces: faces,
      solution: List.unmodifiable(order),
      options: options,
      deadEnds: deadEnds,
    );
  }
  return null;
}

/// Simulated removal with bounded backtracking. Returns the removal order
/// and the number of dead ends met, or null after more than `maxDeadEnds`.
(List<(int, int)>, int)? _construct(Layout layout, TileSet start, Xoshiro128 rng, DealerOptions options) {
  var remaining = start;
  final steps = <(int, int)>[];
  var deadEnds = 0;
  while (remaining.isNotEmpty) {
    final free = layout.freeTiles(remaining);
    if (free.length < 2) {
      deadEnds++;
      if (deadEnds > options.maxDeadEnds || steps.isEmpty) return null;
      // Escalating backtrack: the k-th dead end undoes the last k pairs.
      final undo = deadEnds < steps.length ? deadEnds : steps.length;
      for (var u = 0; u < undo; u++) {
        final (a, b) = steps.removeLast();
        remaining = remaining.addAll([a, b]);
      }
      continue;
    }
    final i = rng.nextInt(free.length);
    final a = free[i];
    final rest = List.of(free)..removeAt(i);
    final draws = options.spreadCandidates < rest.length ? options.spreadCandidates : rest.length;
    var b = -1, bestScore = -1;
    final pa = layout.positions[a];
    for (var d = 0; d < draws; d++) {
      final cand = rest[rng.nextInt(rest.length)];
      final s = spreadScore(pa, layout.positions[cand]);
      if (s > bestScore) {
        bestScore = s;
        b = cand;
      }
    }
    steps.add((a, b));
    remaining = remaining.removeAll([a, b]);
  }
  return (steps, deadEnds);
}

/// Checks that [solution] clears the tiles of [faces] (≥ 0 entries) from the
/// board legally: each pair is distinct, both present, both free, and their
/// faces match. A cheap full proof of solvability.
bool isValidSolution(Layout layout, List<int> faces, List<(int, int)> solution) {
  var remaining = TileSet.of(layout.length, [
    for (var i = 0; i < layout.length; i++)
      if (faces[i] >= 0) i,
  ]);
  for (final (a, b) in solution) {
    if (a == b || !remaining.contains(a) || !remaining.contains(b)) return false;
    if (!layout.isFree(a, remaining) || !layout.isFree(b, remaining)) return false;
    if (!facesMatch(faces[a], faces[b])) return false;
    remaining = remaining.removeAll([a, b]);
  }
  return remaining.isEmpty;
}
