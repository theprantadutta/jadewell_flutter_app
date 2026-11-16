/// Pure commands: each takes a [GameState] and returns the next state plus
/// the events the UI should animate. A command that does nothing returns the
/// very same state instance (`identical(next, state)`).
///
/// Selection model (design/motion/MOTION_SPEC.md §2): tap free A → selected;
/// tap A again → deselected; tap free matching B → match; tap free
/// non-matching B → mismatch and B becomes selected; tap blocked tile →
/// blocked feedback, selection unchanged.
library;

import 'dart:typed_data';

import 'dealer.dart';
import 'events.dart';
import 'game_state.dart';
import 'move_log.dart';
import 'prng.dart';
import 'scoring.dart';
import 'solver.dart';
import 'tiles.dart';

typedef CommandResult = (GameState, List<GameEvent>);

/// Domain-separation salt for shuffle sub-seeds ("SHUF").
const int kShuffleSalt = 0x53485546;

/// Sub-seed of the shuffle with 0-based index [shuffleIndex] in a game dealt
/// from [dealSeed]: `deriveSeed(dealSeed XOR 0x53485546, shuffleIndex + 1)`.
int shuffleSeed(int dealSeed, int shuffleIndex) => deriveSeed((dealSeed ^ kShuffleSalt) & kMask32, shuffleIndex + 1);

int _clampElapsed(GameState s, int elapsedMs) => elapsedMs > s.lastElapsedMs ? elapsedMs : s.lastElapsedMs;

/// A tap on [pos]. [elapsedMs] is the board clock (logged with matches).
/// Taps on removed or out-of-range positions, or after the clear, do nothing.
CommandResult select(GameState s, int pos, {int elapsedMs = 0}) {
  if (s.isCleared || pos < 0 || pos >= s.layout.length || s.removed.contains(pos)) return (s, const []);
  if (!s.isFree(pos)) return (s, [Blocked(pos, s.layout.blockersOf(pos, s.remaining))]);
  final sel = s.selected;
  if (sel == null) return (s.copyWith(selected: () => pos), [Selected(pos)]);
  if (sel == pos) return (s.copyWith(selected: () => null), [Deselected(pos)]);
  if (facesMatch(s.faces[sel], s.faces[pos])) return _applyMatch(s, sel, pos, elapsedMs);
  return (s.copyWith(selected: () => pos, currentStreak: 0), [Mismatch(sel, pos), Selected(pos)]);
}

/// Matches [a] and [b] directly (replay, tests, assisted play). Rejected
/// with [RejectReason.illegalMove] unless both are distinct remaining free
/// tiles with matching faces.
CommandResult match(GameState s, int a, int b, {int elapsedMs = 0}) {
  if (s.isCleared) return (s, const [Rejected(RejectReason.gameOver)]);
  final n = s.layout.length;
  final legal =
      a != b && a >= 0 && b >= 0 && a < n && b < n && s.isFree(a) && s.isFree(b) && facesMatch(s.faces[a], s.faces[b]);
  if (!legal) return (s, const [Rejected(RejectReason.illegalMove)]);
  return _applyMatch(s, a, b, elapsedMs);
}

CommandResult _applyMatch(GameState s, int a, int b, int elapsedMs) {
  final elapsed = _clampElapsed(s, elapsedMs);
  final before = s.freeTiles.toSet();
  final streak = s.currentStreak + 1;
  final next = s.copyWith(
    removed: s.removed.addAll([a, b]),
    selected: () => null,
    history: [...s.history, MatchEntry(a, b)],
    moveLog: [...s.moveLog, LogMatch(a, b, elapsed)],
    currentStreak: streak,
    longestStreak: streak > s.longestStreak ? streak : s.longestStreak,
    lastElapsedMs: elapsed,
  );
  final freed = [
    for (final t in next.freeTiles)
      if (!before.contains(t)) t,
  ];
  final events = <GameEvent>[Matched(a, b, freed)];
  if (next.isCleared) {
    events.add(Cleared(clearStats(next)));
  } else if (next.isDeadlocked) {
    events.add(const Deadlock());
  }
  return (next, events);
}

/// Stats of a (cleared) state, with stars when a par is known.
ClearStats clearStats(GameState s) => ClearStats(
  elapsedMs: s.lastElapsedMs,
  hintsUsed: s.hintsUsed,
  shufflesUsed: s.shufflesUsed,
  rewardedShuffles: s.rewardedShuffles,
  undos: s.undos,
  longestStreak: s.longestStreak,
  tilesMatched: s.tilesMatched,
  parMs: s.parMs,
  stars: s.parMs == null
      ? null
      : starsFor(
          timeMs: s.lastElapsedMs,
          parMs: s.parMs!,
          hintsUsed: s.hintsUsed,
          rewardedShuffles: s.rewardedShuffles,
        ),
);

