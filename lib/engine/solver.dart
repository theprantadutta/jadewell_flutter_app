/// Independent forward solver (brief §5.4). It sees only positions and faces,
/// never the dealer's construction order.
///
/// Depth-first search over matching free pairs with:
///  * memoisation of failed remaining-sets (exact, 32-bit-word bitsets);
///  * safe moves: when every remaining tile of a match key is free, removing
///    them all is never wrong (removal only frees tiles, and those tiles can
///    only pair among themselves), so they are removed without branching;
///  * symmetry: a key with 3 free of 4 remaining branches over its 3 distinct
///    pairings only; 2 free gives a single pair;
///  * dead-key pruning: if every other remaining tile of a key lies
///    transitively above or below tile t (via "covered by"), t can never be
///    free together with a partner;
///  * relaxed-clearance pruning (see [_Search._relaxedClearable]);
///  * Luby restarts with randomised move ordering against heavy tails;
///  * move ordering: pairs whose tiles cover / side-block the most remaining
///    tiles first;
///  * a node budget: exceeding it yields [SolveUnknown], never a guess.
library;

import 'dart:typed_data';

import 'layout.dart';
import 'prng.dart';
import 'tile_set.dart';
import 'tiles.dart';

/// Budget for verifying a fresh deal or shuffle.
const int kVerifyBudget = 200000;

/// Budget for choosing a hint.
const int kHintBudget = 20000;

/// Node limit of the first restart; later runs scale it by the Luby sequence.
const int kRestartBase = 256;

/// Move scores are multiplied by [kJitter] and, in restarts, a uniform
/// 0…[kJitterRange]−1 is added, so moves within a few score points of each
/// other can swap places.
const int kJitter = 1;
const int kJitterRange = 12;
const int kJitterGrowth = 2;

/// Outcome of [solve].
sealed class SolveResult {
  const SolveResult(this.nodes);

  /// Search nodes expanded.
  final int nodes;
}

/// A solution was found: removing [solution] front to back clears the board.
final class SolveSolvable extends SolveResult {
  const SolveSolvable(this.solution, super.nodes);

  final List<(int, int)> solution;

  @override
  String toString() => 'solvable(${solution.length} pairs, $nodes nodes)';
}

/// The search space was exhausted without a solution: provably unsolvable.
final class SolveUnsolvable extends SolveResult {
  const SolveUnsolvable(super.nodes);

  @override
  String toString() => 'unsolvable($nodes nodes)';
}

/// The node budget ran out before a verdict.
final class SolveUnknown extends SolveResult {
  const SolveUnknown(super.nodes);

  bool get budgetExceeded => true;

  @override
  String toString() => 'unknown(budget exceeded, $nodes nodes)';
}

/// Solves the board made of the positions in [remaining] (default: every
/// position whose face is ≥ 0) with [faces] (face id per position index).
SolveResult solve(Layout layout, List<int> faces, {TileSet? remaining, int budget = kVerifyBudget}) {
  final rem =
      remaining ??
      TileSet.of(layout.length, [
        for (var i = 0; i < layout.length; i++)
          if (faces[i] >= 0) i,
      ]);
  return _Search(layout, faces, rem, budget).run();
}

final Expando<List<Uint32List>> _aboveCache = Expando('above');

/// For each position, the set of positions transitively above it through
/// "covered by" links (cached per layout).
List<Uint32List> _aboveClosure(Layout layout) {
  final cached = _aboveCache[layout];
  if (cached != null) return cached;
  final n = layout.length;
  final w = TileSet.wordsFor(n);
  final out = List.generate(n, (_) => Uint32List(w));
  // Canonical order sorts by z, so process top layer first.
  for (var i = n - 1; i >= 0; i--) {
    final set = out[i];
    for (final c in layout.coveredBy(i)) {
      set[c >> 5] |= 1 << (c & 31);
      final sub = out[c];
      for (var k = 0; k < w; k++) {
        set[k] |= sub[k];
      }
    }
  }
  _aboveCache[layout] = out;
  return out;
}

