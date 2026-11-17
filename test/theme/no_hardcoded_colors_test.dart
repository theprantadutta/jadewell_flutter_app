// Every colour in lib/ comes from the theme layer (lib/ui/theme/): no
// `Color(0x…)`, `Colors.…`, `Color.fromARGB` or `Color.fromRGBO` anywhere
// else. Same check as the pre-commit hook (tool/check_colors.dart).
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/check_colors.dart';

void main() {
  test('no literal colours in lib/ outside lib/ui/theme/', () {
    final hits = checkColours(Directory('lib'));
    expect(hits, isEmpty, reason: hits.join('\n'));
  });

  test('the checker catches each literal form and skips the theme', () {
    final dir = Directory.systemTemp.createTempSync('jw_colours');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/ui/screens/a.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync([
        'final a = Color(0xFF112233);',
        'final b = Colors.transparent;',
        'final c = Color.fromARGB(255, 1, 2, 3);',
        'final d = Color.fromRGBO(0, 0, 0, 0.5);',
        'final e = JwColors.light; // Colors. in a comment is fine',
        "final f = 'Color(0x in a string';",
      ].join('\n'));
    File('${dir.path}/ui/theme/t.dart')
      ..createSync(recursive: true)
      ..writeAsStringSync('const white = Color(0xFFFFFFFF);');
    final lines = checkColours(dir).map((h) => '${h.file}:${h.line}').toList();
    expect(lines, ['ui/screens/a.dart:1', 'ui/screens/a.dart:2', 'ui/screens/a.dart:3', 'ui/screens/a.dart:4', 'ui/screens/a.dart:6']);
  });
}
