// Standalone geometry check for assets/layouts/*.json (pure Dart, dart:io).
//
//   dart run tool/layouts/check_geometry.dart [--passes 2000] [--seed 1]
//
// Checks every layout file (except index.json): even tile count in 72..144
// (36..144 for index.json's starter board),
// no overlap on a layer, support for every tile on z > 0, bounding box within
// 22 x 30 half-units, unique ids, and that every id in index.json has a file.
//
// Then runs a random simulated-removal test per layout: repeatedly remove two
// random free tiles from the full layout and count how often fewer than two
// free tiles remain before the board is empty ("stuck rate"). This mirrors the
// dealer's reverse construction without backtracking. It uses dart:math Random,
// which is fine for a tool (the engine has its own seeded PRNG).
//
// Exits 1 on any geometry error or a stuck rate above --max-stuck (default 5%).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Layouts whose stuck rate is reported but never fails the check. The turtle
/// is the canonical classic (Appendix A), generated elsewhere and not ours to
/// reshape; its lone cap tile gets random removal stuck often, which the
/// dealer's backtrack/reseed absorbs.
const Set<String> kStuckRateWarnOnly = {'turtle'};

/// Smallest regular layout; the starter board (index.json `starter`) may be
/// as small as [kMinStarterTiles].
const int kMinTiles = 72;
const int kMinStarterTiles = 36;

const int kMaxWidth = 22;
const int kMaxHeight = 30;

class Tile {
  Tile(this.x, this.y, this.z);
  final int x, y, z;
}

class Geometry {
  Geometry(this.tiles) {
    final n = tiles.length;
    covers = List.generate(n, (_) => <int>[]);
    left = List.generate(n, (_) => <int>[]);
    right = List.generate(n, (_) => <int>[]);
    for (var i = 0; i < n; i++) {
      final a = tiles[i];
      for (var j = 0; j < n; j++) {
        if (i == j) continue;
        final b = tiles[j];
        final dx = b.x - a.x;
        final dy = b.y - a.y;
        if (b.z == a.z + 1 && dx.abs() < 2 && dy.abs() < 2) covers[i].add(j);
        if (b.z == a.z && dy.abs() < 2) {
          if (dx == -2) left[i].add(j);
          if (dx == 2) right[i].add(j);
        }
      }
    }
  }

  final List<Tile> tiles;
  late final List<List<int>> covers;
  late final List<List<int>> left;
  late final List<List<int>> right;

  bool isFree(int i, List<bool> present) {
    for (final j in covers[i]) {
      if (present[j]) return false;
    }
    final blockedLeft = left[i].any((j) => present[j]);
    if (!blockedLeft) return true;
    return !right[i].any((j) => present[j]);
  }

  /// Returns the number of tiles left when stuck, or 0 when cleared.
  int simulate(Random rng) {
    final n = tiles.length;
    final present = List<bool>.filled(n, true);
    var remaining = n;
    final free = <int>[];
    while (remaining > 0) {
      free.clear();
      for (var i = 0; i < n; i++) {
        if (present[i] && isFree(i, present)) free.add(i);
      }
      if (free.length < 2) return remaining;
      final a = rng.nextInt(free.length);
      var b = rng.nextInt(free.length - 1);
      if (b >= a) b++;
      present[free[a]] = false;
      present[free[b]] = false;
      remaining -= 2;
    }
    return 0;
  }
}

List<String> validate(List<Tile> tiles, {bool starter = false}) {
  final errors = <String>[];
  final n = tiles.length;
  final minTiles = starter ? kMinStarterTiles : kMinTiles;
  if (n.isOdd) errors.add('odd tile count $n');
  if (n < minTiles || n > 144) errors.add('tile count $n outside $minTiles..144');
  final byZ = <int, List<Tile>>{};
  for (final t in tiles) {
    if (t.z < 0) errors.add('negative z at (${t.x},${t.y})');
    byZ.putIfAbsent(t.z, () => []).add(t);
  }
  for (final entry in byZ.entries) {
    final l = entry.value;
    for (var i = 0; i < l.length; i++) {
      for (var j = i + 1; j < l.length; j++) {
        if ((l[i].x - l[j].x).abs() < 2 && (l[i].y - l[j].y).abs() < 2) {
          errors.add(
            'overlap on z=${entry.key}: (${l[i].x},${l[i].y}) '
            '(${l[j].x},${l[j].y})',
          );
        }
      }
    }
  }
  for (final t in tiles) {
    if (t.z == 0) continue;
    final below = byZ[t.z - 1] ?? const <Tile>[];
    final supported = below.any(
      (b) => (b.x - t.x).abs() < 2 && (b.y - t.y).abs() < 2,
    );
    if (!supported) errors.add('unsupported tile (${t.x},${t.y},${t.z})');
  }
  if (tiles.isNotEmpty) {
    final w =
        tiles.map((t) => t.x).reduce(max) +
        2 -
        tiles.map((t) => t.x).reduce(min);
    final h =
        tiles.map((t) => t.y).reduce(max) +
        2 -
        tiles.map((t) => t.y).reduce(min);
    if (w > kMaxWidth || h > kMaxHeight) {
      errors.add(
        'bounding box ${w}x$h half-units exceeds '
        '${kMaxWidth}x$kMaxHeight',
      );
    }
  }
  return errors;
}

