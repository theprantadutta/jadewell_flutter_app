import 'dart:io';

import 'package:jadewell_flutter_app/engine/engine.dart';
import 'package:test/test.dart';

import '../tool/gen_turtle.dart' as gen;
import 'helpers.dart';

void main() {
  group('tiles', () {
    test('42 faces, ids and names match tile-faces.json', () {
      expect(kFaces, hasLength(42));
      expect(kFaces[0].name, '1 of Circles');
      expect(kFaces[17].name, '9 of Bamboo');
      expect(kFaces[18].name, '1 of Characters');
      expect(kFaces[27].name, 'East Wind');
      expect(kFaces[33].name, 'White Dragon');
      expect(kFaces[34].name, 'Plum Flower');
      expect(kFaces[41].name, 'Winter Season');
      for (var i = 0; i < 42; i++) {
        expect(kFaces[i].id, i);
      }
      expect({for (final f in kFaces) f.code}, hasLength(42));
    });

    test('match keys: 34 regular, all flowers FL, all seasons SE', () {
      expect({for (final f in kFaces) f.matchKey}, hasLength(kMatchKeyCount));
      for (var i = 0; i < 34; i++) {
        expect(kFaces[i].matchKeyName, 'f$i');
      }
      for (var i = 34; i < 38; i++) {
        expect(kFaces[i].matchKeyName, 'FL');
      }
      for (var i = 38; i < 42; i++) {
        expect(kFaces[i].matchKeyName, 'SE');
      }
      expect(facesMatch(34, 37), isTrue);
      expect(facesMatch(38, 41), isTrue);
      expect(facesMatch(37, 38), isFalse);
      expect(facesMatch(5, 5), isTrue);
      expect(facesMatch(5, 6), isFalse);
      for (final f in kFaces) {
        expect(matchKeyOf(f.id), f.matchKey);
      }
    });

    test('144-tile multiset and 72 canonical pairs', () {
      final set = fullTileSet();
      expect(set, hasLength(144));
      for (var f = 0; f < 34; f++) {
        expect(set.where((x) => x == f), hasLength(4));
      }
      for (var f = 34; f < 42; f++) {
        expect(set.where((x) => x == f), hasLength(1));
      }
      expect(kCanonicalPairs, hasLength(72));
      expect(kCanonicalPairs.first, (0, 0));
      expect(kCanonicalPairs.sublist(68), [(34, 35), (36, 37), (38, 39), (40, 41)]);
      for (final (a, b) in kCanonicalPairs) {
        expect(facesMatch(a, b), isTrue);
      }
    });

    test('facePairs rejects multisets that do not pair up', () {
      expect(() => facePairs([1, 1, 2]), throwsArgumentError);
      expect(() => facePairs([1, 2]), throwsArgumentError);
      expect(() => facePairs([34, 38]), throwsArgumentError);
      expect(facePairs([38, 2, 41, 2]), [(2, 2), (38, 41)]);
    });
  });

  group('validation', () {
    test('valid tiny layout', () {
      expect(Layout.validate(const [Position(0, 0, 0), Position(2, 0, 0)]), isEmpty);
    });

    test('odd count', () {
      expect(
        Layout.validate(const [Position(0, 0, 0), Position(2, 0, 0), Position(4, 0, 0)]),
        contains(contains('even')),
      );
    });

    test('too few / too many', () {
      expect(Layout.validate(const []), contains(contains('at least 2')));
      final many = [for (var i = 0; i < 146; i++) Position(2 * (i % 20), 2 * (i ~/ 20), 0)];
      expect(Layout.validate(many), contains(contains('at most 144')));
    });

    test('overlap on the same layer, including half offsets and duplicates', () {
      expect(Layout.validate(const [Position(0, 0, 0), Position(1, 1, 0)]), contains(contains('overlap')));
      expect(Layout.validate(const [Position(0, 0, 0), Position(0, 0, 0)]), contains(contains('overlap')));
      expect(Layout.validate(const [Position(0, 0, 0), Position(2, 1, 0)]), isEmpty);
    });

    test('unsupported tile above nothing', () {
      final errors = Layout.validate(const [Position(0, 0, 0), Position(4, 0, 1)]);
      expect(errors, contains(contains('unsupported')));
    });

    test('partial support is enough', () {
      expect(Layout.validate(const [Position(0, 0, 0), Position(1, 1, 1)]), isEmpty);
    });

    test('negative coordinates', () {
      expect(Layout.validate(const [Position(-1, 0, 0), Position(2, 0, 0)]), contains(contains('negative')));
    });

    test('JSON structure errors', () {
      expect(() => Layout.parse('[]'), throwsA(isA<LayoutException>()));
      expect(() => Layout.parse('{"id":"x","name":"x","tiles":[{"x":0}]}'), throwsA(isA<LayoutException>()));
      expect(
        () => Layout.parse('{"id":"x","name":"x","tiles":[{"x":0,"y":0,"z":0}]}'),
        throwsA(isA<LayoutException>().having((e) => e.errors.join(), 'errors', contains('even'))),
      );
    });

    test('extra keys are ignored, metadata parsed', () {
      final l = Layout.parse(
        '{"id":"x","name":"X","version":3,"difficulty":"easy","chapter":"c","order":4,'
        '"parMs":1000,"author":"someone","tiles":[{"x":2,"y":0,"z":0,"tag":1},{"x":0,"y":0,"z":0}]}',
      );
      expect(l.id, 'x');
      expect(l.version, 3);
      expect(l.difficulty, 'easy');
      expect(l.chapter, 'c');
      expect(l.order, 4);
      expect(l.parMs, 1000);
    });
  });

  group('canonical order', () {
    test('sorted by z, then y, then x', () {
      final l = tinyLayout([(4, 0, 0), (0, 2, 0), (1, 1, 1), (0, 0, 0), (2, 0, 0), (2, 2, 0)]);
      expect(l.positions, const [
        Position(0, 0, 0),
        Position(2, 0, 0),
        Position(4, 0, 0),
        Position(0, 2, 0),
        Position(2, 2, 0),
        Position(1, 1, 1),
      ]);
    });
  });

  group('free rule', () {
    test('a lone tile is free', () {
      final l = tinyLayout([(0, 0, 0), (6, 0, 0)]);
      expect(l.freeTiles(l.all), [0, 1]);
    });

    test('row of three: middle is side-blocked, ends free', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (4, 0, 0), (8, 0, 0)]);
      expect(l.isFree(0, l.all), isTrue);
      expect(l.isFree(1, l.all), isFalse);
      expect(l.isFree(2, l.all), isTrue);
      expect(l.blockersOf(1, l.all), [0, 2]);
      // Removing one end frees the middle.
      expect(l.isFree(1, l.all.remove(0)), isTrue);
      expect(l.isFree(1, l.all.remove(2)), isTrue);
    });

    test('half-row offset neighbours still touch the side (|dy| < 2)', () {
      // A at (2,2); left neighbour half a row up, right neighbour half a row down.
      final l = tinyLayout([(0, 1, 0), (2, 2, 0), (4, 3, 0), (8, 8, 0)]);
      final a = idx(l, 2, 2, 0);
      expect(l.leftOf(a), [idx(l, 0, 1, 0)]);
      expect(l.rightOf(a), [idx(l, 4, 3, 0)]);
      expect(l.isFree(a, l.all), isFalse);
    });

    test('a full row offset (|dy| == 2) does not touch', () {
      final l = tinyLayout([(0, 0, 0), (2, 2, 0), (4, 4, 0), (8, 8, 0)]);
      expect(l.isFree(idx(l, 2, 2, 0), l.all), isTrue);
    });

    test('a half-tile gap (|dx| == 3) does not touch', () {
      final l = tinyLayout([(0, 0, 0), (3, 0, 0), (6, 0, 0), (10, 0, 0)]);
      expect(l.isFree(idx(l, 3, 0, 0), l.all), isTrue);
    });

    test('two neighbours on one side only: still free', () {
      final l = tinyLayout([(0, 0, 0), (0, 2, 0), (2, 1, 0), (8, 8, 0)]);
      final a = idx(l, 2, 1, 0);
      expect(l.leftOf(a), hasLength(2));
      expect(l.isFree(a, l.all), isTrue);
    });

    test('partial cover by a half-offset tile blocks', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (1, 1, 1), (8, 8, 0)]);
      final top = idx(l, 1, 1, 1);
      expect(l.coveredBy(0), [top]);
      expect(l.coveredBy(1), [top]);
      expect(l.covers(top), [0, 1]);
      expect(l.isFree(0, l.all), isFalse);
      expect(l.isFree(1, l.all), isFalse);
      expect(l.blockersOf(0, l.all), [top]);
      expect(l.isFree(0, l.all.remove(top)), isTrue);
    });

    test('a cap centred over four tiles covers all four', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (0, 2, 0), (2, 2, 0), (1, 1, 1), (8, 8, 0)]);
      final cap = idx(l, 1, 1, 1);
      for (final p in [(0, 0), (2, 0), (0, 2), (2, 2)]) {
        expect(l.coveredBy(idx(l, p.$1, p.$2, 0)), [cap]);
      }
    });

    test('a tile on the layer above that only touches the edge does not cover', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (2, 0, 1), (8, 8, 0)]);
      expect(l.isFree(idx(l, 0, 0, 0), l.all), isTrue);
      expect(l.isFree(idx(l, 2, 0, 0), l.all), isFalse);
    });

    test('side neighbours on another layer do not side-block', () {
      // A (2,0,0) has a z=0 neighbour on its left and only a z=1 tile at dx = +2 on its right.
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (5, 0, 0), (4, 0, 1)]);
      final a = idx(l, 2, 0, 0);
      expect(l.rightOf(a), isEmpty);
      expect(l.coveredBy(a), isEmpty);
      expect(l.isFree(a, l.all), isTrue);
    });

    test('covered and side-blocked: blockers include both', () {
      final l = tinyLayout([(0, 0, 0), (2, 0, 0), (4, 0, 0), (2, 0, 1)]);
      expect(l.blockersOf(1, l.all), [0, 2, 3]);
      expect(l.blockersOf(1, l.all.remove(0)), [3]);
    });

    test('overhang warning (z+2 over a tile nothing on z+1 covers)', () {
      final l = tinyLayout([(0, 0, 0), (3, 0, 0), (2, 0, 1), (1, 0, 2)]);
      expect(l.warnings(), isNotEmpty);
    });
  });

  group('turtle', () {
    final turtle = loadLayout('turtle');

    test('144 tiles, 8 wide, 15 tall, 5 layers', () {
      expect(turtle.length, 144);
      final e = turtle.extent;
      expect((e.width, e.height, e.layers), (8, 15, 5));
      expect(turtle.parMs, 360000);
      expect(turtle.chapter, 'classics');
      expect(turtle.order, 2);
      expect(turtle.difficulty, 'medium');
    });

    test('layer sizes 87 / 36 / 16 / 4 / 1', () {
      final counts = List.filled(5, 0);
      for (final p in turtle.positions) {
        counts[p.z]++;
      }
      expect(counts, [87, 36, 16, 4, 1]);
    });

    test('brief examples, end tiles and cap at odd half-units', () {
      expect(turtle.positions, contains(const Position(0, 2, 0)));
      expect(turtle.positions.last, const Position(7, 13, 4));
      expect(turtle.positions, containsAll(const [Position(7, 0, 0), Position(7, 26, 0), Position(7, 28, 0)]));
      expect(turtle.coveredBy(idx(turtle, 6, 12, 3)), [143]);
      expect(turtle.covers(143), hasLength(4));
    });

    test('valid, no warnings, file positions already canonical', () {
      expect(Layout.validate(turtle.positions), isEmpty);
      expect(turtle.warnings(), isEmpty);
      final sorted = List.of(turtle.positions)..sort(Position.compare);
      expect(turtle.positions, sorted);
    });

    test('assets/layouts/turtle.json is what tool/gen_turtle.dart generates', () {
      final onDisk = File('$repoRoot/assets/layouts/turtle.json').readAsStringSync().replaceAll('\r\n', '\n');
      expect(onDisk, gen.turtleJson());
    });

    test('initially free tiles', () {
      final free = turtle.freeTiles(turtle.all);
      expect(free, contains(143));
      expect(free, contains(idx(turtle, 7, 0, 0)));
      expect(free, isNot(contains(idx(turtle, 6, 12, 3))));
    });
  });

  group('every bundled layout', () {
    for (final f in bundledLayoutFiles()) {
      test('${f.uri.pathSegments.last} parses and validates', () {
        final data = LayoutData.parse(f.readAsStringSync());
        expect(data.validate(), isEmpty);
        final l = data.build();
        expect(l.length, inInclusiveRange(2, 144));
        expect(l.length.isEven, isTrue);
      });
    }
  });

  group('TileSet', () {
    test('basic operations', () {
      final s = TileSet.empty(144).add(0).add(31).add(32).add(143);
      expect(s.toList(), [0, 31, 32, 143]);
      expect(s.length, 4);
      expect(s.contains(31), isTrue);
      expect(s.remove(31).contains(31), isFalse);
      expect(TileSet.full(144).length, 144);
      expect(TileSet.full(144).removeAll([0, 143]).length, 142);
      expect(TileSet.of(144, [1, 2]), TileSet.empty(144).addAll([2, 1]));
      expect(TileSet.empty(10).isEmpty, isTrue);
      expect(popCount32(0xFFFFFFFF), 32);
    });
  });
}
