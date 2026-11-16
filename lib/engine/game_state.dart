/// Immutable game state. Commands in commands.dart turn one state into the
/// next plus a list of events.
library;

import 'dart:typed_data';

import 'dealer.dart';
import 'layout.dart';
import 'move_log.dart';
import 'solver.dart';
import 'tile_set.dart';
import 'tiles.dart';

/// Free hints per board.
const int kFreeHintsPerBoard = 3;

/// Free shuffles per board (the deadlock shuffle is extra and always free).
const int kFreeShufflesPerBoard = 2;

/// How a shuffle was paid for.
enum ShuffleKind {
  /// One of the board's free shuffles ([GameState.freeShufflesLeft]).
  credit,

  /// Paid with a rewarded ad: costs the 3rd star.
  rewarded,

  /// The free shuffle offered on deadlock: never costs anything.
  deadlock,
}

/// How a hint was paid for.
enum HintKind {
  /// One of the board's free hints ([GameState.freeHintsLeft]).
  credit,

  /// Paid with a rewarded ad.
  rewarded,
}

/// An undoable step.
sealed class HistoryEntry {
  const HistoryEntry();
}

/// Tiles [a] and [b] were matched.
final class MatchEntry extends HistoryEntry {
  const MatchEntry(this.a, this.b);

  final int a, b;

  @override
  bool operator ==(Object other) => other is MatchEntry && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(a, b);

  @override
  String toString() => 'MatchEntry($a, $b)';
}

/// The board was shuffled with [subSeed]; undo restores [previousFaces].
final class ShuffleEntry extends HistoryEntry {
  ShuffleEntry(Int8List previousFaces, this.subSeed, this.kind)
    : previousFaces = Int8List.fromList(previousFaces).asUnmodifiableView();

  final Int8List previousFaces;
  final int subSeed;
  final ShuffleKind kind;

  @override
  String toString() => 'ShuffleEntry(${kind.name}, subSeed: $subSeed)';
}

/// Numbers reported with [Cleared].
final class ClearStats {
  const ClearStats({
    required this.elapsedMs,
    required this.hintsUsed,
    required this.shufflesUsed,
    required this.rewardedShuffles,
    required this.undos,
    required this.longestStreak,
    required this.tilesMatched,
    required this.parMs,
    required this.stars,
  });

  final int elapsedMs;
  final int hintsUsed;
  final int shufflesUsed;
  final int rewardedShuffles;
  final int undos;
  final int longestStreak;
  final int tilesMatched;

  /// Par used for [stars], or null when the layout has none.
  final int? parMs;

  /// 1–3, or null when [parMs] is null.
  final int? stars;

  @override
  String toString() =>
      'ClearStats(elapsedMs: $elapsedMs, stars: $stars, hints: $hintsUsed, '
      'shuffles: $shufflesUsed (rewarded $rewardedShuffles), undos: $undos, longestStreak: $longestStreak)';
}

/// Immutable snapshot of a board in play.
final class GameState {
  GameState({
    required this.layout,
    required this.seed,
    required this.options,
    required Int8List faces,
    required this.removed,
    required this.selected,
    required List<HistoryEntry> history,
    required List<MoveLogEntry> moveLog,
    required this.hintsUsed,
    required this.freeHintsLeft,
    required this.shufflesUsed,
    required this.freeShufflesLeft,
    required this.rewardedShuffles,
    required this.shuffleCount,
    required this.undos,
    required this.currentStreak,
    required this.longestStreak,
    required this.lastElapsedMs,
    required this.parMs,
    this.verifiedBySolver = false,
  }) : faces = Int8List.fromList(faces).asUnmodifiableView(),
       history = List.unmodifiable(history),
       moveLog = List.unmodifiable(moveLog);

