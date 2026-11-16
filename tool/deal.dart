// Deals a board and prints it, its solution and the solver's verdict.
//
//   dart run tool/deal.dart --layout turtle --seed 42
//   dart run tool/deal.dart --layout turtle --daily 2026-11-16
//   dart run tool/deal.dart --layout turtle --seed 42 --spread 1   # unbiased dealer
//   dart run tool/deal.dart --fixtures                             # rewrite fixtures/deals/*.json
//   dart run tool/deal.dart --fixtures --check                     # exit 1 if fixtures are stale
//
// Layouts are read from assets/layouts/<id>.json.

import 'dart:convert';
import 'dart:io';

import 'package:jadewell_flutter_app/engine/engine.dart';

Layout loadLayout(String id) {
  final f = File('assets/layouts/$id.json');
  if (!f.existsSync()) {
    stderr.writeln('deal: no layout ${f.path}');
    exit(2);
  }
  return Layout.parse(f.readAsStringSync());
}

/// ASCII rendering of one layer: each half-unit column is 2 characters,
/// each half-unit row one line. A tile at (x, y) prints `[C1]` on line y and
/// `'--'` on line y+1, so half-tile offsets stay visible.
String renderLayer(Layout layout, List<int> faces, int z, {TileSet? remaining}) {
  var maxX = 0, maxY = 0;
  for (final p in layout.positions) {
    if (p.x + 2 > maxX) maxX = p.x + 2;
    if (p.y + 2 > maxY) maxY = p.y + 2;
  }
  final grid = List.generate(maxY, (_) => List.filled(maxX * 2, ' '));
  void put(int row, int col, String s) {
    for (var k = 0; k < s.length; k++) {
      grid[row][col + k] = s[k];
    }
  }

  for (var i = 0; i < layout.length; i++) {
    final p = layout.positions[i];
    if (p.z != z || faces[i] < 0 || (remaining != null && !remaining.contains(i))) continue;
    put(p.y, p.x * 2, '[${kFaces[faces[i]].code}]');
    put(p.y + 1, p.x * 2, "'--'");
  }
  return grid.map((r) => r.join().trimRight()).join('\n');
}

String describePair(Layout layout, List<int> faces, (int, int) pair) {
  final (a, b) = pair;
  final pa = layout.positions[a], pb = layout.positions[b];
  return '(${a.toString().padLeft(3)},${b.toString().padLeft(3)})  '
      '${kFaces[faces[a]].code} ${kFaces[faces[b]].code}  $pa $pb';
}

void printDeal(Layout layout, int seed, DealerOptions options) {
  final sw = Stopwatch()..start();
  final d = deal(layout, seed, options: options);
  final dealUs = sw.elapsedMicroseconds;
  sw.reset();
  final r = solve(layout, d.faces);
  final solveUs = sw.elapsedMicroseconds;
  final e = layout.extent;
  stdout
    ..writeln(
      '${layout.name} (${layout.id} v${layout.version}): ${layout.length} tiles, '
      '${e.width}×${e.height}, ${e.layers} layers',
    )
    ..writeln('seed $seed, generator v$kGeneratorVersion, $options, attempt ${d.attempt}')
    ..writeln();
  for (var z = 0; z < e.layers; z++) {
    stdout
      ..writeln('layer $z')
      ..writeln(renderLayer(layout, d.faces, z))
      ..writeln();
  }
  stdout.writeln('solution (construction order, ${d.solution.length} pairs):');
  for (var k = 0; k < d.solution.length; k++) {
    stdout.writeln('${(k + 1).toString().padLeft(3)}. ${describePair(layout, d.faces, d.solution[k])}');
  }
  stdout
    ..writeln()
    ..writeln('construction order valid: ${isValidSolution(layout, d.faces, d.solution)}')
    ..writeln('forward solver: $r')
    ..writeln(
      'timings: deal ${(dealUs / 1000).toStringAsFixed(2)} ms, solve ${(solveUs / 1000).toStringAsFixed(2)} ms',
    );
  if (r is! SolveSolvable) exitCode = 1;
}

// ---------------------------------------------------------------------------
// Cross-language fixtures (fixtures/deals/*.json), asserted by the Dart tests
// and the C# port.

const List<int> kFixtureSeeds = [
  0, 1, 2, 3, 7, 42, 99, 1000, 4242, 65535, 65536, 123456789, 2147483647, 2147483648, 4294967295, //
  3850022033, 2463534242, 88172645, 314159265, 271828182, 1618033988 & 0xFFFFFFFF, 3735928559, 305419896,
  2882400001, 19780101,
];

Map<String, Object?> dealFixture(Layout layout, int seed, DealerOptions options) {
  final d = deal(layout, seed, options: options);
  return {
    'layoutId': layout.id,
    'layoutVersion': layout.version,
    'generatorVersion': kGeneratorVersion,
    'spreadCandidates': options.spreadCandidates,
    'seed': seed,
    'attempt': d.attempt,
    'faces': d.faces.toList(),
    'solution': [
      for (final (a, b) in d.solution) [a, b],
    ],
  };
}

