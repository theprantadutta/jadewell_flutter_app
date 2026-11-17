import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/screens/dev_gallery/gallery_sheets.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_helpers.dart';

void main() {
  setUpAll(loadJwFonts);

  for (final b in Brightness.values) {
    testWidgets('components sheet ${b.name}', (tester) async {
      await expectGolden(
        tester,
        goldenFrame(brightness: b, child: const GalleryComponentsSheet()),
        'goldens/components_${b.name}.png',
        surface: const Size(420, 3800),
      );
    });
  }
}
