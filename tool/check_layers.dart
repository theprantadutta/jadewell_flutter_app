// Enforces the lib/ layering rules from docs/ARCHITECTURE.md §1.
//
//   dart run tool/check_layers.dart                 # checks lib/
//   dart run tool/check_layers.dart --root <dir>    # checks another tree laid out like lib/
//
// Exits 1 and prints `file:line  [rule] message` for every violation.
// Pure Dart (dart:io only) so it runs in the pre-commit hook without Flutter.

import 'dart:io';

const String kPackageName = 'jadewell_flutter_app';

/// dart: libraries the engine may use. dart:math is allowed for maths
/// (min, max, sqrt), but `Random` is banned separately: deals must come from
/// the engine's own seeded PRNG.
const Set<String> kEngineDartLibs = {
  'dart:core',
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:math',
  'dart:typed_data',
};

/// Root files that compose the app and may import anything.
const Set<String> kCompositionRoots = {'main.dart', 'app.dart'};

class Violation {
  Violation(this.file, this.line, this.rule, this.message);

  /// Path relative to the checked root, with forward slashes.
  final String file;
  final int line;
  final String rule;
  final String message;

  @override
  String toString() => '$file:$line  [$rule] $message';
}

final RegExp _directive = RegExp(r'''^\s*(import|export)\s+['"]([^'"]+)['"]''');
final RegExp _random = RegExp(r'\bRandom\s*[\.(]');

/// Top-level layer of a path relative to the root (`engine/x.dart` → `engine`),
/// or null for files directly in the root.
String? layerOf(String relPath) {
  final parts = relPath.split('/');
  return parts.length > 1 ? parts.first : null;
}

bool _isPlatformImpl(String relPath) =>
    layerOf(relPath) == 'platform' && relPath.endsWith('_impl.dart');

/// Checks every .dart file under [root] (laid out like lib/).
List<Violation> checkLayers(Directory root, {String packageName = kPackageName}) {
  final violations = <Violation>[];
  final rootPath = root.absolute.uri;

  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final rel = _relative(rootPath, file.absolute.uri);
    final fromLayer = layerOf(rel);
    final lines = file.readAsLinesSync();

    for (var i = 0; i < lines.length; i++) {
      final lineNo = i + 1;
      final text = lines[i];

      if (fromLayer == 'engine' && _random.hasMatch(text) && !text.trimLeft().startsWith('//')) {
        violations.add(Violation(rel, lineNo, 'engine-prng',
            'engine must use its own seeded PRNG, not dart:math Random'));
      }

      final m = _directive.firstMatch(text);
      if (m == null) continue;
      final uri = m.group(2)!;
      final v = _checkImport(rel, fromLayer, uri, rootPath, packageName);
      if (v != null) violations.add(Violation(rel, lineNo, v.$1, v.$2));
    }
  }
  return violations;
}

/// Returns (rule, message) when [uri] imported from [fromRel] breaks a rule.
(String, String)? _checkImport(
    String fromRel, String? fromLayer, String uri, Uri rootPath, String packageName) {
  // dart: libraries
  if (uri.startsWith('dart:')) {
    if (fromLayer == 'engine' && !kEngineDartLibs.contains(uri)) {
      return ('engine-pure', 'engine may not import $uri');
    }
    return null;
  }

  // Resolve to a path inside the root, or treat as an external package.
  String? targetRel;
  if (uri.startsWith('package:$packageName/')) {
    targetRel = uri.substring('package:$packageName/'.length);
  } else if (uri.startsWith('package:')) {
    if (fromLayer == 'engine') {
      return ('engine-pure', 'engine may not import packages ($uri)');
    }
    return null; // external packages are fine elsewhere
  } else {
    final resolved = rootPath.resolve(fromRel).resolve(uri);
    targetRel = _relative(rootPath, resolved);
    if (targetRel.startsWith('../')) {
      return ('outside-lib', 'import escapes lib/ ($uri)');
    }
  }

  final toLayer = layerOf(targetRel);

  // Composition roots may import anything.
  if (fromLayer == null && kCompositionRoots.contains(fromRel)) return null;

  // Nothing imports the composition roots.
  if (toLayer == null) {
    return ('no-root-import', '$fromRel may not import root file $targetRel');
  }

  // Platform implementations are only reachable from main.dart / app.dart and platform itself.
  if (_isPlatformImpl(targetRel) && fromLayer != 'platform') {
    return ('platform-interface', '${fromLayer ?? fromRel} must use the platform interface, not $targetRel');
  }

  const allowed = <String, Set<String>>{
    'engine': {'engine'},
    'data': {'engine', 'data'},
    'platform': {'engine', 'data', 'platform'},
    'state': {'engine', 'data', 'platform', 'state'},
    'ui': {'engine', 'data', 'platform', 'state', 'ui'},
  };

  final from = fromLayer ?? '<root>';
  final ok = allowed[from];
  if (ok == null) {
    return ('unknown-layer', 'file is not inside a known layer (${allowed.keys.join(', ')})');
  }
  if (!ok.contains(toLayer)) {
    if (toLayer == 'ui') return ('no-ui-import', '$from may not import ui ($targetRel)');
    return ('layer', '$from may not import $toLayer ($targetRel)');
  }
  return null;
}

String _relative(Uri root, Uri target) {
  final r = root.toString().endsWith('/') ? root.toString() : '${root.toString()}/';
  final t = target.normalizePath().toString();
  if (t.startsWith(r)) return Uri.decodeComponent(t.substring(r.length));
  // Outside the root: express with ../ for reporting.
  final rootSegs = Uri.parse(r).pathSegments.where((s) => s.isNotEmpty).toList();
  final tSegs = target.normalizePath().pathSegments;
  var i = 0;
  while (i < rootSegs.length && i < tSegs.length && rootSegs[i].toLowerCase() == tSegs[i].toLowerCase()) {
    i++;
  }
  return [...List.filled(rootSegs.length - i, '..'), ...tSegs.skip(i)].join('/');
}

void main(List<String> args) {
  var rootArg = 'lib';
  final idx = args.indexOf('--root');
  if (idx != -1 && idx + 1 < args.length) rootArg = args[idx + 1];

  final root = Directory(rootArg);
  if (!root.existsSync()) {
    stderr.writeln('check_layers: $rootArg not found');
    exit(2);
  }
  final violations = checkLayers(root);
  if (violations.isEmpty) {
    stdout.writeln('check_layers: OK ($rootArg)');
    return;
  }
  for (final v in violations) {
    stderr.writeln(v);
  }
  stderr.writeln('check_layers: ${violations.length} violation(s)');
  exit(1);
}
