// Every bundled layout + index.json passes tool/validate_layouts.dart (fewer
// seeds here; the agreement tests already cover 5,000 per layout).
import 'dart:io';

import 'package:test/test.dart';

import '../tool/validate_layouts.dart';

void main() {
  test('all layouts and the catalogue are valid', () {
    final result = validateLayouts(Directory('assets/layouts'), seeds: 25);
    final problems = [
      for (final r in result.layouts) ...r.problems.map((p) => '${r.id}: $p'),
      ...result.catalogue,
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
    expect(result.layouts.length, greaterThanOrEqualTo(20));
  });
}
