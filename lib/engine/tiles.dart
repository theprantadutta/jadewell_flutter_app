/// The 42 tile faces, their match keys and the 144-tile multiset.
///
/// Face ids are the same as `design/design-system/tile-faces.json`:
///   0–8 circles 1–9, 9–17 bamboo 1–9, 18–26 characters 1–9,
///   27–30 winds (E, S, W, N), 31–33 dragons (red, green, white),
///   34–37 flowers (plum, orchid, chrysanthemum, bamboo),
///   38–41 seasons (spring, summer, autumn, winter).
library;

/// Suit / group of a face.
enum TileKind { circles, bamboo, characters, wind, dragon, flower, season }

/// Number of distinct faces.
const int kFaceCount = 42;

/// Number of distinct match keys: 34 regular faces + FL + SE.
const int kMatchKeyCount = 36;

/// Match key shared by all flowers.
const int kFlowerKey = 34;

/// Match key shared by all seasons.
const int kSeasonKey = 35;

/// Tiles in a full set.
const int kFullSetSize = 144;

/// Face pairs in a full set.
const int kFullPairCount = 72;

/// One of the 42 faces.
final class TileFace {
  const TileFace._(this.id, this.code, this.name, this.kind, this.matchKey);

  /// Face id (0–41), identical to `tile-faces.json`.
  final int id;

  /// Two-character code for logs and the CLI (C1, B9, K5, WE, DR, F1, S4).
  final String code;

  /// English name, identical to `tile-faces.json`.
  final String name;

  final TileKind kind;

  /// Integer match key (0–35). Faces match iff their keys are equal.
  final int matchKey;

  /// Match key as used in `tile-faces.json` (`f0`…`f33`, `FL`, `SE`).
  String get matchKeyName => matchKey == kFlowerKey
      ? 'FL'
      : matchKey == kSeasonKey
      ? 'SE'
      : 'f$matchKey';

  /// Copies of this face in a full 144 set (4 for regular faces, 1 for bonus).
  int get copies => matchKey < kFlowerKey ? 4 : 1;

  @override
  String toString() => code;
}

/// All 42 faces, indexed by id.
final List<TileFace> kFaces = List.unmodifiable(_buildFaces());

List<TileFace> _buildFaces() {
  final faces = <TileFace>[];
  const suits = [
    (TileKind.circles, 'C', 'Circles'),
    (TileKind.bamboo, 'B', 'Bamboo'),
    (TileKind.characters, 'K', 'Characters'),
  ];
  for (final (kind, letter, name) in suits) {
    for (var rank = 1; rank <= 9; rank++) {
      final id = faces.length;
      faces.add(TileFace._(id, '$letter$rank', '$rank of $name', kind, id));
    }
  }
  const winds = [('WE', 'East Wind'), ('WS', 'South Wind'), ('WW', 'West Wind'), ('WN', 'North Wind')];
  for (final (code, name) in winds) {
    final id = faces.length;
    faces.add(TileFace._(id, code, name, TileKind.wind, id));
  }
  const dragons = [('DR', 'Red Dragon'), ('DG', 'Green Dragon'), ('DW', 'White Dragon')];
  for (final (code, name) in dragons) {
    final id = faces.length;
    faces.add(TileFace._(id, code, name, TileKind.dragon, id));
  }
  const flowers = ['Plum Flower', 'Orchid Flower', 'Chrysanthemum Flower', 'Bamboo Flower'];
  for (var i = 0; i < 4; i++) {
    faces.add(TileFace._(faces.length, 'F${i + 1}', flowers[i], TileKind.flower, kFlowerKey));
  }
  const seasons = ['Spring Season', 'Summer Season', 'Autumn Season', 'Winter Season'];
  for (var i = 0; i < 4; i++) {
    faces.add(TileFace._(faces.length, 'S${i + 1}', seasons[i], TileKind.season, kSeasonKey));
  }
  assert(faces.length == kFaceCount);
  return faces;
}

/// Match key of face [faceId].
int matchKeyOf(int faceId) => faceId < kFlowerKey
    ? faceId
    : faceId < 38
    ? kFlowerKey
    : kSeasonKey;

/// Whether two faces match (identical, or both flowers, or both seasons).
bool facesMatch(int faceA, int faceB) => matchKeyOf(faceA) == matchKeyOf(faceB);

/// The 144-tile multiset in ascending face-id order
/// (0,0,0,0, 1,1,1,1, …, 33,33,33,33, 34,35,36,37, 38,39,40,41).
List<int> fullTileSet() => [
  for (var f = 0; f < kFaceCount; f++)
    for (var c = 0; c < kFaces[f].copies; c++) f,
];

/// Groups a face multiset into matching pairs, the canonical way:
/// sort ascending by face id, then pair consecutive entries.
///
/// Because faces of one match key have contiguous ids, this works exactly
/// when every match key occurs an even number of times; otherwise throws
/// [ArgumentError]. For the full set it yields the 72 canonical pairs
/// (0,0),(0,0),(1,1),(1,1),…,(33,33),(33,33),(34,35),(36,37),(38,39),(40,41).
List<(int, int)> facePairs(Iterable<int> faces) {
  final sorted = faces.toList()..sort();
  if (sorted.length.isOdd) {
    throw ArgumentError('odd number of faces (${sorted.length})');
  }
  final pairs = <(int, int)>[];
  for (var i = 0; i < sorted.length; i += 2) {
    final a = sorted[i], b = sorted[i + 1];
    if (a < 0 || b >= kFaceCount) throw ArgumentError('face id out of range');
    if (!facesMatch(a, b)) {
      throw ArgumentError('faces do not pair up: match key of face $a has an odd count');
    }
    pairs.add((a, b));
  }
  return pairs;
}

/// The 72 canonical face pairs of a full set.
final List<(int, int)> kCanonicalPairs = List.unmodifiable(facePairs(fullTileSet()));