final class _Search {
  _Search(this.layout, List<int> faces, TileSet remaining, this.budget)
    : n = layout.length,
      w = TileSet.wordsFor(layout.length),
      rem = remaining.words,
      keys = Int32List(layout.length),
      coverStart = layout.tables.coverStart,
      cover = layout.tables.cover,
      leftStart = layout.tables.leftStart,
      left = layout.tables.left,
      rightStart = layout.tables.rightStart,
      right = layout.tables.right,
      underStart = layout.tables.underStart,
      under = layout.tables.under,
      scratch = Uint32List(TileSet.wordsFor(layout.length)),
      work = Int32List(layout.length * 10 + 8),
      above = _aboveClosure(layout),
      memo = _Memo(TileSet.wordsFor(layout.length)) {
    for (var i = 0; i < n; i++) {
      keys[i] = faces[i] >= 0 ? matchKeyOf(faces[i]) : -1;
    }
    remCount = 0;
    for (var i = 0; i < n; i++) {
      if (_has(i)) {
        if (keys[i] < 0) throw ArgumentError('position $i is remaining but has no face');
        remCount++;
      }
    }
  }

  final Layout layout;
  final int budget;
  final int n, w;
  final Uint32List rem;
  final Int32List keys;
  final Int32List coverStart, cover, leftStart, left, rightStart, right, underStart, under;
  final Uint32List scratch;
  final Int32List work;
  final List<Uint32List> above;
  final _Memo memo;
  final List<int> path = [];
  late int remCount;
  int nodes = 0;
  int runNodes = 0;
  int runLimit = 0;
  bool aborted = false;
  Xoshiro128? jitter;
  int jitterRange = kJitterRange;

  SolveResult run() {
    // Faces of each key must pair up, or nothing can clear the board.
    final counts = Int32List(kMatchKeyCount);
    for (var i = 0; i < n; i++) {
      if (_has(i)) counts[keys[i]]++;
    }
    for (final c in counts) {
      if (c > 4) throw ArgumentError('more than 4 tiles share a match key');
    }
    for (final c in counts) {
      if (c.isOdd) return const SolveUnsolvable(0);
    }
    // Restarts: run r uses a Luby-scaled node limit and, from run 1 on,
    // randomly perturbed move ordering. A run that finishes without hitting
    // its limit has explored everything, so its verdict is final. Failed
    // states proven in earlier runs stay in the memo.
    for (var r = 0; ; r++) {
      final left = budget - nodes;
      if (left <= 0) return SolveUnknown(nodes);
      final limit = kRestartBase * _luby(r + 1);
      runLimit = limit < left ? limit : left;
      runNodes = 0;
      aborted = false;
      jitter = r == 0 ? null : Xoshiro128(r);
      jitterRange = kJitterRange + kJitterGrowth * r;
      if (_dfs()) {
        return SolveSolvable(
          List.unmodifiable([for (var k = 0; k < path.length; k += 2) (path[k], path[k + 1])]),
          nodes,
        );
      }
      if (!aborted) return SolveUnsolvable(nodes);
    }
  }

  static int _luby(int i) {
    // 1,1,2,1,1,2,4,1,1,2,1,1,2,4,8,…
    var k = 1;
    while ((1 << k) - 1 < i) {
      k++;
    }
    if ((1 << k) - 1 == i) return 1 << (k - 1);
    return _luby(i - (1 << (k - 1)) + 1);
  }

  bool _has(int i) => (rem[i >> 5] >> (i & 31)) & 1 != 0;

  void _clear(int i) => rem[i >> 5] &= ~(1 << (i & 31));

  void _set(int i) => rem[i >> 5] |= 1 << (i & 31);

  bool _free(int i) {
    for (var k = coverStart[i], e = coverStart[i + 1]; k < e; k++) {
      if (_has(cover[k])) return false;
    }
    var l = false;
    for (var k = leftStart[i], e = leftStart[i + 1]; k < e; k++) {
      if (_has(left[k])) {
        l = true;
        break;
      }
    }
    if (!l) return true;
    for (var k = rightStart[i], e = rightStart[i + 1]; k < e; k++) {
      if (_has(right[k])) return false;
    }
    return true;
  }

