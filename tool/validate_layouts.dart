// Validates every bundled layout and the catalogue (brief §6). Exits 1 on any problem.
//
//   dart run tool/validate_layouts.dart              # 500 seeds per layout
//   dart run tool/validate_layouts.dart --seeds 50
//
// Checks: layout geometry (engine validation), no overhang warnings, required
// metadata, index.json consistency (every listed id has a file, every file is
// listed exactly once, chapter/order agree), and that the dealer + independent
// solver agree on N seeds per layout in production dealer mode.

import 'dart:convert';
import 'dart:io';

import '../lib/engine/engine.dart';

class LayoutReport {
  LayoutReport(this.id);
  final String id;
  final List<String> problems = [];
  int seeds = 0;
  int maxNodes = 0;
  int tiles = 0;
}

/// Returns all problems found (empty = valid). [seeds] per layout.
({List<LayoutReport> layouts, List<String> catalogue}) validateLayouts(Directory dir, {int seeds = 500}) {
  final reports = <LayoutReport>[];
  final catalogue = <String>[];
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json') && !f.path.endsWith('index.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  final meta = <String, LayoutData>{};
  for (final f in files) {
    final fileId = f.uri.pathSegments.last.replaceAll('.json', '');
    final report = LayoutReport(fileId);
    reports.add(report);
    LayoutData data;
    try {
      data = LayoutData.parse(f.readAsStringSync());
    } on Object catch (e) {
      report.problems.add('parse error: $e');
      continue;
    }
    meta[data.id] = data;
    report.tiles = data.tiles.length;
    if (data.id != fileId) report.problems.add('id "${data.id}" does not match file name');
    if (data.parMs == null || data.parMs! <= 0) report.problems.add('missing parMs');
    if (data.difficulty == null) report.problems.add('missing difficulty');
    if (data.chapter == null || data.order == null) report.problems.add('missing chapter/order');
    if (data.tiles.length < 72 || data.tiles.length > 144) report.problems.add('tile count ${data.tiles.length} outside 72–144');
    final errors = data.validate();
    report.problems.addAll(errors);
    if (errors.isNotEmpty) continue;

    final layout = data.build();
    report.problems.addAll(layout.warnings().map((w) => 'warning: $w'));
    for (var seed = 1; seed <= seeds; seed++) {
      final Deal d;
      try {
        d = deal(layout, seed);
      } on Object catch (e) {
        report.problems.add('seed $seed: dealer failed: $e');
        break;
      }
      final r = solve(layout, d.faces);
      if (r.nodes > report.maxNodes) report.maxNodes = r.nodes;
      if (r is! SolveSolvable) {
        report.problems.add('seed $seed: solver says $r for a constructed deal');
        break;
      }
      report.seeds++;
    }
  }

  // Catalogue.
  final indexFile = File('${dir.path}/index.json');
  if (!indexFile.existsSync()) {
    catalogue.add('index.json missing');
    return (layouts: reports, catalogue: catalogue);
  }
  final index = jsonDecode(indexFile.readAsStringSync()) as Map<String, dynamic>;
  final listed = <String>[];
  for (final ch in (index['chapters'] as List).cast<Map<String, dynamic>>()) {
    final chapterId = ch['id'] as String;
    final layouts = (ch['layouts'] as List).cast<Map<String, dynamic>>();
    for (var i = 0; i < layouts.length; i++) {
      final id = layouts[i]['id'] as String;
      listed.add(id);
      final m = meta[id];
      if (m == null) {
        catalogue.add('chapter $chapterId lists "$id" but there is no $id.json');
      } else {
        if (m.chapter != chapterId) catalogue.add('"$id" is in chapter $chapterId but its file says ${m.chapter}');
        if (m.order != i + 1) catalogue.add('"$id" is #${i + 1} in $chapterId but its file says order ${m.order}');
      }
    }
  }
  for (final id in (index['dailyPool'] as List).cast<String>()) {
    listed.add(id);
    if (!meta.containsKey(id)) catalogue.add('dailyPool lists "$id" but there is no $id.json');
  }
  for (final id in meta.keys) {
    final n = listed.where((x) => x == id).length;
    if (n == 0) catalogue.add('"$id".json is not listed in index.json');
    if (n > 1) catalogue.add('"$id" is listed $n times in index.json');
  }
  return (layouts: reports, catalogue: catalogue);
}

void main(List<String> args) {
  var seeds = 500;
  final i = args.indexOf('--seeds');
  if (i != -1 && i + 1 < args.length) seeds = int.parse(args[i + 1]);

  final sw = Stopwatch()..start();
  final result = validateLayouts(Directory('assets/layouts'), seeds: seeds);
  var failed = false;
  for (final r in result.layouts) {
    final status = r.problems.isEmpty ? 'ok  ' : 'FAIL';
    stdout.writeln('$status ${r.id.padRight(10)} ${r.tiles.toString().padLeft(3)} tiles  '
        '${r.seeds}/$seeds seeds  max ${r.maxNodes} nodes');
    for (final p in r.problems) {
      stdout.writeln('       - $p');
    }
    if (r.problems.isNotEmpty) failed = true;
  }
  for (final p in result.catalogue) {
    stdout.writeln('FAIL index.json: $p');
    failed = true;
  }
  stdout.writeln('${result.layouts.length} layouts, ${sw.elapsed.inSeconds}s');
  if (failed) exit(1);
}
