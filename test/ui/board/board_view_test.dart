import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:jadewell_flutter_app/ui/board/board_geometry.dart';
import 'package:jadewell_flutter_app/ui/board/board_tile.dart';
import 'package:jadewell_flutter_app/ui/board/board_view.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_face_spec.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_widget.dart';
import 'package:jadewell_flutter_app/ui/board/tile_motion.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_theme.dart';
import 'package:material_ui/material_ui.dart';

import '../golden_helpers.dart';

final turtle = Layout.parse(File('assets/layouts/turtle.json').readAsStringSync());

/// Plays the engine against a [BoardView] like the controller does: state
/// first, then the events, synchronously.
class _Harness extends StatefulWidget {
  const _Harness({required this.initial, required this.faces, this.animateEntry = false, this.reduceMotion = false});

  final GameState initial;
  final List<TileFaceSpec> faces;
  final bool animateEntry;
  final bool reduceMotion;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late GameState game = widget.initial;
  final events = StreamController<GameEvent>.broadcast(sync: true);
  final taps = <int>[];

  void tap(int i) {
    taps.add(i);
    final (next, ev) = select(game, i);
    setState(() => game = next);
    ev.forEach(events.add);
  }

  @override
  void dispose() {
    unawaited(events.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BoardView(
    game: game,
    faces: widget.faces,
    events: events.stream,
    onTileTap: tap,
    animateEntry: widget.animateEntry,
    reduceMotion: widget.reduceMotion,
  );
}

Widget _app(Widget child, {Size size = const Size(390, 640)}) => MaterialApp(
  theme: buildJwThemeData(Brightness.light),
  home: Align(alignment: Alignment.topLeft, child: SizedBox.fromSize(size: size, child: child)),
);

void main() {
  final faces = loadFaces();

  group('BoardFit (DESIGN_SYSTEM §4)', () {
    final geo = BoardGeometry(turtle);

    test('content box is cols × 32 + edge by rows × 39 + layers × 6 + edge', () {
      expect(geo.size, const Size(8 * 32 + 4, 15 * 39 + 4 * 6 + 4));
    });

    test('a roomy area caps at 1.25×; the face size multiplies the re-fitted unit', () {
      const area = Size(1200, 2000);
      expect(BoardFit.compute(area, geo.size).scale, 1.25);
      expect(BoardFit.compute(area, geo.size, faceSize: TileFaceSize.large).scale, closeTo(1.25 * 1.12, 1e-9));
      expect(BoardFit.compute(area, geo.size, faceSize: TileFaceSize.small).scale, closeTo(1.25 * 0.9, 1e-9));
    });

    test('fits exactly between the bounds, with 12 pt padding', () {
      final area = Size(geo.size.width * 1.1 + 24, geo.size.height * 1.1 + 24);
      final fit = BoardFit.compute(area, geo.size);
      expect(fit.scale, closeTo(fit.fitScale, 1e-9));
      expect(fit.scale, closeTo(1.1, 1e-9));
      expect(fit.zoomable, isFalse);
    });

    test('never below 0.8×: pinch-zoom instead', () {
      final fit = BoardFit.compute(const Size(200, 300), geo.size);
      expect(fit.scale, 0.8);
      expect(fit.zoomable, isTrue);
      expect(fit.fitScale, lessThan(0.8));
    });
  });

  testWidgets('BoardView scales the board to fit and centres it', (tester) async {
    final game = GameState.newGame(turtle, 42);
    final geo = BoardGeometry(turtle);
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(BoardView(game: game, faces: faces, animateEntry: false), size: const Size(1000, 1400)),
    );
    final box = tester.getSize(find.byType(FittedBox));
    expect(box.width, closeTo(geo.size.width * 1.25, 0.01));
    expect(box.height, closeTo(geo.size.height * 1.25, 0.01));
    final center = tester.getCenter(find.byType(FittedBox));
    expect(center.dx, closeTo(500, 0.5));
    expect(center.dy, closeTo(700, 0.5));
    expect(tester.widgetList(find.byType(BoardTile)), hasLength(144));
  });

  testWidgets('tapping a blocked tile outlines its blockers for 780 ms', (tester) async {
    final game = GameState.newGame(turtle, 42);
    // An uncovered ground tile blocked by both side neighbours.
    final target = List.generate(turtle.length, (i) => i).firstWhere(
      (i) =>
          turtle.positions[i].z == 0 &&
          turtle.coveredBy(i).isEmpty &&
          turtle.leftOf(i).isNotEmpty &&
          turtle.rightOf(i).isNotEmpty,
    );
    expect(game.isFree(target), isFalse);
    final blockers = turtle.blockersOf(target, game.remaining);
    expect(blockers, isNotEmpty);

    await tester.pumpWidget(_app(_Harness(initial: game, faces: faces)));
    final tiles = tester.widgetList<BoardTile>(find.byType(BoardTile)).toList();
    await tester.tap(find.byWidget(tiles[target]));
    await tester.pump();

    final state = tester.state<_HarnessState>(find.byType(_Harness));
    expect(state.taps, [target]);
    List<BoardTile> current() => tester.widgetList<BoardTile>(find.byType(BoardTile)).toList();
    for (var i = 0; i < turtle.length; i++) {
      expect(current()[i].outlined, blockers.contains(i), reason: 'tile $i');
    }
    expect(current()[target].visual, TileVisualState.blocked);

    await tester.pump(const Duration(milliseconds: 700));
    expect(current().where((t) => t.outlined), hasLength(blockers.length));
    await tester.pump(const Duration(milliseconds: 100));
    expect(current().where((t) => t.outlined), isEmpty);
  });

  testWidgets('matched tiles stop being hit-testable at once and leave after the exit', (tester) async {
    final game = GameState.newGame(turtle, 42);
    final (a, b) = game.availableMoves.first;
    await tester.pumpWidget(_app(_Harness(initial: game, faces: faces)));
    final state = tester.state<_HarnessState>(find.byType(_Harness));
    state.tap(a);
    await tester.pump();
    expect(tester.widgetList<BoardTile>(find.byType(BoardTile)).elementAt(a).visual, TileVisualState.selected);
    state.tap(b);
    await tester.pump();
    final exiting = tester.widgetList<BoardTile>(find.byType(BoardTile)).where((t) => t.exiting).toList();
    expect(exiting, hasLength(2));
    expect(find.byType(BoardTile), findsNWidgets(144));
    await tester.pump(MatchExit.out + const Duration(milliseconds: 50));
    expect(find.byType(BoardTile), findsNWidgets(142));
  });

  testWidgets('input is blocked only for the first 60 % of the board entry', (tester) async {
    final game = GameState.newGame(turtle, 42);
    await tester.pumpWidget(_app(_Harness(initial: game, faces: faces, animateEntry: true)));
    final board = tester.state<BoardViewState>(find.byType(BoardView));
    expect(board.inputLocked, isTrue);
    var total = Duration.zero;
    for (var i = 0; i < turtle.length; i++) {
      final p = turtle.positions[i];
      final end = EntryDrop.delayFor(layer: p.z, col: p.x / 2, row: p.y / 2, index: i) + EntryDrop.length;
      if (end > total) total = end;
    }
    expect(total.inMilliseconds, inInclusiveRange(1800, 2000), reason: '144 tiles finish in ≈ 1.9 s');
    await tester.pump(total * 0.6 - const Duration(milliseconds: 20));
    expect(board.inputLocked, isTrue);
    await tester.pump(const Duration(milliseconds: 40));
    expect(board.inputLocked, isFalse);
    await tester.pumpAndSettle();
  });

  test('entry delay formula (MOTION_SPEC §3)', () {
    expect(EntryDrop.delayFor(layer: 2, col: 3, row: 4, index: 7), Duration(milliseconds: 2 * 250 + 7 * 9 + (7 * 53 % 5) * 8));
  });
}