  /// Deals [layout] for [seed] and verifies the deal with the forward solver.
  ///
  /// Throws [DealException] if the layout cannot be dealt, or if the deal is
  /// neither confirmed by the solver nor by replaying its construction order
  /// (which would be an engine bug). A solver budget overrun alone does not
  /// throw, because the construction order is itself a proof; it leaves
  /// [verifiedBySolver] false so the caller can report it.
  factory GameState.newGame(
    Layout layout,
    int seed, {
    DealerOptions options = DealerOptions.production,
    int? parMs,
    bool verify = true,
    int solverBudget = kVerifyBudget,
  }) {
    final d = deal(layout, seed, options: options);
    var bySolver = false;
    if (verify) {
      final r = solve(layout, d.faces, budget: solverBudget);
      bySolver = r is SolveSolvable;
      if (r is SolveUnsolvable || (!bySolver && !isValidSolution(layout, d.faces, d.solution))) {
        throw DealException('deal for "${layout.id}" seed $seed failed verification: $r');
      }
    }
    return GameState(
      layout: layout,
      seed: seed & 0xFFFFFFFF,
      options: options,
      faces: d.faces,
      removed: TileSet.empty(layout.length),
      selected: null,
      history: const [],
      moveLog: const [],
      hintsUsed: 0,
      freeHintsLeft: kFreeHintsPerBoard,
      shufflesUsed: 0,
      freeShufflesLeft: kFreeShufflesPerBoard,
      rewardedShuffles: 0,
      shuffleCount: 0,
      undos: 0,
      currentStreak: 0,
      longestStreak: 0,
      lastElapsedMs: 0,
      parMs: parMs ?? layout.parMs,
      verifiedBySolver: bySolver,
    );
  }

  final Layout layout;

  /// Deal seed (32-bit).
  final int seed;

  /// Dealer options of the deal; shuffles use the same.
  final DealerOptions options;

  /// Face id per position index. Removed positions keep their last face.
  final Int8List faces;

  /// Removed positions.
  final TileSet removed;

  /// Selected position, if any.
  final int? selected;

  /// Undo stack (last = most recent).
  final List<HistoryEntry> history;

  /// Append-only log for daily verification (includes hints and undos).
  final List<MoveLogEntry> moveLog;

  final int hintsUsed;
  final int freeHintsLeft;
  final int shufflesUsed;
  final int freeShufflesLeft;

  /// Shuffles paid with a rewarded ad (cost the 3rd star).
  final int rewardedShuffles;

  /// Shuffles performed so far, never decremented by undo. The next
  /// shuffle's sub-seed is `shuffleSeed(seed, shuffleCount)`.
  final int shuffleCount;

  final int undos;

  /// Consecutive matches since the last mismatch or undo.
  final int currentStreak;
  final int longestStreak;

  /// Largest elapsed time passed to a command so far (log times never go
  /// backwards).
  final int lastElapsedMs;

  /// Par for stars, from the layout unless overridden.
  final int? parMs;

  /// Whether the forward solver confirmed the deal in [GameState.newGame]
  /// (false when created otherwise or verification was skipped).
  final bool verifiedBySolver;

  int get generatorVersion => kGeneratorVersion;

  /// Positions still on the board.
  late final TileSet remaining = layout.all.removeAll(removed.toList());

  /// Tiles matched so far (removed count).
  int get tilesMatched => removed.length;

  bool get isCleared => removed.length == layout.length;

  /// Free remaining positions, ascending.
  late final List<int> freeTiles = List.unmodifiable(layout.freeTiles(remaining));

  bool isFree(int pos) => !removed.contains(pos) && layout.isFree(pos, remaining);

  /// Matching free pairs (a < b), ascending.
  late final List<(int, int)> availableMoves = List.unmodifiable(() {
    final out = <(int, int)>[];
    final f = freeTiles;
    for (var i = 0; i < f.length; i++) {
      for (var j = i + 1; j < f.length; j++) {
        if (facesMatch(faces[f[i]], faces[f[j]])) out.add((f[i], f[j]));
      }
    }
    return out;
  }());

  /// Tiles remain and no matching free pair exists.
  bool get isDeadlocked => !isCleared && availableMoves.isEmpty;

  /// Faces of the remaining tiles, ascending by position.
  List<int> get remainingFaces => [for (final p in remaining.toList()) faces[p]];

  GameState copyWith({
    Int8List? faces,
    TileSet? removed,
    int? Function()? selected,
    List<HistoryEntry>? history,
    List<MoveLogEntry>? moveLog,
    int? hintsUsed,
    int? freeHintsLeft,
    int? shufflesUsed,
    int? freeShufflesLeft,
    int? rewardedShuffles,
    int? shuffleCount,
    int? undos,
    int? currentStreak,
    int? longestStreak,
    int? lastElapsedMs,
  }) => GameState(
    layout: layout,
    seed: seed,
    options: options,
    faces: faces ?? this.faces,
    removed: removed ?? this.removed,
    selected: selected != null ? selected() : this.selected,
    history: history ?? this.history,
    moveLog: moveLog ?? this.moveLog,
    hintsUsed: hintsUsed ?? this.hintsUsed,
    freeHintsLeft: freeHintsLeft ?? this.freeHintsLeft,
    shufflesUsed: shufflesUsed ?? this.shufflesUsed,
    freeShufflesLeft: freeShufflesLeft ?? this.freeShufflesLeft,
    rewardedShuffles: rewardedShuffles ?? this.rewardedShuffles,
    shuffleCount: shuffleCount ?? this.shuffleCount,
    undos: undos ?? this.undos,
    currentStreak: currentStreak ?? this.currentStreak,
    longestStreak: longestStreak ?? this.longestStreak,
    lastElapsedMs: lastElapsedMs ?? this.lastElapsedMs,
    parMs: parMs,
    verifiedBySolver: verifiedBySolver,
  );

