import 'dart:convert';

import 'package:flutter/services.dart';

/// Suit or honour family of a face.
enum TileKind { circles, bamboo, characters, wind, dragon, flower, season }

/// One pip (bead or capsule): centre as % of the glyph box, and a colour key
/// (`c1` blue, `c2` green, `c3` red for circles; `g` green, `b` dark teal,
/// `r` coral for bamboo).
class TileFaceElement {
  const TileFaceElement(this.x, this.y, this.colour);

  final double x;
  final double y;
  final String colour;
}

/// Geometry of one of the 42 faces, from `assets/tile-faces.json`.
class TileFaceSpec {
  const TileFaceSpec({
    required this.id,
    required this.matchKey,
    required this.name,
    required this.kind,
    required this.glyph,
    required this.index,
    required this.elements,
  });

  factory TileFaceSpec.fromJson(Map<String, Object?> j) => TileFaceSpec(
    id: (j['id']! as num).toInt(),
    matchKey: j['matchKey']! as String,
    name: j['name']! as String,
    kind: TileKind.values.byName(j['kind']! as String),
    glyph: j['glyph'] as String?,
    index: j['index'] as String?,
    elements: [
      for (final e in (j['elements'] as List<Object?>? ?? const []).cast<Map<String, Object?>>())
        TileFaceElement((e['x']! as num).toDouble(), (e['y']! as num).toDouble(), e['colour']! as String),
    ],
  );

  final int id;
  final String matchKey;
  final String name;
  final TileKind kind;

  /// CJK glyph for characters, winds, red/green dragons, flowers, seasons.
  final String? glyph;

  /// "1"–"4" for flowers and seasons.
  final String? index;
  final List<TileFaceElement> elements;

  /// 1–9 for suits (circles, bamboo, characters), else null.
  int? get rank => id < 27 ? id % 9 + 1 : null;

  bool get isWhiteDragon => kind == TileKind.dragon && glyph == null;

  static const assetPath = 'assets/tile-faces.json';

  static List<TileFaceSpec>? _cache;

  /// All 42 faces, ordered by id. Cached after the first load.
  static Future<List<TileFaceSpec>> load([AssetBundle? bundle]) async {
    if (_cache != null) return _cache!;
    final raw = await (bundle ?? rootBundle).loadString(assetPath);
    return _cache = parse(raw);
  }

  /// The cached faces, if [load] has completed.
  static List<TileFaceSpec>? get loaded => _cache;

  /// Parses the JSON list (also used by tests reading the file directly).
  static List<TileFaceSpec> parse(String json) {
    final list = (jsonDecode(json) as List<Object?>).cast<Map<String, Object?>>();
    final faces = [for (final j in list) TileFaceSpec.fromJson(j)]..sort((a, b) => a.id - b.id);
    return List.unmodifiable(faces);
  }

  /// Seeds the cache (tests, or after parsing elsewhere).
  static void prime(List<TileFaceSpec> faces) => _cache = faces;
}
