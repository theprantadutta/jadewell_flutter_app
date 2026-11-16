import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../theme/jw_fonts.dart';
import 'tile_face_spec.dart';

/// Tile face palette (DESIGN_SYSTEM §2): the same in both themes.
abstract final class TilePalette {
  static const blue = Color(0xFF5260B0);
  static const green = Color(0xFF4E9474);
  static const red = Color(0xFFE2664F);
  static const teal = Color(0xFF3B7A6C);
  static const plum = Color(0xFF4A3F5C);
  static const rose = Color(0xFFC95E80);
  static const amber = Color(0xFFB97E2A);
  static const jade = Color(0xFF4FA585);

  static Color element(TileKind kind, String key) => switch ((kind, key)) {
    (TileKind.circles, 'c1') => blue,
    (TileKind.circles, 'c2') => green,
    (TileKind.circles, 'c3') => red,
    (_, 'g') => green,
    (_, 'b') => teal,
    (_, 'r') => red,
    _ => plum,
  };
}

/// Colour matrix for glyphs on blocked tiles: [saturation] (0…1) and
/// [opacity] folded into one matrix.
List<double> tileGlyphMatrix({double saturation = 1, double opacity = 1}) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final s = saturation, i = 1 - s;
  return [
    lr * i + s, lg * i, lb * i, 0, 0, //
    lr * i, lg * i + s, lb * i, 0, 0,
    lr * i, lg * i, lb * i + s, 0, 0,
    0, 0, 0, opacity, 0,
  ];
}

/// Greyscale matrix (used for the readability proof).
const List<double> kGreyscaleMatrix = [
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];

/// Paints one face's glyphs into its glyph box (the canvas size; 21.5 × 28.5
/// at 1×). Geometry comes from `tile-faces.json`; sizes scale with the box.
///
/// Circles are clay beads, bamboo are capsules with a vertical sheen (the
/// 1-bamboo has a coral cap), characters are a numeral over 萬, winds and
/// dragons a single glyph (white dragon: blue rounded frame), flowers and
/// seasons a glyph with its index bottom-right. Blocked tiles pass
/// [glyphOpacity] and [saturation] (applied through one colour matrix).
class TileFacePainter extends CustomPainter {
  const TileFacePainter(this.face, {this.glyphOpacity = 1, this.saturation = 1});

  final TileFaceSpec face;
  final double glyphOpacity;
  final double saturation;

