/// Compact move log for daily verification and its replay. The byte format
/// is shared with the C# server; see docs/ENGINE.md §Move log.
///
/// Format v1: base64url (RFC 4648 §5, no padding) of
///
///     version:u8 (= 1)
///     entry*:
///       0x00 match           a:varint b:varint dt:varint
///       0x01 shuffle credit  subSeed:u32le dt:varint
///       0x02 shuffle rewarded subSeed:u32le dt:varint
///       0x03 shuffle deadlock subSeed:u32le dt:varint
///       0x04 hint credit
///       0x05 hint rewarded
///       0x06 undo
///
/// varint = unsigned LEB128 (7 bits per byte, least significant group
/// first, high bit = more), at most 5 bytes, value < 2^32. `dt` = elapsed ms
/// minus the elapsed ms of the previous match/shuffle entry (0 for the first).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'commands.dart';
import 'dealer.dart';
import 'game_state.dart';
import 'layout.dart';
import 'scoring.dart';

/// Version byte of the encoding.
const int kMoveLogVersion = 1;

sealed class MoveLogEntry {
  const MoveLogEntry();
}

final class LogMatch extends MoveLogEntry {
  const LogMatch(this.a, this.b, this.elapsedMs);

  final int a, b, elapsedMs;

  @override
  bool operator ==(Object other) => other is LogMatch && other.a == a && other.b == b && other.elapsedMs == elapsedMs;

  @override
  int get hashCode => Object.hash(a, b, elapsedMs);

  @override
  String toString() => 'LogMatch($a, $b, ${elapsedMs}ms)';
}

final class LogShuffle extends MoveLogEntry {
  const LogShuffle(this.kind, this.subSeed, this.elapsedMs);

  final ShuffleKind kind;
  final int subSeed, elapsedMs;

  @override
  bool operator ==(Object other) =>
      other is LogShuffle && other.kind == kind && other.subSeed == subSeed && other.elapsedMs == elapsedMs;

  @override
  int get hashCode => Object.hash(kind, subSeed, elapsedMs);

  @override
  String toString() => 'LogShuffle(${kind.name}, $subSeed, ${elapsedMs}ms)';
}

final class LogHint extends MoveLogEntry {
  const LogHint(this.kind);

  final HintKind kind;

  @override
  bool operator ==(Object other) => other is LogHint && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;

  @override
  String toString() => 'LogHint(${kind.name})';
}

final class LogUndo extends MoveLogEntry {
  const LogUndo();

  @override
  bool operator ==(Object other) => other is LogUndo;

  @override
  int get hashCode => 6;

  @override
  String toString() => 'LogUndo()';
}

const int _tagMatch = 0x00;
const int _tagShuffleCredit = 0x01;
const int _tagShuffleRewarded = 0x02;
const int _tagShuffleDeadlock = 0x03;
const int _tagHintCredit = 0x04;
const int _tagHintRewarded = 0x05;
const int _tagUndo = 0x06;

/// Raw bytes of the log (before base64url).
Uint8List encodeMoveLogBytes(List<MoveLogEntry> entries) {
  final out = BytesBuilder(copy: false)..addByte(kMoveLogVersion);
  var prev = 0;
  void varint(int v) {
    if (v < 0 || v > 0xFFFFFFFF) throw ArgumentError('varint out of range: $v');
    while (v >= 0x80) {
      out.addByte((v & 0x7F) | 0x80);
      v >>>= 7;
    }
    out.addByte(v);
  }

  void dt(int elapsed) {
    if (elapsed < prev) throw ArgumentError('elapsed time went backwards ($elapsed < $prev)');
    varint(elapsed - prev);
    prev = elapsed;
  }

  for (final e in entries) {
    switch (e) {
      case LogMatch(:final a, :final b, :final elapsedMs):
        out.addByte(_tagMatch);
        varint(a);
        varint(b);
        dt(elapsedMs);
      case LogShuffle(:final kind, :final subSeed, :final elapsedMs):
        out.addByte(switch (kind) {
          ShuffleKind.credit => _tagShuffleCredit,
          ShuffleKind.rewarded => _tagShuffleRewarded,
          ShuffleKind.deadlock => _tagShuffleDeadlock,
        });
        final s = subSeed & 0xFFFFFFFF;
        out
          ..addByte(s & 0xFF)
          ..addByte((s >>> 8) & 0xFF)
          ..addByte((s >>> 16) & 0xFF)
          ..addByte((s >>> 24) & 0xFF);
        dt(elapsedMs);
      case LogHint(:final kind):
        out.addByte(kind == HintKind.credit ? _tagHintCredit : _tagHintRewarded);
      case LogUndo():
        out.addByte(_tagUndo);
    }
  }
  return out.takeBytes();
}

/// Encodes [entries] as base64url without padding.
String encodeMoveLog(List<MoveLogEntry> entries) => base64Url.encode(encodeMoveLogBytes(entries)).replaceAll('=', '');