  /// JSON snapshot for "Resume" (saved_game). Restore with [GameState.fromJson]
  /// and the same layout.
  Map<String, Object?> toJson() => {
    'layoutId': layout.id,
    'layoutVersion': layout.version,
    'generatorVersion': generatorVersion,
    'seed': seed,
    'spreadCandidates': options.spreadCandidates,
    'faces': faces.toList(),
    'removed': removed.toList(),
    'selected': selected,
    'history': [
      for (final h in history)
        switch (h) {
          MatchEntry(:final a, :final b) => {
            'match': [a, b],
          },
          ShuffleEntry(:final previousFaces, :final subSeed, :final kind) => {
            'shuffle': subSeed,
            'kind': kind.name,
            'previousFaces': previousFaces.toList(),
          },
        },
    ],
    'moveLog': encodeMoveLog(moveLog),
    'hintsUsed': hintsUsed,
    'freeHintsLeft': freeHintsLeft,
    'shufflesUsed': shufflesUsed,
    'freeShufflesLeft': freeShufflesLeft,
    'rewardedShuffles': rewardedShuffles,
    'shuffleCount': shuffleCount,
    'undos': undos,
    'currentStreak': currentStreak,
    'longestStreak': longestStreak,
    'lastElapsedMs': lastElapsedMs,
    'parMs': parMs,
  };

  /// Restores a [toJson] snapshot. Throws [FormatException] when it does not
  /// fit [layout] or comes from another generator version.
  factory GameState.fromJson(Layout layout, Map<String, Object?> json) {
    T get<T>(String key) {
      final v = json[key];
      if (v is! T) throw FormatException('saved game: bad "$key"');
      return v;
    }

    if (get<String>('layoutId') != layout.id) throw const FormatException('saved game: layout mismatch');
    if (get<int>('generatorVersion') != kGeneratorVersion) {
      throw const FormatException('saved game: unsupported generator version');
    }
    Int8List facesOf(Object? list) {
      if (list is! List<Object?> || list.length != layout.length || list.any((f) => f is! int)) {
        throw const FormatException('saved game: bad faces');
      }
      return Int8List.fromList(list.cast<int>());
    }

    final removedList = get<List<Object?>>('removed').cast<int>();
    final history = <HistoryEntry>[];
    for (final h in get<List<Object?>>('history')) {
      if (h is! Map<String, Object?>) throw const FormatException('saved game: bad history');
      final m = h['match'];
      if (m is List<Object?> && m.length == 2) {
        history.add(MatchEntry(m[0]! as int, m[1]! as int));
      } else if (h['shuffle'] is int) {
        history.add(
          ShuffleEntry(
            facesOf(h['previousFaces']),
            h['shuffle']! as int,
            ShuffleKind.values.byName(h['kind']! as String),
          ),
        );
      } else {
        throw const FormatException('saved game: bad history entry');
      }
    }
    return GameState(
      layout: layout,
      seed: get<int>('seed'),
      options: DealerOptions(spreadCandidates: get<int>('spreadCandidates')),
      faces: facesOf(json['faces']),
      removed: TileSet.of(layout.length, removedList),
      selected: json['selected'] as int?,
      history: history,
      moveLog: decodeMoveLog(get<String>('moveLog')),
      hintsUsed: get<int>('hintsUsed'),
      freeHintsLeft: get<int>('freeHintsLeft'),
      shufflesUsed: get<int>('shufflesUsed'),
      freeShufflesLeft: get<int>('freeShufflesLeft'),
      rewardedShuffles: get<int>('rewardedShuffles'),
      shuffleCount: get<int>('shuffleCount'),
      undos: get<int>('undos'),
      currentStreak: get<int>('currentStreak'),
      longestStreak: get<int>('longestStreak'),
      lastElapsedMs: get<int>('lastElapsedMs'),
      parMs: json['parMs'] as int?,
    );
  }
}
