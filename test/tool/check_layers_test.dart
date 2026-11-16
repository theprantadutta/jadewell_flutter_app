// Proves tool/check_layers.dart works: clean on lib/, and reports exactly the
// deliberate violations in tool/layer_fixtures/. Pure Dart (runs under
// `dart test` and `flutter test`).
import 'dart:io';

import 'package:test/test.dart';

import '../../tool/check_layers.dart';

void main() {
  test('lib/ has no layering violations', () {
    final violations = checkLayers(Directory('lib'));
    expect(violations, isEmpty, reason: violations.join('\n'));
  });

  test('fixtures report exactly the deliberate violations', () {
    final got = checkLayers(Directory('tool/layer_fixtures'))
        .map((v) => '${v.file}:${v.line} ${v.rule}')
        .toList();
    expect(got, [
      'data/imports_state.dart:2 layer',
      'data/imports_ui.dart:2 no-ui-import',
      'engine/uses_flutter.dart:2 engine-pure',
      'engine/uses_random.dart:2 engine-pure',
      'engine/uses_random.dart:5 engine-prng',
      'state/imports_impl.dart:3 platform-interface',
      'ui/widget.dart:3 no-root-import',
    ]);
  });
}
