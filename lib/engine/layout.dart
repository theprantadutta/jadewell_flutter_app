/// Layouts as data: half-tile grid positions, validation and neighbour lists.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'tile_set.dart';

/// Hard upper bound on positions (one full tile set).
const int kMaxPositions = 144;

/// A tile slot. `x`, `y` are half-tile units (the tile covers
/// `[x, x+2) × [y, y+2)`), `z` is the layer (0 = bottom).
final class Position {
  const Position(this.x, this.y, this.z);

  final int x, y, z;

  /// Canonical order: by z, then y, then x.
  static int compare(Position a, Position b) {
    if (a.z != b.z) return a.z - b.z;
    if (a.y != b.y) return a.y - b.y;
    return a.x - b.x;
  }

  /// Footprints overlap (`|dx| < 2 && |dy| < 2`), ignoring layers.
  bool overlaps(Position o) => (x - o.x).abs() < 2 && (y - o.y).abs() < 2;

  Map<String, int> toJson() => {'x': x, 'y': y, 'z': z};

  @override
  bool operator ==(Object other) => other is Position && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '($x,$y,$z)';
}

/// Thrown when a layout JSON cannot be parsed or fails validation.
final class LayoutException implements Exception {
  LayoutException(this.layoutId, this.errors);

  final String layoutId;
  final List<String> errors;

  @override
  String toString() => 'LayoutException($layoutId): ${errors.join('; ')}';
}

/// Raw, unvalidated layout data as read from JSON.
final class LayoutData {
  const LayoutData({
    required this.id,
    required this.name,
    required this.version,
    required this.tiles,
    this.difficulty,
    this.chapter,
    this.order,
    this.parMs,
  });

  /// Parses the §5.2 schema. Unknown keys are ignored. Throws
  /// [LayoutException] for structural problems (missing keys, wrong types).
  factory LayoutData.fromJson(Object? json) {
    final errors = <String>[];
    if (json is! Map<String, Object?>) {
      throw LayoutException('?', ['layout JSON must be an object']);
    }
    final id = json['id'];
    final name = json['name'];
    final version = json['version'] ?? 1;
    final tilesJson = json['tiles'];
    if (id is! String || id.isEmpty) errors.add('"id" must be a non-empty string');
    if (name is! String) errors.add('"name" must be a string');
    if (version is! int) errors.add('"version" must be an integer');
    final tiles = <Position>[];
    if (tilesJson is! List<Object?>) {
      errors.add('"tiles" must be an array');
    } else {
      for (var i = 0; i < tilesJson.length; i++) {
        final t = tilesJson[i];
        if (t is Map<String, Object?> && t['x'] is int && t['y'] is int && t['z'] is int) {
          tiles.add(Position(t['x']! as int, t['y']! as int, t['z']! as int));
        } else {
          errors.add('tiles[$i] must be {"x":int,"y":int,"z":int}');
        }
      }
    }
    final layoutId = id is String ? id : '?';
    if (errors.isNotEmpty) throw LayoutException(layoutId, errors);
    final par = json['parMs'];
    final order = json['order'];
    return LayoutData(
      id: id! as String,
      name: name! as String,
      version: version as int,
      tiles: tiles,
      difficulty: json['difficulty'] is String ? json['difficulty']! as String : null,
      chapter: json['chapter'] is String ? json['chapter']! as String : null,
      order: order is int ? order : null,
      parMs: par is int ? par : null,
    );
  }

  factory LayoutData.parse(String source) => LayoutData.fromJson(jsonDecode(source));

  final String id;
  final String name;
  final int version;
  final List<Position> tiles;
  final String? difficulty;
  final String? chapter;
  final int? order;
  final int? parMs;

  /// Validation errors (empty when valid). See [Layout.validate].
  List<String> validate() => Layout.validate(tiles);

  /// Validates and builds the [Layout]; throws [LayoutException] on errors.
  Layout build() {
    final errors = validate();
    if (errors.isNotEmpty) throw LayoutException(id, errors);
    return Layout._(this);
  }
}

