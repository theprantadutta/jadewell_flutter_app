// Generates assets/layouts/turtle.json: the classic 144-tile turtle turned
// upright for portrait (brief Appendix A).
//
//   dart run tool/gen_turtle.dart            # writes assets/layouts/turtle.json
//   dart run tool/gen_turtle.dart --check    # exits 1 if the file is stale
//
// Classic coordinates are (col, row, layer) in whole tiles, col 0–11, row 0–7,
// with half-tile offsets for the end tiles and the cap. Upright transform:
// newCol = row, newRow = col + 1. Half-tile units: x = 2·newCol, y = 2·newRow.

import 'dart:convert';
import 'dart:io';

import 'package:jadewell_flutter_app/engine/layout.dart';

/// Classic turtle positions as (col, row, layer); cols/rows may be x.5.
List<(double, double, int)> classicTurtle() {
  final out = <(double, double, int)>[];
  // Layer 0: row → inclusive col range.
  const rows = {0: (0, 11), 1: (2, 9), 2: (1, 10), 3: (0, 11), 4: (0, 11), 5: (1, 10), 6: (2, 9), 7: (0, 11)};
  rows.forEach((row, range) {
    for (var col = range.$1; col <= range.$2; col++) {
      out.add((col.toDouble(), row.toDouble(), 0));
    }
  });
  out
    ..add((-1, 3.5, 0))
    ..add((12, 3.5, 0))
    ..add((13, 3.5, 0));
  void block(int c0, int c1, int r0, int r1, int z) {
    for (var row = r0; row <= r1; row++) {
      for (var col = c0; col <= c1; col++) {
        out.add((col.toDouble(), row.toDouble(), z));
      }
    }
  }

  block(3, 8, 1, 6, 1);
  block(4, 7, 2, 5, 2);
  block(5, 6, 3, 4, 3);
  out.add((5.5, 3.5, 4));
  return out;
}

/// Upright half-unit positions in canonical (z, y, x) order.
List<Position> uprightTurtle() {
  final out = <Position>[];
  for (final (col, row, z) in classicTurtle()) {
    final newCol = row;
    final newRow = col + 1;
    final x = newCol * 2, y = newRow * 2;
    if (x != x.roundToDouble() || y != y.roundToDouble()) {
      throw StateError('non-integer half-unit at ($col, $row, $z)');
    }
    out.add(Position(x.round(), y.round(), z));
  }
  out.sort(Position.compare);
  return out;
}

String turtleJson() {
  final tiles = uprightTurtle();
  final b = StringBuffer()
    ..writeln('{')
    ..writeln('  "id": "turtle",')
    ..writeln('  "name": "Turtle",')
    ..writeln('  "version": 1,')
    ..writeln('  "difficulty": "medium",')
    ..writeln('  "chapter": "classics",')
    ..writeln('  "order": 2,')
    ..writeln('  "parMs": 360000,')
    ..writeln('  "tiles": [');
  for (var i = 0; i < tiles.length; i++) {
    final t = tiles[i];
    b.writeln('    ${jsonEncode(t.toJson())}${i == tiles.length - 1 ? '' : ','}');
  }
  b
    ..writeln('  ]')
    ..writeln('}');
  return b.toString();
}

void main(List<String> args) {
  final json = turtleJson();
  final layout = Layout.parse(json); // validates; throws on error
  final e = layout.extent;
  if (layout.length != 144 || e.width != 8 || e.height != 15) {
    stderr.writeln('gen_turtle: unexpected shape ${layout.length} tiles, ${e.width}×${e.height}');
    exit(1);
  }
  final file = File('assets/layouts/turtle.json');
  if (args.contains('--check')) {
    if (!file.existsSync() || file.readAsStringSync().replaceAll('\r\n', '\n') != json) {
      stderr.writeln('gen_turtle: assets/layouts/turtle.json is stale; run dart run tool/gen_turtle.dart');
      exit(1);
    }
    stdout.writeln('gen_turtle: OK');
    return;
  }
  file.writeAsStringSync(json);
  stdout.writeln('gen_turtle: wrote ${file.path} (${layout.length} tiles, ${e.width}×${e.height}, ${e.layers} layers)');
}
