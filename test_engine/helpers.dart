import 'dart:io';
import 'dart:typed_data';

import 'package:jadewell_flutter_app/engine/engine.dart';

/// Repo root (tests run from the package root).
String get repoRoot => Directory.current.path;

Layout loadLayout(String id) => Layout.parse(File('$repoRoot/assets/layouts/$id.json').readAsStringSync());

/// Every bundled layout (assets/layouts/*.json except index.json), by id.
List<File> bundledLayoutFiles() {
  final dir = Directory('$repoRoot/assets/layouts');
  return dir.listSync().whereType<File>().where((f) {
    final name = f.uri.pathSegments.last;
    return name.endsWith('.json') && name != 'index.json';
  }).toList()..sort((a, b) => a.path.compareTo(b.path));
}

/// Small layout from (x, y, z) triples.
Layout tinyLayout(List<(int, int, int)> tiles, {String id = 'tiny', int? parMs}) =>
    Layout.fromPositions(id, [for (final (x, y, z) in tiles) Position(x, y, z)], parMs: parMs);

/// Index of the position (x, y, z) in [layout].
int idx(Layout layout, int x, int y, int z) => layout.positions.indexOf(Position(x, y, z));

/// A game on [layout] with hand-picked [faces] (face id per position index).
GameState gameWithFaces(Layout layout, List<int> faces, {int? parMs, int seed = 1}) {
  final base = GameState.newGame(layout, seed, options: DealerOptions.unbiased, verify: false, parMs: parMs);
  return base.copyWith(faces: Int8List.fromList(faces));
}
