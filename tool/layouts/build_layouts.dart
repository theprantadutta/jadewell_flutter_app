// Generates assets/layouts/<id>.json (every layout except turtle, which has
// its own generator) and assets/layouts/index.json.
//
//   dart run tool/layouts/build_layouts.dart
//
// Coordinates follow the layout schema: x, y in half-tile units (a tile covers
// [x, x+2) x [y, y+2)), z = layer. Layers are authored as ASCII maps of FULL
// tiles, one character per tile:
//
//   '#'  tile at (2*col + dx, 2*row + dy)
//   'r'  same, shifted half a tile right   (x + 1)
//   'd'  same, shifted half a tile down    (y + 1)
//   'b'  same, shifted both ways           (x + 1, y + 1)
//   '.'  or space: no tile
//
// A whole layer can be offset with dx/dy (half units), which is how the
// half-offset "pyramid" layers are made. After building, every layout is
// translated so its minimum x and y are 0.
//
// Check the result with tool/layouts/check_geometry.dart and eyeball it with
// tool/layouts/preview.dart.

import 'dart:convert';
import 'dart:io';

typedef Cell = (int, int);

/// Parses an ASCII layer map (see the header comment).
Set<Cell> grid(List<String> rows, {int dx = 0, int dy = 0}) {
  final out = <Cell>{};
  for (var r = 0; r < rows.length; r++) {
    final row = rows[r];
    for (var c = 0; c < row.length; c++) {
      final ch = row[c];
      final x = 2 * c + dx;
      final y = 2 * r + dy;
      switch (ch) {
        case '#':
          out.add((x, y));
        case 'r':
          out.add((x + 1, y));
        case 'd':
          out.add((x, y + 1));
        case 'b':
          out.add((x + 1, y + 1));
        case '.' || ' ':
          break;
        default:
          throw ArgumentError('Unknown map character "$ch" in "$row"');
      }
    }
  }
  return out;
}

/// A solid block of [cols] x [rows] tiles with its top-left tile at (x, y).
Set<Cell> rect(int x, int y, int cols, int rows) => {
  for (var r = 0; r < rows; r++)
    for (var c = 0; c < cols; c++) (x + 2 * c, y + 2 * r),
};

/// Explicit tile positions.
Set<Cell> at(List<Cell> cells) => cells.toSet();

/// Tiles that sit on the crossing of every 2x2 block of [below] (half offset in
/// both directions): the classic stepped-pyramid layer.
Set<Cell> inset(Set<Cell> below) => {
  for (final (x, y) in below)
    if (below.contains((x + 2, y)) &&
        below.contains((x, y + 2)) &&
        below.contains((x + 2, y + 2)))
      (x + 1, y + 1),
};

enum Difficulty { easy, medium, hard }

const Map<Difficulty, double> kSecondsPerTile = {
  Difficulty.easy: 2.0,
  Difficulty.medium: 2.5,
  Difficulty.hard: 3.0,
};

class LayoutDef {
  LayoutDef(
    this.id,
    this.name,
    this.difficulty,
    this.chapter,
    this.order,
    this.layers, {
    this.parSeconds,
  });

  final String id;
  final String name;
  final Difficulty difficulty;
  final String chapter;
  final int order;

  /// layers[z] = tile positions on layer z.
  final List<Set<Cell>> layers;

  /// Par override in seconds (the starter board's short par); null derives
  /// it from the tile count and difficulty.
  final int? parSeconds;

  int get tileCount => layers.fold(0, (n, l) => n + l.length);

  int get parMs {
    if (parSeconds != null) return parSeconds! * 1000;
    final seconds = tileCount * kSecondsPerTile[difficulty]!;
    return (seconds / 5).round() * 5 * 1000;
  }

  List<(int, int, int)> get tiles {
    var minX = 1 << 30;
    var minY = 1 << 30;
    for (final layer in layers) {
      for (final (x, y) in layer) {
        if (x < minX) minX = x;
        if (y < minY) minY = y;
      }
    }
    final out = <(int, int, int)>[
      for (var z = 0; z < layers.length; z++)
        for (final (x, y) in layers[z]) (x - minX, y - minY, z),
    ];
    out.sort((a, b) {
      if (a.$3 != b.$3) return a.$3 - b.$3;
      if (a.$2 != b.$2) return a.$2 - b.$2;
      return a.$1 - b.$1;
    });
    return out;
  }

