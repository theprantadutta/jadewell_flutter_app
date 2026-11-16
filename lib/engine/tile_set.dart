import 'dart:typed_data';

/// Immutable set of position indices (0–143+), stored as 32-bit words so it
/// behaves identically on the Dart VM and on the web.
final class TileSet {
  TileSet._(this._words);

  /// Empty set able to hold [capacity] positions.
  factory TileSet.empty(int capacity) => TileSet._(Uint32List(wordsFor(capacity)));

  /// Set containing 0 … [count]−1.
  factory TileSet.full(int count) {
    final w = Uint32List(wordsFor(count));
    for (var i = 0; i < count; i++) {
      w[i >> 5] |= 1 << (i & 31);
    }
    return TileSet._(w);
  }

  /// Set of the given indices, with room for [capacity] positions.
  factory TileSet.of(int capacity, Iterable<int> indices) {
    final w = Uint32List(wordsFor(capacity));
    for (final i in indices) {
      w[i >> 5] |= 1 << (i & 31);
    }
    return TileSet._(w);
  }

  /// Wraps [words] without copying. The caller must not mutate them afterwards.
  factory TileSet.fromWords(Uint32List words) => TileSet._(words);

  final Uint32List _words;

  static int wordsFor(int capacity) => (capacity + 31) >> 5;

  /// Copy of the underlying words.
  Uint32List get words => Uint32List.fromList(_words);

  bool contains(int i) => (_words[i >> 5] >> (i & 31)) & 1 == 1;

  TileSet add(int i) => _with(i, true);

  TileSet remove(int i) => _with(i, false);

  TileSet addAll(Iterable<int> indices) {
    final w = Uint32List.fromList(_words);
    for (final i in indices) {
      w[i >> 5] |= 1 << (i & 31);
    }
    return TileSet._(w);
  }

  TileSet removeAll(Iterable<int> indices) {
    final w = Uint32List.fromList(_words);
    for (final i in indices) {
      w[i >> 5] &= ~(1 << (i & 31));
    }
    return TileSet._(w);
  }

  TileSet _with(int i, bool on) {
    final w = Uint32List.fromList(_words);
    if (on) {
      w[i >> 5] |= 1 << (i & 31);
    } else {
      w[i >> 5] &= ~(1 << (i & 31));
    }
    return TileSet._(w);
  }

  /// Number of members.
  int get length {
    var n = 0;
    for (final w in _words) {
      n += popCount32(w);
    }
    return n;
  }

  bool get isEmpty {
    for (final w in _words) {
      if (w != 0) return false;
    }
    return true;
  }

  bool get isNotEmpty => !isEmpty;

  /// Members in ascending order.
  List<int> toList() {
    final out = <int>[];
    for (var wi = 0; wi < _words.length; wi++) {
      var w = _words[wi];
      var bit = 0;
      while (w != 0) {
        if (w & 1 == 1) out.add((wi << 5) + bit);
        w >>>= 1;
        bit++;
      }
    }
    return out;
  }

  @override
  bool operator ==(Object other) {
    if (other is! TileSet || other._words.length != _words.length) return false;
    for (var i = 0; i < _words.length; i++) {
      if (_words[i] != other._words[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(_words);

  @override
  String toString() => 'TileSet${toList()}';
}

/// Number of set bits in a 32-bit value.
int popCount32(int v) {
  v = v - ((v >>> 1) & 0x55555555);
  v = (v & 0x33333333) + ((v >>> 2) & 0x33333333);
  v = (v + (v >>> 4)) & 0x0F0F0F0F;
  v = v + (v >>> 8);
  v = v + (v >>> 16);
  return v & 0x3F;
}