Map<String, Object?> turtleFixtures() {
  final layout = loadLayout('turtle');
  const opts = DealerOptions.production;
  // Shuffle fixtures: play the first k construction pairs, then shuffle with
  // shuffleSeed(seed, 0) through the same dealer on the sub-board.
  final shuffles = <Map<String, Object?>>[];
  for (final (seed, k) in [(42, 10), (7, 30), (2024, 50), (99, 0), (65535, 70)]) {
    var s = GameState.newGame(layout, seed, verify: false);
    final d = deal(layout, seed, options: opts);
    for (final (a, b) in d.solution.take(k)) {
      s = match(s, a, b).$1;
    }
    final next = applyShuffle(s, ShuffleKind.credit, elapsedMs: 0, verify: false)!.$1;
    shuffles.add({
      'seed': seed,
      'removed': s.removed.toList(),
      'subSeed': shuffleSeed(seed, 0),
      'facesBefore': s.faces.toList(),
      'facesAfter': next.faces.toList(),
    });
  }
  return {
    'description':
        'Deals of assets/layouts/turtle.json by the Dart engine. faces[i] is the face id (tile-faces.json) '
        'of position index i (canonical (z, y, x) order). solution = construction order. See docs/ENGINE.md.',
    'layoutId': layout.id,
    'layoutVersion': layout.version,
    'generatorVersion': kGeneratorVersion,
    'dealerOptions': {
      'spreadCandidates': opts.spreadCandidates,
      'maxDeadEnds': opts.maxDeadEnds,
      'maxAttempts': opts.maxAttempts,
    },
    'positions': [for (final p in layout.positions) p.toJson()],
    'deals': [for (final seed in kFixtureSeeds) dealFixture(layout, seed, opts)],
    'unbiasedDeals': [for (final seed in kFixtureSeeds.take(5)) dealFixture(layout, seed, DealerOptions.unbiased)],
    'shuffles': shuffles,
  };
}

Map<String, Object?> prngFixtures() {
  List<int> outputs(int seed, int count) {
    final rng = Xoshiro128(seed);
    return [for (var i = 0; i < count; i++) rng.nextUint32()];
  }

  const intNs = [1, 2, 3, 6, 10, 72, 143, 144, 1000, 0x7FFFFFFF, 0x80000001, 0xFFFFFFFF, 0x100000000];
  final dates = ['2026-11-16', '2026-12-31', '2027-01-01', '2028-02-29', '2030-06-15'];
  return {
    'description': 'Golden values for the engine PRNG and hashes (docs/ENGINE.md). All values are unsigned 32-bit.',
    'splitmix32': [
      for (final seed in [0, 1, 42, 0xFFFFFFFF])
        {
          'seed': seed,
          'outputs': () {
            final sm = SplitMix32(seed);
            return [for (var i = 0; i < 4; i++) sm.next()];
          }(),
        },
    ],
    'xoshiro128ss': [
      for (final seed in [0, 1, 42, 123456789, 0x80000000, 0xFFFFFFFF]) {'seed': seed, 'outputs': outputs(seed, 16)},
    ],
    'nextInt': [
      for (final seed in [42, 2026])
        {
          'seed': seed,
          'n': intNs,
          'outputs': () {
            final rng = Xoshiro128(seed);
            return [for (final n in intNs) rng.nextInt(n)];
          }(),
        },
    ],
    'fnv1a32': [
      for (final s in ['', 'a', 'foobar', 'turtle', '2026-11-16|turtle|1', 'Jadewell 翡翠'])
        {'input': s, 'hash': fnv1a32(s)},
    ],
    'deriveSeed': [
      for (final (s, i) in [(42, 1), (42, 2), (0, 1), (0xFFFFFFFF, 7)])
        {'seed': s, 'index': i, 'derived': deriveSeed(s, i)},
    ],
    'attemptSeed': [
      for (final (s, a) in [(42, 0), (42, 1), (42, 5), (7, 63)])
        {'seed': s, 'attempt': a, 'attemptSeed': attemptSeed(s, a)},
    ],
    'shuffleSeed': [
      for (final (s, i) in [(42, 0), (42, 1), (42, 2), (7, 0), (0xFFFFFFFF, 3)])
        {'dealSeed': s, 'index': i, 'subSeed': shuffleSeed(s, i)},
    ],
    'dailySeed': [
      for (final date in dates)
        for (final id in ['turtle', 'pyramid'])
          {
            'date': date,
            'layoutId': id,
            'generatorVersion': kGeneratorVersion,
            'key': dailySeedKey(DateTime.parse('${date}T00:00:00Z'), id, kGeneratorVersion),
            'seed': dailySeed(DateTime.parse('${date}T00:00:00Z'), id, kGeneratorVersion),
          },
    ],
  };
}