  String toJson() {
    final b = StringBuffer()
      ..writeln('{')
      ..writeln('  "id": ${jsonEncode(id)},')
      ..writeln('  "name": ${jsonEncode(name)},')
      ..writeln('  "version": 1,')
      ..writeln('  "difficulty": "${difficulty.name}",')
      ..writeln('  "chapter": ${jsonEncode(chapter)},')
      ..writeln('  "order": $order,')
      ..writeln('  "parMs": $parMs,')
      ..writeln('  "tiles": [');
    final t = tiles;
    for (var i = 0; i < t.length; i++) {
      final (x, y, z) = t[i];
      b.writeln(
        '    {"x": $x, "y": $y, "z": $z}${i == t.length - 1 ? '' : ','}',
      );
    }
    b
      ..writeln('  ]')
      ..writeln('}');
    return b.toString();
  }
}

// ---------------------------------------------------------------------------
// Warm-up (the starter board, played first by a new player)
// ---------------------------------------------------------------------------

/// A seedling in a pot: 40 tiles, two layers, short rows so most tiles start
/// free (27 of 40). One top tile sits on each leaf's middle (blocked anyway)
/// and a 2 x 2 cap straddles the pot, so there is a little depth without
/// hiding moves. Random play gets stuck in ~1.5% of games (the check allows
/// 5%); the dealer guarantees a solution regardless. Par 75 s.
LayoutDef sprout() => LayoutDef(
  'sprout',
  'Sprout',
  Difficulty.easy,
  'warmup',
  1,
  [
    grid([
      '##...##',
      '###.###',
      '.##.##.',
      '...#...',
      '...#...',
      '...#...',
      '#######',
      '.#####.',
      '.#####.',
    ]),
    at([(2, 2), (10, 2), (5, 13), (7, 13), (5, 15), (7, 15)]),
  ],
  parSeconds: 75,
);

// ---------------------------------------------------------------------------
// Classics
// ---------------------------------------------------------------------------

LayoutDef pyramid() => LayoutDef(
  'pyramid',
  'Pyramid',
  Difficulty.easy,
  'classics',
  1,
  [rect(0, 0, 8, 9), rect(1, 3, 7, 6), rect(5, 7, 3, 2)],
);

LayoutDef fortress() =>
    LayoutDef('fortress', 'Fortress', Difficulty.hard, 'classics', 3, [
      grid([
        '##########',
        '##......##',
        '#........#',
        '#........#',
        '#..####..#',
        '#..####..#',
        '#..####..#',
        '#..####..#',
        '#..####..#',
        '#........#',
        '#........#',
        '##......##',
        '##########',
      ]),
      grid([
        '##.####.##',
        '##......##',
        '..........',
        '..........',
        '#..####..#',
        '#..####..#',
        '#..####..#',
        '#..####..#',
        '#..####..#',
        '..........',
        '..........',
        '##......##',
        '##.####.##',
      ]),
      // Corner turret caps and the keep's roof.
      at([
        (1, 1),
        (17, 1),
        (1, 23),
        (17, 23),
        (8, 11),
        (10, 11),
        (8, 13),
        (10, 13),
      ]),
    ]);

LayoutDef bridge() =>
    LayoutDef('bridge', 'Bridge', Difficulty.easy, 'classics', 4, [
      grid([
        '##.......##',
        '##.......##',
        '###########',
        '###########',
        '##.......##',
        '##.......##',
        '##.......##',
        '##.......##',
      ]),
      // Towers, and a railing that straddles the two deck rows.
      {
        ...rect(0, 2, 2, 6),
        ...rect(18, 2, 2, 6),
        for (var x = 5; x <= 15; x += 2) (x, 5),
      },
      at([(1, 7), (19, 7)]),
    ]);

// ---------------------------------------------------------------------------
// Creatures
// ---------------------------------------------------------------------------

LayoutDef crab() =>
    LayoutDef('crab', 'Crab', Difficulty.medium, 'creatures', 1, [
      grid([
        '##.......##',
        '#.#.....#.#',
        '###.....###',
        '.##.....##.',
        '..#######..',
        '.#########.',
        '.#########.',
        '..#######..',
        '.#.#...#.#.',
        '#..#...#..#',
      ]),
      {...rect(6, 9, 5, 1), ...rect(6, 11, 5, 1), ...rect(6, 13, 5, 1)},
      at([(7, 11), (9, 11), (11, 11)]),
    ]);

