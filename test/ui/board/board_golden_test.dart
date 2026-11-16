import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:jadewell_flutter_app/ui/board/board_view.dart';
import 'package:material_ui/material_ui.dart';

import '../golden_helpers.dart';

/// Readability proof (brief §7, DESIGN_SYSTEM §9): the full 144-tile turtle
/// in both themes and in greyscale. Playable vs blocked must stay obvious.
void main() {
  setUpAll(loadJwFonts);
  final faces = loadFaces();
  final layout = Layout.parse(File('assets/layouts/turtle.json').readAsStringSync());
  final game = GameState.newGame(layout, 42);

  Widget board(Brightness b, {bool greyscale = false}) => goldenFrame(
    brightness: b,
    width: 390,
    greyscale: greyscale,
    child: SizedBox(
      height: 640,
      child: BoardView(game: game, faces: faces, animateEntry: false, reduceMotion: true),
    ),
  );

  for (final b in Brightness.values) {
    testWidgets('full turtle board ${b.name}', (tester) async {
      await expectGolden(tester, board(b), 'goldens/board_turtle_${b.name}.png', surface: const Size(390, 700));
    });

    testWidgets('full turtle board greyscale ${b.name}', (tester) async {
      await expectGolden(
        tester,
        board(b, greyscale: true),
        'goldens/board_turtle_greyscale_${b.name}.png',
        surface: const Size(390, 700),
      );
    });
  }
}
