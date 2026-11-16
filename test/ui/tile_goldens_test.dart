import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/screens/dev_gallery/gallery_sheets.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_helpers.dart';

void main() {
  setUpAll(loadJwFonts);
  final faces = loadFaces();

  for (final b in Brightness.values) {
    testWidgets('tile faces sheet ${b.name}', (tester) async {
      await expectGolden(
        tester,
        goldenFrame(brightness: b, width: 760, child: GalleryTileFacesSheet(faces: faces, bigScale: 2.5)),
        'goldens/tile_faces_${b.name}.png',
        surface: const Size(760, 1900),
      );
    });

    testWidgets('tile states sheet ${b.name}', (tester) async {
      await expectGolden(
        tester,
        goldenFrame(brightness: b, width: 760, child: GalleryTileStatesSheet(faces: faces, scale: 1.5, faceIds: const [0, 4, 8, 9, 15, 17, 22, 27, 31, 32, 33, 35, 39])),
        'goldens/tile_states_${b.name}.png',
        surface: const Size(760, 1100),
      );
    });

    testWidgets('tile states greyscale ${b.name}', (tester) async {
      await expectGolden(
        tester,
        goldenFrame(
          brightness: b,
          width: 760,
          greyscale: true,
          child: GalleryTileStatesSheet(faces: faces, scale: 1.5, faceIds: const [0, 4, 8, 9, 15, 17, 22, 27, 31, 32, 33, 35, 39]),
        ),
        'goldens/tile_states_greyscale_${b.name}.png',
        surface: const Size(760, 1100),
      );
    });
  }
}