  bool _freeIn(Uint32List set, int i) {
    for (var k = coverStart[i], e = coverStart[i + 1]; k < e; k++) {
      final j = cover[k];
      if ((set[j >> 5] >> (j & 31)) & 1 != 0) return false;
    }
    var l = false;
    for (var k = leftStart[i], e = leftStart[i + 1]; k < e; k++) {
      final j = left[k];
      if ((set[j >> 5] >> (j & 31)) & 1 != 0) {
        l = true;
        break;
      }
    }
    if (!l) return true;
    for (var k = rightStart[i], e = rightStart[i + 1]; k < e; k++) {
      final j = right[k];
      if ((set[j >> 5] >> (j & 31)) & 1 != 0) return false;
    }
    return true;
  }

  /// Relaxed clearance test (sound dead-state pruning). Every tile may be
  /// removed on its own as soon as it is free, except tiles of keys with
  /// exactly two remaining, which may only leave together when both are
  /// free. Removal never blocks anything, so removing greedily reaches the
  /// largest clearable set; if even that leaves tiles, the real game (which
  /// is strictly more constrained) cannot clear the board either.
  bool _relaxedClearable(Int32List all, Int32List allCount) {
    for (var k = 0; k < w; k++) {
      scratch[k] = rem[k];
    }
    var leftCount = remCount;
    var top = 0;
    for (var i = 0; i < n; i++) {
      if (_has(i)) work[top++] = i;
    }
    while (top > 0) {
      final i = work[--top];
      if ((scratch[i >> 5] >> (i & 31)) & 1 == 0 || !_freeIn(scratch, i)) continue;
      final k = keys[i];
      var removedPartner = -1;
      if (allCount[k] == 2) {
        final p = all[k * 4] == i ? all[k * 4 + 1] : all[k * 4];
        if (!_freeIn(scratch, p)) continue;
        removedPartner = p;
      }
      for (var pass = 0; pass < 2; pass++) {
        final t = pass == 0 ? i : removedPartner;
        if (t < 0) break;
        scratch[t >> 5] &= ~(1 << (t & 31));
        leftCount--;
        for (var e = underStart[t]; e < underStart[t + 1]; e++) {
          work[top++] = under[e];
        }
        for (var e = leftStart[t]; e < leftStart[t + 1]; e++) {
          work[top++] = left[e];
        }
        for (var e = rightStart[t]; e < rightStart[t + 1]; e++) {
          work[top++] = right[e];
        }
      }
    }
    return leftCount == 0;
  }

  /// Remaining tiles that [i] covers or touches on a side: what removing it
  /// can help free.
  int _value(int i) {
    var v = 0;
    final under = layout.covers(i);
    for (final u in under) {
      if (_has(u)) v += 3;
    }
    for (var k = leftStart[i], e = leftStart[i + 1]; k < e; k++) {
      if (_has(left[k])) v++;
    }
    for (var k = rightStart[i], e = rightStart[i + 1]; k < e; k++) {
      if (_has(right[k])) v++;
    }
    return v;
  }

