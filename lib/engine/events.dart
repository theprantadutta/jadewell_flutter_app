/// Events emitted by the commands for the UI. The UI animates them; the
/// engine never waits for an animation.
library;

import 'game_state.dart';

sealed class GameEvent {
  const GameEvent();
}

/// [tile] became the selection.
final class Selected extends GameEvent {
  const Selected(this.tile);

  final int tile;

  @override
  bool operator ==(Object other) => other is Selected && other.tile == tile;

  @override
  int get hashCode => tile.hashCode;

  @override
  String toString() => 'Selected($tile)';
}

/// [tile] is no longer selected (tapped again, or dropped by undo/shuffle).
final class Deselected extends GameEvent {
  const Deselected(this.tile);

  final int tile;

  @override
  bool operator ==(Object other) => other is Deselected && other.tile == tile;

  @override
  int get hashCode => tile.hashCode;

  @override
  String toString() => 'Deselected($tile)';
}

/// [a] and [b] were removed. [freed] lists the tiles that were blocked
/// before and are free now, ascending.
final class Matched extends GameEvent {
  const Matched(this.a, this.b, this.freed);

  final int a, b;
  final List<int> freed;

  @override
  String toString() => 'Matched($a, $b, freed: $freed)';
}

/// The selected tile [a] and the tapped free tile [b] do not match.
/// [b] becomes the selection; a [Selected] event for it follows.
final class Mismatch extends GameEvent {
  const Mismatch(this.a, this.b);

  final int a, b;

  @override
  bool operator ==(Object other) => other is Mismatch && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => 'Mismatch($a, $b)';
}

/// [tile] was tapped but is not free. [blockers] are the remaining tiles
/// covering it, plus both side neighbours when it is side-blocked.
/// The selection is unchanged.
final class Blocked extends GameEvent {
  const Blocked(this.tile, this.blockers);

  final int tile;
  final List<int> blockers;

  @override
  String toString() => 'Blocked($tile, blockers: $blockers)';
}

/// The remaining tiles' faces were re-dealt onto the remaining positions.
final class Shuffled extends GameEvent {
  const Shuffled(this.subSeed, this.kind, this.positions);

  final int subSeed;
  final ShuffleKind kind;

  /// The positions whose faces were re-dealt (all remaining), ascending.
  final List<int> positions;

  @override
  String toString() => 'Shuffled(${kind.name}, subSeed: $subSeed, ${positions.length} tiles)';
}

/// The last history entry was undone. For a match, [reblocked] lists tiles
/// that were free and are blocked again by the restored pair.
final class Undone extends GameEvent {
  const Undone(this.entry, this.reblocked);

  final HistoryEntry entry;
  final List<int> reblocked;

  @override
  String toString() => 'Undone($entry, reblocked: $reblocked)';
}

/// Suggested pair.
final class HintShown extends GameEvent {
  const HintShown(this.a, this.b);

  final int a, b;

  @override
  bool operator ==(Object other) => other is HintShown && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => 'HintShown($a, $b)';
}

/// Tiles remain and no matching free pair exists. The UI shows the
/// "No moves" sheet with the free shuffle.
final class Deadlock extends GameEvent {
  const Deadlock();

  @override
  bool operator ==(Object other) => other is Deadlock;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'Deadlock()';
}

/// The last pair was removed.
final class Cleared extends GameEvent {
  const Cleared(this.stats);

  final ClearStats stats;

  @override
  String toString() => 'Cleared($stats)';
}

/// Why a command did nothing.
enum RejectReason {
  /// Hint asked with no free hint left and not rewarded.
  noHintCredits,

  /// Shuffle asked with no free shuffle left and not rewarded.
  noShuffleCredits,

  /// The free deadlock shuffle was asked while moves exist.
  notDeadlocked,

  /// Undo with an empty history.
  nothingToUndo,

  /// The remaining positions admit no complete removal order, so no shuffle
  /// can make the board solvable (e.g. two tiles stacked on each other).
  shuffleImpossible,

  /// [match] with a pair that is not a legal move.
  illegalMove,

  /// The board is already cleared.
  gameOver,
}

/// The command was refused; the state is unchanged.
final class Rejected extends GameEvent {
  const Rejected(this.reason);

  final RejectReason reason;

  @override
  bool operator ==(Object other) => other is Rejected && other.reason == reason;

  @override
  int get hashCode => reason.hashCode;

  @override
  String toString() => 'Rejected(${reason.name})';
}