/// Undoes the last match or shuffle. Unlimited and free; counters other
/// than [GameState.undos] are not refunded (a shuffle credit stays spent).
CommandResult undo(GameState s) {
  if (s.isCleared) return (s, const [Rejected(RejectReason.gameOver)]);
  if (s.history.isEmpty) return (s, const [Rejected(RejectReason.nothingToUndo)]);
  final entry = s.history.last;
  final events = <GameEvent>[if (s.selected != null) Deselected(s.selected!)];
  final GameState next;
  final List<int> reblocked;
  switch (entry) {
    case MatchEntry(:final a, :final b):
      next = s.copyWith(
        removed: s.removed.removeAll([a, b]),
        selected: () => null,
        history: s.history.sublist(0, s.history.length - 1),
        moveLog: [...s.moveLog, const LogUndo()],
        undos: s.undos + 1,
        currentStreak: 0,
      );
      final after = next.freeTiles.toSet();
      reblocked = [
        for (final t in s.freeTiles)
          if (!after.contains(t)) t,
      ];
    case ShuffleEntry(:final previousFaces):
      next = s.copyWith(
        faces: Int8List.fromList(previousFaces),
        selected: () => null,
        history: s.history.sublist(0, s.history.length - 1),
        moveLog: [...s.moveLog, const LogUndo()],
        undos: s.undos + 1,
        currentStreak: 0,
      );
      reblocked = const [];
  }
  events.add(Undone(entry, reblocked));
  if (next.isDeadlocked) events.add(const Deadlock());
  return (next, events);
}

/// Re-deals the remaining faces onto the remaining positions so the board
/// is solvable again (brief §5.5).
///
///  * `free: true`: the deadlock shuffle. Only while deadlocked, costs nothing.
///  * `rewarded: true`: paid by a rewarded ad whose reward callback fired.
///    Counts in [GameState.rewardedShuffles] (costs the 3rd star).
///  * neither: uses one of [GameState.freeShufflesLeft], else rejected with
///    [RejectReason.noShuffleCredits] (the UI then offers the rewarded ad).
CommandResult shuffle(
  GameState s, {
  required bool free,
  required bool rewarded,
  int elapsedMs = 0,
  int solverBudget = kVerifyBudget,
}) {
  if (free && rewarded) throw ArgumentError('a shuffle is either free or rewarded');
  if (s.isCleared) return (s, const [Rejected(RejectReason.gameOver)]);
  final ShuffleKind kind;
  if (free) {
    if (!s.isDeadlocked) return (s, const [Rejected(RejectReason.notDeadlocked)]);
    kind = ShuffleKind.deadlock;
  } else if (rewarded) {
    kind = ShuffleKind.rewarded;
  } else {
    if (s.freeShufflesLeft <= 0) return (s, const [Rejected(RejectReason.noShuffleCredits)]);
    kind = ShuffleKind.credit;
  }
  final result = applyShuffle(s, kind, elapsedMs: elapsedMs, verify: true, solverBudget: solverBudget);
  if (result == null) return (s, const [Rejected(RejectReason.shuffleImpossible)]);
  return result;
}

/// Performs a shuffle of [kind] without checking credits or deadlock (used
/// by [shuffle] after its checks, and by replay). Returns null when the
/// remaining positions admit no solvable arrangement.
///
/// The sub-deal is solvable by construction; with [verify] the forward
/// solver also confirms it, and a solver verdict of unsolvable without a
/// valid construction order (an engine bug) rejects the shuffle.
CommandResult? applyShuffle(
  GameState s,
  ShuffleKind kind, {
  required int elapsedMs,
  required bool verify,
  int solverBudget = kVerifyBudget,
}) {
  final subSeed = shuffleSeed(s.seed, s.shuffleCount);
  final positions = s.remaining;
  final sub = dealSubBoard(s.layout, positions, s.remainingFaces, subSeed, options: s.options);
  if (sub == null) return null;
  final faces = Int8List.fromList(s.faces);
  for (final p in positions.toList()) {
    faces[p] = sub.faces[p];
  }
  if (verify) {
    final r = solve(s.layout, faces, remaining: positions, budget: solverBudget);
    if (r is! SolveSolvable && !isValidSolution(s.layout, sub.faces, sub.solution)) return null;
  }
  final elapsed = _clampElapsed(s, elapsedMs);
  final next = s.copyWith(
    faces: faces,
    selected: () => null,
    history: [...s.history, ShuffleEntry(s.faces, subSeed, kind)],
    moveLog: [...s.moveLog, LogShuffle(kind, subSeed, elapsed)],
    shufflesUsed: s.shufflesUsed + 1,
    freeShufflesLeft: kind == ShuffleKind.credit && s.freeShufflesLeft > 0 ? s.freeShufflesLeft - 1 : null,
    rewardedShuffles: kind == ShuffleKind.rewarded ? s.rewardedShuffles + 1 : null,
    shuffleCount: s.shuffleCount + 1,
    lastElapsedMs: elapsed,
  );
  final events = <GameEvent>[
    if (s.selected != null) Deselected(s.selected!),
    Shuffled(subSeed, kind, positions.toList()),
  ];
  if (next.isDeadlocked) events.add(const Deadlock());
  return (next, events);
}

