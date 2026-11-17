// Fails when a literal colour appears in lib/ outside the theme layer
// (lib/ui/theme/): `Color(0x…)`, `Colors.…`, `Color.fromARGB` or
// `Color.fromRGBO`. Every colour must come from the theme (`context.jw`,
// `JwFill`, `JwBase`, `JwFaceInks`) so the design tokens stay the single
// source of truth.
//
//   dart run tool/check_colors.dart                 # checks lib/
//   dart run tool/check_colors.dart --root <dir>    # checks another tree laid out like lib/
//
// Exits 1 and prints `file:line  text` for every hit. Pure Dart (dart:io
// only) so it runs in the pre-commit hook without Flutter.

import 'dart:io';

/// Paths (relative to the root, forward slashes) where literal colours are
/// allowed: the theme layer and generated code.
const List<String> kAllowedPrefixes = ['ui/theme/', 'ui/l10n/generated/'];

final RegExp kLiteralColour = RegExp(r'\bColor\(\s*0x|(?<![A-Za-z0-9_$])Colors\.|\bColor\.from(ARGB|RGBO)\b');

class ColourHit {
  ColourHit(this.file, this.line, this.text);

  /// Path relative to the checked root, with forward slashes.
  final String file;
  final int line;
  final String text;

  @override
  String toString() => '$file:$line  ${text.trim()}';
}

/// Every literal colour in .dart files under [root] outside [kAllowedPrefixes].
List<ColourHit> checkColours(Directory root) {
  final hits = <ColourHit>[];
  final rootUri = root.absolute.uri;
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final rel = Uri.decodeComponent(file.absolute.uri.path.substring(rootUri.path.length));
    if (kAllowedPrefixes.any(rel.startsWith)) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      final code = _stripComment(lines[i]);
      if (kLiteralColour.hasMatch(code)) hits.add(ColourHit(rel, i + 1, lines[i]));
    }
  }
  return hits;
}

/// The line without a trailing `//` comment (ignores `//` inside quotes).
String _stripComment(String line) {
  String? quote;
  for (var i = 0; i < line.length - 1; i++) {
    final ch = line[i];
    if (quote != null) {
      if (ch == r'\') {
        i++;
      } else if (ch == quote) {
        quote = null;
      }
    } else if (ch == "'" || ch == '"') {
      quote = ch;
    } else if (ch == '/' && line[i + 1] == '/') {
      return line.substring(0, i);
    }
  }
  return line;
}

void main(List<String> args) {
  final i = args.indexOf('--root');
  final root = Directory(i >= 0 && i + 1 < args.length ? args[i + 1] : 'lib');
  final hits = checkColours(root);
  if (hits.isEmpty) {
    stdout.writeln('check_colors: OK (${root.path})');
    return;
  }
  stderr.writeln('check_colors: ${hits.length} literal colour(s) outside lib/ui/theme/ — use theme tokens:');
  for (final h in hits) {
    stderr.writeln('  $h');
  }
  exitCode = 1;
}