void main(List<String> args) {
  var passes = 2000;
  var seed = 1;
  var maxStuck = 0.05;
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == '--passes') passes = int.parse(args[i + 1]);
    if (args[i] == '--seed') seed = int.parse(args[i + 1]);
    if (args[i] == '--max-stuck') maxStuck = double.parse(args[i + 1]);
  }
  final root = File.fromUri(Platform.script).parent.parent.parent;
  final dir = Directory('${root.path}/assets/layouts');
  var failed = false;
  final ids = <String, String>{};
  final indexFile = File('${dir.path}/index.json');
  String? starter;
  if (indexFile.existsSync()) {
    final json = jsonDecode(indexFile.readAsStringSync()) as Map<String, Object?>;
    starter = (json['starter'] as Map<String, Object?>?)?['layout'] as String?;
  }
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where(
            (f) => f.path.endsWith('.json') && !f.path.endsWith('index.json'),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final f in files) {
    final name = f.uri.pathSegments.last;
    final Map<String, Object?> json;
    try {
      json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    } on FormatException catch (e) {
      stdout.writeln('FAIL $name: invalid JSON ($e)');
      failed = true;
      continue;
    }
    final id = json['id'] as String? ?? '';
    final errors = <String>[];
    if ('$id.json' != name) errors.add('id "$id" does not match file name');
    if (ids.containsKey(id)) errors.add('duplicate id "$id" (${ids[id]})');
    ids[id] = name;
    for (final key in ['name', 'difficulty', 'chapter', 'order', 'version']) {
      if (!json.containsKey(key)) errors.add('missing "$key"');
    }
    final tiles = [
      for (final t
          in (json['tiles'] as List<Object?>? ?? const [])
              .cast<Map<String, Object?>>())
        Tile(t['x']! as int, t['y']! as int, t['z']! as int),
    ];
    errors.addAll(validate(tiles, starter: id == starter));

    var stuck = 0;
    var stuckLeft = 0;
    if (errors.isEmpty) {
      final g = Geometry(tiles);
      final rng = Random(seed);
      for (var p = 0; p < passes; p++) {
        final left = g.simulate(rng);
        if (left > 0) {
          stuck++;
          stuckLeft += left;
        }
      }
    }
    final rate = stuck / passes;
    final layers = tiles.isEmpty ? 0 : tiles.map((t) => t.z).reduce(max) + 1;
    final w = tiles.isEmpty
        ? 0
        : tiles.map((t) => t.x).reduce(max) +
              2 -
              tiles.map((t) => t.x).reduce(min);
    final h = tiles.isEmpty
        ? 0
        : tiles.map((t) => t.y).reduce(max) +
              2 -
              tiles.map((t) => t.y).reduce(min);
    final stuckOk = rate <= maxStuck || kStuckRateWarnOnly.contains(id);
    final ok = errors.isEmpty && stuckOk;
    if (!ok) failed = true;
    final tag = !ok
        ? 'FAIL'
        : rate > maxStuck
        ? 'warn'
        : 'ok  ';
    stdout.writeln(
      '$tag ${id.padRight(10)} ${tiles.length.toString().padLeft(3)} '
      'tiles  ${(w / 2).toStringAsFixed(1)} x ${(h / 2).toStringAsFixed(1)} x $layers  '
      'stuck ${(rate * 100).toStringAsFixed(2)}%'
      '${stuck > 0 ? ' (avg ${(stuckLeft / stuck).toStringAsFixed(1)} left)' : ''}',
    );
    for (final e in errors) {
      stdout.writeln('       $e');
    }
  }

  final index = File('${dir.path}/index.json');
  if (!index.existsSync()) {
    stdout.writeln('FAIL index.json missing');
    failed = true;
  } else {
    final json = jsonDecode(index.readAsStringSync()) as Map<String, Object?>;
    final referenced = <String>[
      for (final c in json['chapters']! as List<Object?>)
        for (final l
            in (c! as Map<String, Object?>)['layouts']! as List<Object?>)
          (l! as Map<String, Object?>)['id']! as String,
      for (final d in json['dailyPool']! as List<Object?>) d! as String,
      ?starter,
    ];
    final seen = <String>{};
    for (final id in referenced) {
      if (!seen.add(id)) {
        stdout.writeln('FAIL index.json lists "$id" twice');
        failed = true;
      }
      if (!ids.containsKey(id)) {
        stdout.writeln(
          'FAIL index.json references "$id" but $id.json is missing',
        );
        failed = true;
      }
    }
  }
  stdout.writeln(failed ? 'FAILED' : 'all layouts ok');
  exit(failed ? 1 : 0);
}
