import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/board/tile/tile_widget.dart';
import 'package:jadewell_flutter_app/ui/theme/clay.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_raster_cache.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_theme.dart';
import 'package:jadewell_flutter_app/ui/theme/jw_tokens.dart';
import 'package:material_ui/material_ui.dart';

import 'golden_helpers.dart';

void main() {
  setUp(JwRasterCache.instance.clear);

  test('a key renders once and is reused', () {
    final cache = JwRasterCache.instance;
    final before = cache.renderCount;
    void paint(Canvas c) => c.drawRect(const Rect.fromLTWH(0, 0, 10, 10), Paint());
    final a = cache.obtain('k', const Rect.fromLTWH(0, 0, 10, 10), 2, paint)!;
    final b = cache.obtain('k', const Rect.fromLTWH(0, 0, 10, 10), 2, paint)!;
    expect(identical(a, b), isTrue);
    expect(cache.renderCount - before, 1);
    expect(a.image.width, 20);
    expect(a.destAt(const Offset(5, 5)), const Rect.fromLTWH(5, 5, 10, 10));
  });

  test('cache is bounded by bytes and evicts least recently used', () {
    final cache = JwRasterCache.instance;
    final saved = cache.maxBytes;
    cache.maxBytes = 3 * 100 * 100 * 4;
    addTearDown(() => cache.maxBytes = saved);
    for (var i = 0; i < 5; i++) {
      cache.obtain(i, const Rect.fromLTWH(0, 0, 100, 100), 1, (_) {});
    }
    expect(cache.length, 3);
    expect(cache.peek(0), isNull);
    expect(cache.peek(4), isNotNull);
  });

  test('memory pressure empties the cache', () {
    final cache = JwRasterCache.instance..obtain('x', const Rect.fromLTWH(0, 0, 4, 4), 1, (_) {});
    expect(cache.length, 1);
    cache.didHaveMemoryPressure();
    expect(cache.length, 0);
    expect(cache.bytes, 0);
  });

  test('scales are bucketed to 1/8', () {
    expect(JwRasterCache.bucket(2.625), 2.625);
    expect(JwRasterCache.bucket(2.63), 2.75);
    expect(JwRasterCache.bucket(0.01), 0.25);
  });

  test('clay surfaces render one texture per size and scale, none for a plain fill', () {
    const d = ClayDecoration(level: ClayLevel.raised, colors: JwColors.light, radius: 12);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final before = JwRasterCache.instance.renderCount;
    d.paintInto(canvas, const Rect.fromLTWH(0, 0, 100, 40), devicePixelRatio: 2);
    d.paintInto(canvas, const Rect.fromLTWH(0, 50, 100, 40), devicePixelRatio: 2);
    expect(JwRasterCache.instance.renderCount - before, 1);
    final r = d.rasterFor(canvas, const Size(100, 40), 2)!;
    // The texture covers the outer shadows' reach.
    expect(r.bounds.top, lessThan(0));
    expect(r.bounds.bottom, greaterThan(40 + 12));
    const flat = ClayDecoration(level: ClayLevel.flat, colors: JwColors.light);
    expect(flat.rasterFor(canvas, const Size(100, 40), 2), isNull);
    recorder.endRecording().dispose();
  });

  testWidgets('a board of tiles shares one texture per face and state', (tester) async {
    final faces = loadFaces();
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJwThemeData(Brightness.light),
        home: Wrap(
          children: [
            for (var i = 0; i < 3; i++)
              for (final f in faces.take(10)) TileWidget(face: f, reduceMotion: true),
            for (final f in faces.take(10)) TileWidget(face: f, state: TileVisualState.blocked, reduceMotion: true),
          ],
        ),
      ),
    );
    // 10 faces × 2 states, plus one clay texture per state they are built on.
    expect(JwRasterCache.instance.length, 10 * 2 + 2);
  });
}
