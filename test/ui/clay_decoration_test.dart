import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_face_spec.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_widget.dart';
import 'package:jadewell_flutter_app/ui/theme/clay.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_theme.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_tokens.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_helpers.dart';

void main() {
  test('CSS blur maps to sigma blur/2 and spread is kept', () {
    final s = ClayLevel.raised.shadows(JwColors.light)[2];
    expect(s.blur, 24);
    expect(s.sigma, 12);
    expect(s.spread, -10);
    expect(s.inset, isFalse);
  });

  test('every level resolves against both themes', () {
    for (final level in ClayLevel.values) {
      expect(level.shadows(JwColors.dark).length, level.shadows(JwColors.light).length);
    }
  });

  testWidgets('tiles in one state share a single cached picture', (tester) async {
    final faces = loadFaces();
    final cache = ClayPictureCache.instance..clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJwThemeData(Brightness.light),
        home: Wrap(
          children: [
            for (final f in faces.take(20)) TileWidget(face: f, reduceMotion: true),
            for (final f in faces.take(20)) TileWidget(face: f, state: TileVisualState.blocked, reduceMotion: true),
          ],
        ),
      ),
    );
    // One picture for playable, one for blocked, plus nothing per tile.
    expect(cache.length, 2);
  });

  test('cache is LRU bounded', () {
    final cache = ClayPictureCache.instance
      ..clear()
      ..maxEntries = 3;
    const d = ClayDecoration(level: ClayLevel.raised, colors: JwColors.light, radius: 12);
    for (var i = 1; i <= 5; i++) {
      cache.obtain(d, Size(10.0 * i, 10));
    }
    expect(cache.length, 3);
    cache.maxEntries = 400;
  });

  test('tile face json has 42 faces', () {
    expect(loadFaces().length, 42);
    expect(TileFaceSpec.loaded!.where((f) => f.isWhiteDragon).length, 1);
  });
}