/// Decodes raw log bytes. Throws [FormatException].
List<MoveLogEntry> decodeMoveLogBytes(List<int> bytes) {
  if (bytes.isEmpty) throw const FormatException('move log: empty');
  if (bytes[0] != kMoveLogVersion) throw FormatException('move log: unsupported version ${bytes[0]}');
  var pos = 1;
  var prev = 0;
  int byte() {
    if (pos >= bytes.length) throw const FormatException('move log: truncated');
    return bytes[pos++];
  }

  int varint() {
    var result = 0;
    for (var i = 0; i < 5; i++) {
      final b = byte();
      result += (b & 0x7F) * (1 << (7 * i));
      if (b & 0x80 == 0) {
        if (result > 0xFFFFFFFF) throw const FormatException('move log: varint overflow');
        return result;
      }
    }
    throw const FormatException('move log: varint too long');
  }

  int elapsed() => prev += varint();

  final out = <MoveLogEntry>[];
  while (pos < bytes.length) {
    final tag = byte();
    switch (tag) {
      case _tagMatch:
        final a = varint(), b = varint();
        out.add(LogMatch(a, b, elapsed()));
      case _tagShuffleCredit || _tagShuffleRewarded || _tagShuffleDeadlock:
        final s = byte() | (byte() << 8) | (byte() << 16) | (byte() * 0x1000000);
        final kind = tag == _tagShuffleCredit
            ? ShuffleKind.credit
            : tag == _tagShuffleRewarded
            ? ShuffleKind.rewarded
            : ShuffleKind.deadlock;
        out.add(LogShuffle(kind, s, elapsed()));
      case _tagHintCredit:
        out.add(const LogHint(HintKind.credit));
      case _tagHintRewarded:
        out.add(const LogHint(HintKind.rewarded));
      case _tagUndo:
        out.add(const LogUndo());
      default:
        throw FormatException('move log: unknown tag $tag at byte ${pos - 1}');
    }
  }
  return out;
}

/// Decodes a base64url log (padding optional). Throws [FormatException].
List<MoveLogEntry> decodeMoveLog(String encoded) => decodeMoveLogBytes(base64Url.decode(base64Url.normalize(encoded)));

/// Outcome of [replay].
final class ReplayResult {
  const ReplayResult({
    required this.legal,
    required this.cleared,
    this.error,
    this.errorIndex,
    this.finalTimeMs,
    this.stars,
    this.state,
  });

  /// Every entry was legal.
  final bool legal;

  /// The board was cleared by the last match (implies [legal]).
  final bool cleared;

  /// Why replay stopped, when not [legal].
  final String? error;

  /// Index of the offending entry (−1 for errors before the first entry).
  final int? errorIndex;

  /// Elapsed ms of the clearing match, when [cleared].
  final int? finalTimeMs;

  /// Stars for the clear, when [cleared] and a par is known.
  final int? stars;

  /// State after the last legal entry.
  final GameState? state;

  @override
  String toString() => legal
      ? 'ReplayResult(legal, cleared: $cleared, time: $finalTimeMs, stars: $stars)'
      : 'ReplayResult(illegal at $errorIndex: $error)';
}

/// Replays an encoded move log on the deal (layout, seed, generator version)
/// the way the server verifies a daily result.
///
/// Rules: matches must be legal moves; a shuffle's sub-seed must equal
/// `shuffleSeed(seed, n)` for the n-th shuffle (0-based, counting undone
/// ones); a deadlock shuffle requires a deadlock; hints require a move to
/// exist; undo requires history; nothing may follow the clearing match.
/// Free-credit counts are not enforced (bonus credits are granted outside
/// the log), but kinds are kept, so stars count rewarded shuffles.
ReplayResult replay(
  Layout layout,
  int seed,
  int generatorVersion,
  String encodedLog, {
  int? parMs,
  DealerOptions options = DealerOptions.production,
}) {
  ReplayResult fail(String error, int index, GameState? s) =>
      ReplayResult(legal: false, cleared: false, error: error, errorIndex: index, state: s);

  if (generatorVersion != kGeneratorVersion) {
    return fail('unsupported generator version $generatorVersion', -1, null);
  }
  final List<MoveLogEntry> entries;
  try {
    entries = decodeMoveLog(encodedLog);
  } on FormatException catch (e) {
    return fail(e.message, -1, null);
  }
  final GameState start;
  try {
    start = GameState.newGame(layout, seed, options: options, parMs: parMs, verify: false);
  } on DealException catch (e) {
    return fail(e.message, -1, null);
  }
  var s = start;
  for (var i = 0; i < entries.length; i++) {
    if (s.isCleared) return fail('entry after the board was cleared', i, s);
    final e = entries[i];
    switch (e) {
      case LogMatch(:final a, :final b, :final elapsedMs):
        final (next, events) = match(s, a, b, elapsedMs: elapsedMs);
        if (identical(next, s)) return fail('illegal match ($a, $b): ${events.join(', ')}', i, s);
        s = next;
      case LogShuffle(:final kind, :final subSeed, :final elapsedMs):
        final expected = shuffleSeed(seed, s.shuffleCount);
        if (subSeed != expected) return fail('shuffle sub-seed $subSeed, expected $expected', i, s);
        if (kind == ShuffleKind.deadlock && !s.isDeadlocked) return fail('deadlock shuffle without deadlock', i, s);
        final next = applyShuffle(s, kind, elapsedMs: elapsedMs, verify: false);
        if (next == null) return fail('shuffle impossible', i, s);
        s = next.$1;
      case LogHint(:final kind):
        if (s.availableMoves.isEmpty) return fail('hint on a deadlocked board', i, s);
        s = s.copyWith(
          hintsUsed: s.hintsUsed + 1,
          freeHintsLeft: kind == HintKind.credit && s.freeHintsLeft > 0 ? s.freeHintsLeft - 1 : s.freeHintsLeft,
          moveLog: [...s.moveLog, e],
        );
      case LogUndo():
        final (next, _) = undo(s);
        if (identical(next, s)) return fail('undo with empty history', i, s);
        s = next;
    }
  }
  final par = parMs ?? layout.parMs;
  final cleared = s.isCleared;
  final time = cleared ? s.lastElapsedMs : null;
  return ReplayResult(
    legal: true,
    cleared: cleared,
    finalTimeMs: time,
    stars: cleared && par != null
        ? starsFor(timeMs: time!, parMs: par, hintsUsed: s.hintsUsed, rewardedShuffles: s.rewardedShuffles)
        : null,
    state: s,
  );
}