  bool _dfs() {
    if (remCount == 0) return true;
    if (runNodes >= runLimit) {
      aborted = true;
      return false;
    }
    nodes++;
    runNodes++;
    if (memo.contains(rem)) return false;

    // Bucket remaining and free tiles by key (at most 4 tiles per key).
    final all = Int32List(kMatchKeyCount * 4);
    final allCount = Int32List(kMatchKeyCount);
    final free = Int32List(kMatchKeyCount * 4);
    final freeCount = Int32List(kMatchKeyCount);
    for (var i = 0; i < n; i++) {
      if (!_has(i)) continue;
      final k = keys[i];
      all[k * 4 + allCount[k]++] = i;
      if (_free(i)) free[k * 4 + freeCount[k]++] = i;
    }

    // Dead key: a tile none of whose partners can ever be free at the same
    // time as it, because each partner lies transitively above it or below
    // it (one of the two is always covered while the other remains).
    for (var k = 0; k < kMatchKeyCount; k++) {
      final r = allCount[k];
      if (r < 2) continue;
      for (var x = 0; x < r; x++) {
        final t = all[k * 4 + x];
        final aboveT = above[t];
        var compatible = false;
        for (var y = 0; y < r && !compatible; y++) {
          if (y == x) continue;
          final p = all[k * 4 + y];
          compatible = (aboveT[p >> 5] >> (p & 31)) & 1 == 0 && (above[p][t >> 5] >> (t & 31)) & 1 == 0;
        }
        if (!compatible) return _fail();
      }
    }

    if (!_relaxedClearable(all, allCount)) return _fail();

    // Safe move: all remaining tiles of a key are free.
    for (var k = 0; k < kMatchKeyCount; k++) {
      final c = freeCount[k];
      if (c >= 2 && c == allCount[k]) {
        for (var x = 0; x < c; x++) {
          _clear(free[k * 4 + x]);
          path.add(free[k * 4 + x]);
        }
        remCount -= c;
        if (_dfs()) return true;
        remCount += c;
        for (var x = 0; x < c; x++) {
          _set(free[k * 4 + x]);
        }
        path.length -= c;
        return _fail();
      }
    }

    // Branching moves.
    final moves = <int>[]; // packed: score << 16 | a << 8 | b
    for (var k = 0; k < kMatchKeyCount; k++) {
      final c = freeCount[k];
      if (c < 2) continue;
      for (var x = 0; x < c; x++) {
        for (var y = x + 1; y < c; y++) {
          final a = free[k * 4 + x], b = free[k * 4 + y];
          final j = jitter;
          final score = j == null
              ? (_value(a) + _value(b)) * kJitter
              : (_value(a) + _value(b)) * kJitter + j.nextInt(jitterRange);
          moves.add((score << 16) | (a << 8) | b);
        }
      }
    }
    if (moves.isEmpty) return _fail();
    // Highest score first; ties by ascending (a, b) for determinism.
    moves.sort((p, q) {
      final sp = p >> 16, sq = q >> 16;
      if (sp != sq) return sq - sp;
      return (p & 0xFFFF) - (q & 0xFFFF);
    });
    for (final m in moves) {
      final a = (m >> 8) & 0xFF, b = m & 0xFF;
      _clear(a);
      _clear(b);
      path
        ..add(a)
        ..add(b);
      remCount -= 2;
      if (_dfs()) return true;
      remCount += 2;
      _set(a);
      _set(b);
      path.length -= 2;
      if (aborted) return false;
    }
    return _fail();
  }

  bool _fail() {
    if (!aborted) memo.add(rem);
    return false;
  }
}

/// Open-addressing hash set of fixed-width word tuples.
final class _Memo {
  _Memo(this.w) {
    _alloc(1 << 10);
  }

  final int w;
  late Uint32List _keys;
  late Uint8List _used;
  int _mask = 0, _count = 0;

  void _alloc(int capacity) {
    _keys = Uint32List(capacity * w);
    _used = Uint8List(capacity);
    _mask = capacity - 1;
  }

  int _hash(Uint32List words) {
    var h = 0x2545F491;
    for (var i = 0; i < w; i++) {
      h = ((h ^ words[i]) * 0x01000193) & 0x3FFFFFFF;
      h ^= h >> 15;
    }
    return h;
  }

  int _find(Uint32List words) {
    var slot = _hash(words) & _mask;
    while (_used[slot] != 0) {
      var same = true;
      final base = slot * w;
      for (var i = 0; i < w; i++) {
        if (_keys[base + i] != words[i]) {
          same = false;
          break;
        }
      }
      if (same) return slot;
      slot = (slot + 1) & _mask;
    }
    return -1 - slot;
  }

  bool contains(Uint32List words) => _find(words) >= 0;

  void add(Uint32List words) {
    if ((_count + 1) * 2 > _mask + 1) _grow();
    final f = _find(words);
    if (f >= 0) return;
    final slot = -1 - f;
    _used[slot] = 1;
    final base = slot * w;
    for (var i = 0; i < w; i++) {
      _keys[base + i] = words[i];
    }
    _count++;
  }

  void _grow() {
    final oldKeys = _keys, oldUsed = _used;
    _alloc((_mask + 1) * 2);
    _count = 0;
    final tmp = Uint32List(w);
    for (var s = 0; s < oldUsed.length; s++) {
      if (oldUsed[s] == 0) continue;
      for (var i = 0; i < w; i++) {
        tmp[i] = oldKeys[s * w + i];
      }
      add(tmp);
    }
  }
}