/// A played turtle game (seed 42) with hints, a mismatch-free path, an undo,
/// a shuffle and its undo, encoded as a move log, plus the replay result.
Map<String, Object?> moveLogFixtures() {
  final layout = loadLayout('turtle');
  const seed = 42;
  var s = GameState.newGame(layout, seed, verify: false);
  var t = 0;
  int tick() => t += 1700;
  s = hint(s).$1;
  final d = deal(layout, seed);
  for (final (a, b) in d.solution.take(5)) {
    s = match(s, a, b, elapsedMs: tick()).$1;
  }
  s = undo(s).$1;
  s = shuffle(s, free: false, rewarded: false, elapsedMs: tick()).$1;
  s = undo(s).$1;
  s = shuffle(s, free: false, rewarded: false, elapsedMs: tick()).$1;
  // Finish with solver moves from the shuffled position.
  final rest = solve(layout, s.faces, remaining: s.remaining) as SolveSolvable;
  for (final (a, b) in rest.solution) {
    s = match(s, a, b, elapsedMs: tick()).$1;
  }
  final log = encodeMoveLog(s.moveLog);
  final r = replay(layout, seed, kGeneratorVersion, log);
  return {
    'description': 'Move logs (docs/ENGINE.md §Move log) and the result replay() must produce.',
    'logs': [
      {
        'layoutId': layout.id,
        'seed': seed,
        'generatorVersion': kGeneratorVersion,
        'parMs': layout.parMs,
        'log': log,
        'bytesHex': encodeMoveLogBytes(s.moveLog).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'legal': r.legal,
        'cleared': r.cleared,
        'finalTimeMs': r.finalTimeMs,
        'stars': r.stars,
        'hintsUsed': r.state!.hintsUsed,
        'shufflesUsed': r.state!.shufflesUsed,
        'undos': r.state!.undos,
      },
    ],
    'example': {
      'entries': ['match(3, 140, 1500ms)', 'hint(credit)', 'shuffle(credit, subSeed 0xDEADBEEF, 2000ms)', 'undo'],
      'bytesHex': encodeMoveLogBytes(const [
        LogMatch(3, 140, 1500),
        LogHint(HintKind.credit),
        LogShuffle(ShuffleKind.credit, 0xDEADBEEF, 2000),
        LogUndo(),
      ]).map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      'log': encodeMoveLog(const [
        LogMatch(3, 140, 1500),
        LogHint(HintKind.credit),
        LogShuffle(ShuffleKind.credit, 0xDEADBEEF, 2000),
        LogUndo(),
      ]),
    },
  };
}

String prettyJson(Object? json) => '${const JsonEncoder.withIndent('  ').convert(json)}\n';

/// Compact JSON for long int arrays: one deal per few lines instead of
/// one number per line.
String fixtureJson(Object? json) {
  final pretty = prettyJson(json);
  // Collapse arrays of plain numbers onto one line.
  return pretty.replaceAllMapped(
    RegExp(r'\[\s*(-?\d+(?:,\s*-?\d+)*)\s*\]'),
    (m) => '[${m.group(1)!.replaceAll(RegExp(r'\s+'), '')}]',
  );
}

void writeFixtures({required bool check}) {
  final files = {
    'fixtures/deals/turtle.json': fixtureJson(turtleFixtures()),
    'fixtures/deals/prng.json': fixtureJson(prngFixtures()),
    'fixtures/deals/move_logs.json': fixtureJson(moveLogFixtures()),
  };
  var stale = false;
  files.forEach((path, content) {
    final f = File(path);
    if (check) {
      if (!f.existsSync() || f.readAsStringSync().replaceAll('\r\n', '\n') != content) {
        stderr.writeln('deal: $path is stale');
        stale = true;
      }
    } else {
      f
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
      stdout.writeln('wrote $path');
    }
  });
  if (stale) exit(1);
}

void main(List<String> args) {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  if (args.contains('--fixtures')) {
    writeFixtures(check: args.contains('--check'));
    return;
  }
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln(
      'usage: dart run tool/deal.dart --layout <id> (--seed <n> | --daily YYYY-MM-DD) [--spread <k>]\n'
      '       dart run tool/deal.dart --fixtures [--check]',
    );
    return;
  }
  final layout = loadLayout(opt('layout') ?? 'turtle');
  final spread = int.tryParse(opt('spread') ?? '') ?? DealerOptions.production.spreadCandidates;
  final daily = opt('daily');
  final int seed;
  if (daily != null) {
    final date = DateTime.parse('${daily}T00:00:00Z');
    seed = dailySeed(date, layout.id, kGeneratorVersion);
    stdout.writeln('daily ${dailySeedKey(date, layout.id, kGeneratorVersion)} → seed $seed');
  } else {
    seed = (int.tryParse(opt('seed') ?? '') ?? 42) & 0xFFFFFFFF;
  }
  printDeal(layout, seed, DealerOptions(spreadCandidates: spread));
}
