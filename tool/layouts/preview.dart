// Prints a top-view ASCII preview of each layout: one character per half-tile
// cell, showing the height of the stack there (1 = one tile, 2 = two, ...).
// Each tile covers 2 x 2 cells, so half offsets show up as shifted blocks.
//
//   dart run tool/layouts/preview.dart            # every layout
//   dart run tool/layouts/preview.dart crab cat   # selected layouts

import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent.parent;
  final dir = Directory('${root.path}/assets/layouts');
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
    final json = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
    final id = json['id']! as String;
    if (args.isNotEmpty && !args.contains(id)) continue;
    final tiles = [
      for (final t
          in (json['tiles']! as List<Object?>).cast<Map<String, Object?>>())
        (t['x']! as int, t['y']! as int, t['z']! as int),
    ];
    final minX = tiles.map((t) => t.$1).reduce(min);
    final minY = tiles.map((t) => t.$2).reduce(min);
    final w = tiles.map((t) => t.$1).reduce(max) + 2 - minX;
    final h = tiles.map((t) => t.$2).reduce(max) + 2 - minY;
    final height = List.generate(h, (_) => List<int>.filled(w, 0));
    for (final (x, y, _) in tiles) {
      for (var dy = 0; dy < 2; dy++) {
        for (var dx = 0; dx < 2; dx++) {
          height[y - minY + dy][x - minX + dx]++;
        }
      }
    }
    stdout.writeln(
      '${json['name']} ($id) - ${tiles.length} tiles, ${json['difficulty']}',
    );
    for (final row in height) {
      stdout.writeln(row.map((v) => v == 0 ? '.' : '$v').join());
    }
    stdout.writeln();
  }
}