  static const Size glyphBox = Size(21.5, 28.5);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = glyphOpacity < 1 || saturation < 1;
    if (dim) {
      canvas.saveLayer(
        (Offset.zero & size).inflate(4),
        Paint()..colorFilter = ColorFilter.matrix(tileGlyphMatrix(saturation: saturation, opacity: glyphOpacity)),
      );
    }
    final k = size.width / glyphBox.width;
    switch (face.kind) {
      case TileKind.circles:
        _circles(canvas, size);
      case TileKind.bamboo:
        _bamboo(canvas, size);
      case TileKind.characters:
        _text(canvas, face.glyph!, 11 * k, TilePalette.plum, Offset(size.width / 2, size.height * 0.27));
        _text(canvas, '萬', 12 * k, TilePalette.red, Offset(size.width / 2, size.height * 0.72));
      case TileKind.wind:
        _text(canvas, face.glyph!, 17 * k, TilePalette.plum, size.center(Offset.zero), weight: FontWeight.w900);
      case TileKind.dragon:
        if (face.isWhiteDragon) {
          _whiteDragon(canvas, size, k);
        } else {
          final c = face.glyph == '中' ? TilePalette.red : TilePalette.green;
          _text(canvas, face.glyph!, 17 * k, c, size.center(Offset.zero));
        }
      case TileKind.flower:
      case TileKind.season:
        final c = face.kind == TileKind.flower ? TilePalette.rose : TilePalette.amber;
        _text(canvas, face.glyph!, 17 * k, c, Offset(size.width * 0.47, size.height * 0.47));
        if (face.index != null) {
          _text(
            canvas,
            face.index!,
            6.6 * k,
            c,
            Offset(size.width + 0.6 * k, size.height + 0.4 * k),
            family: JwFonts.ui,
            anchor: Alignment.bottomRight,
          );
        }
    }
    if (dim) canvas.restore();
  }

  void _circles(Canvas canvas, Size size) {
    final n = face.elements.length;
    final pct = switch (n) {
      1 => 0.80,
      2 || 3 => 0.36,
      4 => 0.34,
      5 || 6 => 0.30,
      7 || 8 => 0.25,
      _ => 0.24,
    };
    final d = size.width * pct;
    if (n == 1) {
      final c = size.center(Offset.zero);
      final pale = Color.lerp(const Color(0xFFFFFFFF), TilePalette.jade, 0.26)!;
      canvas
        ..drawCircle(c, d / 2, Paint()..color = pale)
        ..drawCircle(c, d * 0.335, Paint()..color = TilePalette.jade);
      paintBead(canvas, c, d * 0.36, TilePalette.red);
      return;
    }
    for (final e in face.elements) {
      paintBead(
        canvas,
        Offset(size.width * e.x / 100, size.height * e.y / 100),
        d,
        TilePalette.element(face.kind, e.colour),
      );
    }
  }

  /// A clay bead: radial highlight at 34% / 30%, inner shade bottom-right.
  static void paintBead(Canvas canvas, Offset c, double d, Color color) {
    final r = d / 2;
    final hi = Color.lerp(color, const Color(0xFFFFFFFF), 0.55)!;
    final lo = Color.lerp(color, const Color(0xFF000000), 0.25)!;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(rect.left + d * 0.34, rect.top + d * 0.30),
          d * 0.78,
          [hi, color, lo],
          const [0, 0.45, 1],
        ),
    );
  }

  void _bamboo(Canvas canvas, Size size) {
    final n = face.elements.length;
    if (n == 1) {
      final w = size.width * 0.28, h = size.height * 0.80;
      final r = Rect.fromCenter(center: size.center(Offset.zero), width: w, height: h);
      final rr = RRect.fromRectAndRadius(r, Radius.circular(w / 2));
      canvas
        ..save()
        ..clipRRect(rr);
      _capsuleFill(canvas, r, TilePalette.green);
      _capsuleFill(canvas, Rect.fromLTWH(r.left, r.top, r.width, h * 0.27), TilePalette.red);
      canvas.restore();
      return;
    }
    final w = size.width * (n == 8 ? 0.13 : 0.15);
    final h = size.height * (n == 7 || n == 9 ? 0.26 : 0.34);
    for (final e in face.elements) {
      final r = Rect.fromCenter(
        center: Offset(size.width * e.x / 100, size.height * e.y / 100),
        width: w,
        height: h,
      );
      canvas
        ..save()
        ..clipRRect(RRect.fromRectAndRadius(r, Radius.circular(w / 2)));
      _capsuleFill(canvas, r, TilePalette.element(face.kind, e.colour));
      canvas.restore();
    }
  }

  /// Capsule body with a vertical sheen (light band left, shade right).
  static void _capsuleFill(Canvas canvas, Rect r, Color c) {
    final hi = Color.lerp(c, const Color(0xFFFFFFFF), 0.32)!;
    final lo = Color.lerp(c, const Color(0xFF000000), 0.14)!;
    canvas.drawRect(
      r,
      Paint()
        ..shader = ui.Gradient.linear(
          r.centerLeft,
          r.centerRight,
          [c, hi, c, lo],
          const [0, 0.3, 0.62, 1],
        ),
    );
  }

  void _whiteDragon(Canvas canvas, Size size, double k) {
    final stroke = 2.3 * k;
    final r = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * 0.56,
      height: size.height * 0.66,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(stroke / 2), Radius.circular(math.min(6 * k, r.width / 2))),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = TilePalette.blue,
    );
  }

  static final Map<String, TextPainter> _textCache = {};

  static void _text(
    Canvas canvas,
    String text,
    double fontSize,
    Color color,
    Offset at, {
    FontWeight weight = FontWeight.w700,
    String family = JwFonts.glyph,
    Alignment anchor = Alignment.center,
  }) {
    final key = '$text|${fontSize.toStringAsFixed(2)}|${color.toARGB32()}|${weight.value}|$family';
    final tp = _textCache[key] ??= (TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: family,
          fontSize: fontSize,
          fontWeight: weight,
          color: color,
          height: 1,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout());
    if (_textCache.length > 600) _textCache.remove(_textCache.keys.first);
    final dx = at.dx - tp.width * (anchor.x + 1) / 2;
    final dy = at.dy - tp.height * (anchor.y + 1) / 2;
    tp.paint(canvas, Offset(dx, dy));
  }

  /// Drops cached text layouts (call after fonts load in tests).
  static void clearTextCache() => _textCache.clear();

  @override
  bool shouldRepaint(TileFacePainter old) =>
      old.face.id != face.id || old.glyphOpacity != glyphOpacity || old.saturation != saturation;
}