/// A validated layout with positions in canonical order and precomputed
/// neighbour lists.
///
/// **Canonical order**: positions sorted by (z, y, x) ascending. A position
/// index is the index in that order. Faces, solutions, move logs and the C#
/// port all refer to positions by this index.
final class Layout {
  Layout._(LayoutData data)
    : id = data.id,
      name = data.name,
      version = data.version,
      difficulty = data.difficulty,
      chapter = data.chapter,
      order = data.order,
      parMs = data.parMs,
      positions = List.unmodifiable(List<Position>.of(data.tiles)..sort(Position.compare)) {
    final n = positions.length;
    final cover = List.generate(n, (_) => <int>[]);
    final under = List.generate(n, (_) => <int>[]);
    final left = List.generate(n, (_) => <int>[]);
    final right = List.generate(n, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      final p = positions[i];
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        final q = positions[j];
        final dx = q.x - p.x, dy = q.y - p.y;
        if (dy.abs() >= 2) continue;
        if (q.z == p.z + 1 && dx.abs() < 2) cover[i].add(j);
        if (q.z == p.z - 1 && dx.abs() < 2) under[i].add(j);
        if (q.z == p.z && dx == -2) left[i].add(j);
        if (q.z == p.z && dx == 2) right[i].add(j);
      }
    }
    final c = _flatten(cover), u = _flatten(under), l = _flatten(left), r = _flatten(right);
    _coverStart = c.$1;
    _cover = c.$2;
    _underStart = u.$1;
    _under = u.$2;
    _leftStart = l.$1;
    _left = l.$2;
    _rightStart = r.$1;
    _right = r.$2;
  }

  /// Parses and validates; throws [LayoutException].
  factory Layout.fromJson(Object? json) => LayoutData.fromJson(json).build();

  /// Parses and validates; throws [LayoutException].
  factory Layout.parse(String source) => LayoutData.parse(source).build();

  /// Builds directly from positions (tests, tools). Throws on invalid input.
  factory Layout.fromPositions(String id, List<Position> tiles, {int? parMs}) =>
      LayoutData(id: id, name: id, version: 1, tiles: tiles, parMs: parMs).build();

  final String id;
  final String name;
  final int version;
  final String? difficulty;
  final String? chapter;
  final int? order;

  /// Par time in ms from the layout metadata, if present.
  final int? parMs;

  /// Positions in canonical (z, y, x) order.
  final List<Position> positions;

  int get length => positions.length;

  // Flattened neighbour lists: for position i the entries are
  // xs[start[i]] … xs[start[i+1]-1], each list sorted ascending.
  late final Int32List _coverStart, _cover; // tiles on z+1 overlapping i
  late final Int32List _underStart, _under; // tiles on z−1 overlapping i
  late final Int32List _leftStart, _left; // same z, dx == −2, |dy| < 2
  late final Int32List _rightStart, _right; // same z, dx == +2, |dy| < 2

  /// Positions on z+1 that overlap position [i] (block it while present).
  List<int> coveredBy(int i) => _slice(_coverStart, _cover, i);

  /// Positions on z−1 that position [i] overlaps (it blocks them).
  List<int> covers(int i) => _slice(_underStart, _under, i);

  /// Same-layer neighbours touching [i]'s left edge.
  List<int> leftOf(int i) => _slice(_leftStart, _left, i);

  /// Same-layer neighbours touching [i]'s right edge.
  List<int> rightOf(int i) => _slice(_rightStart, _right, i);

  /// Raw flattened neighbour tables for hot loops (the solver). Entries of
  /// position i live at `data[start[i]] … data[start[i+1]-1]`. Do not mutate.
  ({
    Int32List coverStart,
    Int32List cover,
    Int32List leftStart,
    Int32List left,
    Int32List rightStart,
    Int32List right,
    Int32List underStart,
    Int32List under,
  })
  get tables => (
    coverStart: _coverStart,
    cover: _cover,
    leftStart: _leftStart,
    left: _left,
    rightStart: _rightStart,
    right: _right,
    underStart: _underStart,
    under: _under,
  );

  static List<int> _slice(Int32List start, Int32List data, int i) =>
      Int32List.sublistView(data, start[i], start[i + 1]);

  static (Int32List, Int32List) _flatten(List<List<int>> lists) {
    final start = Int32List(lists.length + 1);
    var total = 0;
    for (var i = 0; i < lists.length; i++) {
      start[i] = total;
      total += lists[i].length;
    }
    start[lists.length] = total;
    final data = Int32List(total);
    var k = 0;
    for (final l in lists) {
      for (final v in l) {
        data[k++] = v;
      }
    }
    return (start, data);
  }

  /// Set of all positions.
  TileSet get all => TileSet.full(length);

  /// Free rule (brief §5.3) with respect to the positions in [remaining]:
  /// nothing in [remaining] covers [i], and not (some left neighbour remains
  /// and some right neighbour remains). [i] itself need not be in [remaining].
  bool isFree(int i, TileSet remaining) {
    for (var k = _coverStart[i]; k < _coverStart[i + 1]; k++) {
      if (remaining.contains(_cover[k])) return false;
    }
    var leftBlocked = false;
    for (var k = _leftStart[i]; k < _leftStart[i + 1]; k++) {
      if (remaining.contains(_left[k])) {
        leftBlocked = true;
        break;
      }
    }
    if (!leftBlocked) return true;
    for (var k = _rightStart[i]; k < _rightStart[i + 1]; k++) {
      if (remaining.contains(_right[k])) return false;
    }
    return true;
  }

  /// Free members of [remaining], ascending.
  List<int> freeTiles(TileSet remaining) => [
    for (final i in remaining.toList())
      if (isFree(i, remaining)) i,
  ];

  /// Tiles in [remaining] that keep [i] from being free, ascending:
  /// the covering tiles, plus both sides' neighbours when side-blocked.
  /// Empty when [i] is free.
  List<int> blockersOf(int i, TileSet remaining) {
    final out = <int>{
      for (final c in coveredBy(i))
        if (remaining.contains(c)) c,
    };
    final l = [
      for (final c in leftOf(i))
        if (remaining.contains(c)) c,
    ];
    final r = [
      for (final c in rightOf(i))
        if (remaining.contains(c)) c,
    ];
    if (l.isNotEmpty && r.isNotEmpty) out.addAll([...l, ...r]);
    return out.toList()..sort();
  }

  /// Validation errors for [tiles] (empty when valid):
  /// count is even and 2…144, coordinates are non-negative, no two tiles on
  /// the same layer overlap, and every tile on z > 0 overlaps at least one
  /// tile on z − 1.
  static List<String> validate(List<Position> tiles) {
    final errors = <String>[];
    final n = tiles.length;
    if (n < 2) errors.add('needs at least 2 tiles (has $n)');
    if (n > kMaxPositions) errors.add('at most $kMaxPositions tiles (has $n)');
    if (n.isOdd) errors.add('tile count must be even (has $n)');
    for (final t in tiles) {
      if (t.x < 0 || t.y < 0 || t.z < 0) errors.add('negative coordinate at $t');
    }
    final byLayer = <int, List<Position>>{};
    for (final t in tiles) {
      (byLayer[t.z] ??= []).add(t);
    }
    for (final layer in byLayer.values) {
      for (var i = 0; i < layer.length; i++) {
        for (var j = i + 1; j < layer.length; j++) {
          if (layer[i].overlaps(layer[j])) {
            errors.add('overlap on layer ${layer[i].z}: ${layer[i]} and ${layer[j]}');
          }
        }
      }
    }
    for (final t in tiles) {
      if (t.z == 0) continue;
      final below = byLayer[t.z - 1] ?? const <Position>[];
      if (!below.any(t.overlaps)) errors.add('unsupported tile $t (nothing on layer ${t.z - 1} below it)');
    }
    return errors;
  }

  /// Non-fatal findings: tiles overhanging a tile two or more layers below
  /// that no tile on the layer directly above covers. The free rule only
  /// looks at z+1, so such a lower tile counts as free while visually
  /// partly under the overhang.
  List<String> warnings() {
    final out = <String>[];
    for (var i = 0; i < length; i++) {
      final p = positions[i];
      for (var j = 0; j < length; j++) {
        final q = positions[j];
        if (q.z >= p.z + 2 && p.overlaps(q) && coveredBy(i).isEmpty) {
          out.add('$q overhangs $p with nothing on layer ${p.z + 1} covering it');
        }
      }
    }
    return out;
  }

  /// Width/height of the bounding box in tiles (half-units / 2, rounded up).
  ({int width, int height, int layers}) get extent {
    var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1, maxZ = 0;
    for (final p in positions) {
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x + 2 > maxX) maxX = p.x + 2;
      if (p.y + 2 > maxY) maxY = p.y + 2;
      if (p.z > maxZ) maxZ = p.z;
    }
    return (width: (maxX - minX + 1) ~/ 2, height: (maxY - minY + 1) ~/ 2, layers: maxZ + 1);
  }
}