LayoutDef dragon() =>
    LayoutDef('dragon', 'Dragon', Difficulty.hard, 'creatures', 2, [
      grid([
        '.....###.',
        '....#####',
        '...###...',
        '..###....',
        '.###.....',
        '.###.....',
        '.####....',
        '..#####..',
        '...#####.',
        '....####.',
        '.....###.',
        '....###..',
        '..####...',
        '.###.....',
        '##.......',
      ]),
      grid(dx: 1, [
        '.....##..',
        '....##...',
        '...#.....',
        '..#......',
        '.#.......',
        '.##......',
        '.##......',
        '..###....',
        '...##....',
        '....#....',
        '.....#...',
        '....#....',
        '..#......',
        '.#.......',
      ]),
      // Spine ridges.
      at([(10, 2), (4, 11), (6, 15), (8, 17)]),
    ]);

LayoutDef butterfly() =>
    LayoutDef('butterfly', 'Butterfly', Difficulty.medium, 'creatures', 3, [
      grid([
        '###.....###',
        '####...####',
        '#####.#####',
        '###########',
        '.#########.',
        '..#######..',
        '..#######..',
        '.#########.',
        '####.#.####',
        '###..#..###',
        '##...#...##',
      ]),
      grid(dx: 1, dy: 1, [
        '##......##',
        '..........',
        '####..####',
        '.###..###.',
        '..........',
        '..........',
        '.###..###.',
        '..........',
        '##......##',
      ]),
      at([(4, 6), (16, 6)]),
    ]);

LayoutDef cat() => LayoutDef('cat', 'Cat', Difficulty.hard, 'creatures', 4, [
  grid([
    '#.........#',
    '##.......##',
    '###.....###',
    '###########',
    '###########',
    '###########',
    '###########',
    '###########',
    '.#########.',
    '..#######..',
    '...#####...',
  ]),
  {
    ...grid([
      '...........',
      '...........',
      '...........',
      '..#######..',
      '..#.###.#..', // eyes
      '..#######..',
      '...#####...',
    ]),
    (1, 3), (19, 3), // ear tips
  },
  at([(9, 11), (11, 11)]), // nose
]);

// ---------------------------------------------------------------------------
// Wonders
// ---------------------------------------------------------------------------

LayoutDef spiral() =>
    LayoutDef('spiral', 'Spiral', Difficulty.medium, 'wonders', 1, [
      grid([
        '###########',
        '..........#',
        '#########.#',
        '#.......#.#',
        '#.#####.#.#',
        '#.#...#.#.#',
        '#.#...#.#.#',
        '#.#.#.#.#.#',
        '#.#.###.#.#',
        '#.#.....#.#',
        '#.#######.#',
        '#.........#',
        '###########',
      ]),
      // Raised walls on the four long runs, straddling the joints below.
      grid(dx: 1, [
        '##########',
        '..........',
        '########..',
        '..........',
        '..........',
        '..........',
        '..........',
        '..........',
        '..........',
        '..........',
        '..######..',
        '..........',
        '##########',
      ]),
    ]);

LayoutDef temple() {
  final z0 = grid([
    '....###....',
    '..#######..',
    '...#####...',
    '.#########.',
    '..#######..',
    '###########',
    '..#######..',
    '..#######..',
    '..##...##..',
    '###########',
    '###########',
  ]);
  // Roof tiers and the plinth get a second layer; the hall walls stay low.
  final z1 = inset(z0).where((c) => c.$2 <= 11 || c.$2 >= 19).toSet();
  return LayoutDef('temple', 'Temple', Difficulty.hard, 'wonders', 2, [
    z0,
    z1,
    inset(z1).where((c) => c.$2 <= 4).toSet(),
  ]);
}

LayoutDef arena() {
  final z0 = grid([
    '...#####...',
    '.#########.',
    '###.....###',
    '##.......##',
    '##.......##',
    '##..bb...##', // centre stage, half a tile off the grid
    '##..bb...##',
    '##.......##',
    '##.......##',
    '##.......##',
    '###.....###',
    '.#########.',
    '...#####...',
  ]);
  // Seating tiers ride the middle of the two-thick wall (the stage stays
  // flat), with grandstand tops over the two long ends.
  final z1 = inset(z0)..remove((10, 12));
  final z2 = {...rect(8, 1, 3, 1), ...rect(8, 23, 3, 1)};
  return LayoutDef('arena', 'Arena', Difficulty.medium, 'wonders', 3, [
    z0,
    z1,
    z2,
  ]);
}