/// Shows a matching free pair, preferring one that keeps the board
/// solvable (the first move of a solver solution found within [budget]),
/// else the first available pair.
///
/// On deadlock returns `[Deadlock]` and consumes nothing: the UI offers the
/// shuffle, never an ad. With `rewarded: true` (reward callback fired) no
/// credit is used; otherwise one of [GameState.freeHintsLeft] is, or the
/// hint is rejected with [RejectReason.noHintCredits].
CommandResult hint(GameState s, {int budget = kHintBudget, bool rewarded = false}) {
  if (s.isCleared) return (s, const [Rejected(RejectReason.gameOver)]);
  final moves = s.availableMoves;
  if (moves.isEmpty) return (s, const [Deadlock()]);
  if (!rewarded && s.freeHintsLeft <= 0) return (s, const [Rejected(RejectReason.noHintCredits)]);
  final (a, b) = findHint(s, budget: budget)!;
  final next = s.copyWith(
    hintsUsed: s.hintsUsed + 1,
    freeHintsLeft: rewarded ? null : s.freeHintsLeft - 1,
    moveLog: [...s.moveLog, LogHint(rewarded ? HintKind.rewarded : HintKind.credit)],
  );
  return (next, [HintShown(a, b)]);
}

/// The pair [hint] would show, without consuming anything; null on
/// deadlock or when cleared.
(int, int)? findHint(GameState s, {int budget = kHintBudget}) {
  final moves = s.availableMoves;
  if (moves.isEmpty) return null;
  final r = solve(s.layout, s.faces, remaining: s.remaining, budget: budget);
  if (r is SolveSolvable && r.solution.isNotEmpty) {
    final (a, b) = r.solution.first;
    return a < b ? (a, b) : (b, a);
  }
  return moves.first;
}

/// Adds [count] free hints (e.g. a "head start" or "second chance" bonus).
CommandResult grantHint(GameState s, {int count = 1}) => (s.copyWith(freeHintsLeft: s.freeHintsLeft + count), const []);

/// Adds [count] free shuffles (e.g. a "second chance" bonus). Shuffles paid
/// from these credits do not cost stars.
CommandResult grantShuffle(GameState s, {int count = 1}) =>
    (s.copyWith(freeShufflesLeft: s.freeShufflesLeft + count), const []);

/// What tapping the hint button should do.
enum HintAvailability {
  /// No move exists: show the "No moves" sheet with the free shuffle.
  noMoves,

  /// A free hint is left.
  free,

  /// No free hint left: offer the rewarded ad (a pair exists, so the reward
  /// will resolve).
  needsReward,

  /// The board is cleared.
  none,
}

HintAvailability hintAvailability(GameState s) {
  if (s.isCleared) return HintAvailability.none;
  if (s.availableMoves.isEmpty) return HintAvailability.noMoves;
  return s.freeHintsLeft > 0 ? HintAvailability.free : HintAvailability.needsReward;
}

/// What tapping the shuffle button should do.
enum ShuffleAvailability {
  /// Deadlocked: the shuffle is free (`shuffle(free: true)`).
  deadlockFree,

  /// A free shuffle credit is left.
  free,

  /// Offer the rewarded ad, then `shuffle(rewarded: true)`.
  needsReward,

  /// The board is cleared.
  none,
}

ShuffleAvailability shuffleAvailability(GameState s) {
  if (s.isCleared) return ShuffleAvailability.none;
  if (s.isDeadlocked) return ShuffleAvailability.deadlockFree;
  return s.freeShufflesLeft > 0 ? ShuffleAvailability.free : ShuffleAvailability.needsReward;
}