LayoutDef tower() {
  final z0 = grid([
    '...#...',
    '..###..',
    '..###..',
    '.#####.',
    '..###..',
    '..###..',
    '..###..',
    '.#####.',
    '..###..',
    '..###..',
    '..###..',
    '#######',
    '#######',
    '#######',
  ]);
  final z1 = {...inset(z0), (6, 0)}; // the spire is two tiles tall
  return LayoutDef('tower', 'Tower', Difficulty.hard, 'wonders', 4, [
    z0,
    z1,
    inset(z1),
  ]);
}

// ---------------------------------------------------------------------------
// Daily pool
// ---------------------------------------------------------------------------

LayoutDef lotus() {
  final z0 = grid([
    '.....#.....',
    '....###....',
    '.#..###..#.',
    '.##.###.##.',
    '..#######..',
    '..#######..',
    '...#####...',
    '##.#####.##',
    '.#########.',
    '...#####...',
  ]);
  final z1 = inset(z0);
  // A raised bud at the heart of the centre petal.
  final z2 = inset(z1).where((c) => c.$2 <= 6).toSet();
  return LayoutDef('lotus', 'Lotus', Difficulty.medium, 'daily', 1, [
    z0,
    z1,
    z2,
  ]);
}

LayoutDef lantern() =>
    LayoutDef('lantern', 'Lantern', Difficulty.medium, 'daily', 2, [
      grid([
        '....#....',
        '..#####..',
        '.#######.',
        '#########',
        '#########',
        '#########',
        '#########',
        '.#######.',
        '..#####..',
        '....#....',
        '...###...',
        '....#....',
      ]),
      grid(dx: 1, dy: 1, [
        '........',
        '.######.',
        '.######.',
        '.######.',
        '.######.',
        '.######.',
        '..####..',
      ]),
    ]);

LayoutDef fan() => LayoutDef('fan', 'Fan', Difficulty.easy, 'daily', 3, [
  grid([
    '#.#.#.#.#.#',
    '.#########.',
    '###########',
    '.#########.',
    '..#######..',
    '...#####...',
    '....###....',
    '.....#.....',
    '.....#.....',
  ]),
  grid([
    '#.#.#.#.#.#',
    '..#.#.#.#..',
    '.#.#.#.#.#.',
    '..#.#.#.#..',
    '...#.#.#...',
    '....#.#....',
  ]),
]);

LayoutDef bonsai() {
  final z0 = grid([
    '..####.....',
    '.######....',
    '########...',
    '.######.###',
    '....##.####',
    '.....######',
    '......##...',
    '.....##....',
    '....##.....',
    '.#########.',
    '..#######..',
    '..#######..',
  ]);
  final z1 = inset(z0)..remove((9, 17)); // keep the trunk foot flat
  // A second crown on the big foliage pad.
  final z2 = inset(z1).where((c) => c.$2 <= 6 && c.$1 <= 12).toSet();
  return LayoutDef('bonsai', 'Bonsai', Difficulty.hard, 'daily', 4, [
    z0,
    z1,
    z2,
  ]);
}

LayoutDef koi() => LayoutDef('koi', 'Koi', Difficulty.medium, 'daily', 5, [
  grid([
    '...###...',
    '..#####..',
    '.#######.',
    '#########',
    '#########',
    '.#######.',
    '.#######.',
    '..#####..',
    '...###...',
    '....#....',
    '..#####..',
    '.#######.',
    '##.....##',
  ]),
  grid(dx: 1, dy: 1, [
    '........',
    '..####..',
    '.######.',
    '.######.',
    '..####..',
    '..####..',
    '...##...',
  ]),
]);

LayoutDef gate() =>
    LayoutDef('gate', 'Torii Gate', Difficulty.easy, 'daily', 6, [
      grid([
        '###########',
        '.#########.',
        '..#.....#..',
        '###########',
        '..#.....#..',
        '..#.....#..',
        '..#.....#..',
        '..#.....#..',
        '..#.....#..',
        '..#.....#..',
        '.###...###.',
      ]),
      grid(dx: 1, [
        '.########.',
        '..........',
        '..........',
        '..######..',
        '..........',
        '..........',
        '..........',
        '..........',
        '..........',
        '..........',
        '.##....##.',
      ]),
      rect(6, 0, 5, 1), // the curved crest of the top beam
    ]);

LayoutDef moon() => LayoutDef('moon', 'Moon', Difficulty.medium, 'daily', 7, [
  grid([
    '...#####...',
    '.######....',
    '#####......',
    '####.......',
    '####.......',
    '####.......',
    '####.......',
    '#####......',
    '.######....',
    '...#####...',
  ]),
  grid(dx: 1, dy: 1, [
    '...###....',
    '.####.....',
    '.###......',
    '.##.......',
    '.##.......',
    '.##.......',
    '.###......',
    '.####.....',
    '...###....',
  ]),
]);

LayoutDef bell() {
  final z0 = grid([
    '....###....',
    '...#####...',
    '..#######..',
    '..#######..',
    '..#######..',
    '.#########.',
    '.#########.',
    '###########',
    '###########',
    '.....#.....',
  ]);
  // The lip of the bell (bottom two rows) stays one layer deep.
  final z1 = inset(z0).where((c) => c.$2 < 15).toSet();
  final z2 = inset(z1).where((c) => c.$2 == 4 || c.$2 == 10).toSet();
  return LayoutDef('bell', 'Bell', Difficulty.hard, 'daily', 8, [z0, z1, z2]);
}

// ---------------------------------------------------------------------------

final List<LayoutDef> kLayouts = [
  sprout(),
  pyramid(),
  fortress(),
  bridge(),
  crab(),
  dragon(),
  butterfly(),
  cat(),
  spiral(),
  temple(),
  arena(),
  tower(),
  lotus(),
  lantern(),
  fan(),
  bonsai(),
  koi(),
  gate(),
  moon(),
  bell(),
];

/// Chapters for index.json. Turtle (classics #2) is generated elsewhere but is
/// listed here.
const List<Map<String, Object>> kChapters = [
  {
    'id': 'classics',
    'name': 'Classics',
    'order': 1,
    'unlock': {'type': 'always'},
    'layouts': ['pyramid', 'turtle', 'fortress', 'bridge'],
    'requires': [0, 0, 0, 0],
  },
  {
    'id': 'creatures',
    'name': 'Creatures',
    'order': 2,
    'unlock': {'type': 'chapterClears', 'chapter': 'classics', 'count': 3},
    'layouts': ['crab', 'dragon', 'butterfly', 'cat'],
    'requires': [0, 1, 2, 3],
  },
  {
    'id': 'wonders',
    'name': 'Wonders',
    'order': 3,
    'unlock': {'type': 'totalClears', 'count': 8},
    'layouts': ['spiral', 'temple', 'arena', 'tower'],
    'requires': [0, 1, 2, 3],
  },
];

/// The starter board for index.json: what a new player plays first. Kept out
/// of `chapters`, so it never changes chapter counts, unlocks, the star total
/// or the daily pool.
const Map<String, Object> kStarter = {'id': 'warmup', 'name': 'Warm-up', 'layout': 'sprout'};

String indexJson() {
  final chapters = [
    for (final c in kChapters)
      {
        'id': c['id'],
        'name': c['name'],
        'order': c['order'],
        'unlock': c['unlock'],
        'layouts': [
          for (var i = 0; i < (c['layouts']! as List).length; i++)
            {
              'id': (c['layouts']! as List)[i],
              'requiresChapterClears': (c['requires']! as List)[i],
            },
        ],
      },
  ];
  final daily = [
    for (final l in kLayouts)
      if (l.chapter == 'daily') l.id,
  ];
  final data = {'version': 1, 'starter': kStarter, 'chapters': chapters, 'dailyPool': daily};
  return '${const JsonEncoder.withIndent('  ').convert(data)}\n';
}

void main(List<String> args) {
  final root = File.fromUri(Platform.script).parent.parent.parent;
  final dir = Directory('${root.path}/assets/layouts')
    ..createSync(recursive: true);
  for (final l in kLayouts) {
    if (l.id == 'turtle') {
      throw StateError('turtle.json is owned by its own generator');
    }
    File('${dir.path}/${l.id}.json').writeAsStringSync(l.toJson());
    final t = l.tiles;
    final w = t.map((e) => e.$1).reduce((a, b) => a > b ? a : b) + 2;
    final h = t.map((e) => e.$2).reduce((a, b) => a > b ? a : b) + 2;
    stdout.writeln(
      '${l.id.padRight(10)} ${l.tileCount.toString().padLeft(3)} tiles  '
      '${(w / 2).toStringAsFixed(1)} x ${(h / 2).toStringAsFixed(1)} x '
      '${l.layers.length}  ${l.difficulty.name.padRight(6)} '
      'par ${l.parMs ~/ 1000}s  layers ${l.layers.map((e) => e.length).join('+')}',
    );
  }
  File('${dir.path}/index.json').writeAsStringSync(indexJson());
  stdout.writeln('wrote ${kLayouts.length} layouts + index.json');
}
