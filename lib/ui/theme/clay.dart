import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'jw_tokens.dart';

/// One CSS-style box shadow: `[inset] dx dy blur spread colour`.
///
/// [blur] is the CSS blur radius; it is converted to a Gaussian sigma of
/// `blur / 2` when painted. Negative [spread] shrinks the shadow shape (and
/// its corner radius) exactly like CSS.
@immutable
class ClayShadow {
  const ClayShadow(
    this.dx,
    this.dy,
    this.blur,
    this.spread,
    this.color, {
    this.inset = false,
  });

  const ClayShadow.inset(this.dx, this.dy, this.blur, this.spread, this.color)
    : inset = true;

  final double dx;
  final double dy;
  final double blur;
  final double spread;
  final Color color;
  final bool inset;

  Offset get offset => Offset(dx, dy);

  /// CSS blur radius → Gaussian sigma.
  double get sigma => blur / 2;

  @override
  bool operator ==(Object other) =>
      other is ClayShadow &&
      other.dx == dx &&
      other.dy == dy &&
      other.blur == blur &&
      other.spread == spread &&
      other.color == color &&
      other.inset == inset;

  @override
  int get hashCode => Object.hash(dx, dy, blur, spread, color, inset);

  @override
  String toString() =>
      'ClayShadow(${inset ? 'inset ' : ''}$dx $dy $blur $spread $color)';
}

/// The elevation levels of DESIGN_SYSTEM.md §5.
enum ClayLevel {
  /// No shadows at all; a plain clay fill.
  flat,

  /// e0 · sunken: plates, tracks, toggle off, skeletons, locked cards.
  sunken,

  /// e1 · chip: chips, segmented pill, avatars, knobs.
  chip,

  /// e2 · raised: cards, secondary buttons, pills, tray, list groups.
  raised,

  /// e3 · floating: sheets, dialogs, toasts.
  floating,

  /// Any raised element while pressed.
  pressed,

  /// Accent (primary) buttons.
  primary,

  /// Playable tile (4 pt edge).
  tile,

  /// Blocked tile (3 pt edge).
  tileBlocked,

  /// Selected tile: tile with the lifted shadow and the 2.5 pt ring.
  tileLifted;

  /// The default fill for this level.
  Color fill(JwColors c) => switch (this) {
    ClayLevel.sunken => c.surfaceSunken,
    ClayLevel.primary => c.accent,
    ClayLevel.tile || ClayLevel.tileLifted => c.tileFace,
    ClayLevel.tileBlocked => c.tileBlocked,
    _ => c.surfaceRaised,
  };

  /// Resolved shadow stack, listed top-most first (CSS order).
  List<ClayShadow> shadows(JwColors c) => switch (this) {
    ClayLevel.flat => const [],
    ClayLevel.sunken => [
      ClayShadow.inset(3, 3, 7, 0, c.inner),
      ClayShadow.inset(-3, -3, 6, 0, c.highlight),
    ],
    ClayLevel.chip => [
      ClayShadow.inset(1.5, 1.5, 3, 0, c.highlight),
      ClayShadow.inset(-2, -2, 4, 0, c.inner),
      ClayShadow(0, 6, 12, -6, c.shadow),
    ],
    ClayLevel.raised => [
      ClayShadow.inset(2, 2, 4, 0, c.highlight),
      ClayShadow.inset(-3, -4, 7, 0, c.inner),
      ClayShadow(0, 12, 24, -10, c.shadow),
      ClayShadow(0, 3, 6, -2, c.shadow),
    ],
    ClayLevel.floating => [
      ClayShadow.inset(3, 3, 5, 0, c.highlight),
      ClayShadow.inset(-5, -6, 10, 0, c.inner),
      ClayShadow(0, 28, 40, -14, c.shadow),
      ClayShadow(0, 6, 12, -4, c.shadow),
    ],
    ClayLevel.pressed => [
      ClayShadow.inset(3, 4, 8, 0, c.inner),
      ClayShadow.inset(-2, -2, 5, 0, c.highlightSoft),
    ],
    ClayLevel.primary => [
      const ClayShadow.inset(2, 2, 4, 0, Color(0x73FFFFFF)),
      const ClayShadow.inset(-3, -3, 6, 0, Color(0x14000000)),
      ClayShadow(0, 14, 22, -10, c.shadow),
    ],
    ClayLevel.tile => [
      ClayShadow.inset(1.5, 1.5, 2, 0, c.highlight),
      ClayShadow.inset(-2, -2.5, 3, 0, c.inner),
      ClayShadow(0, JwTile.edge, 0, 0, c.tileEdge),
      ClayShadow(0, 9, 12, -3, c.shadow),
    ],
    ClayLevel.tileBlocked => [
      ClayShadow.inset(1, 1, 1, 0, c.highlightSoft),
      ClayShadow.inset(-1, -1.5, 2, 0, c.inner),
      ClayShadow(0, 3, 0, 0, c.tileBlockedEdge),
      ClayShadow(0, 4, 6, -3, c.shadow),
    ],
    ClayLevel.tileLifted => [
      ClayShadow.inset(1.5, 1.5, 2, 0, c.highlight),
      ClayShadow.inset(-2, -2.5, 3, 0, c.inner),
      ClayShadow(0, JwTile.edge, 0, 0, c.tileEdge),
      ClayShadow(0, 18, 18, -5, c.shadow),
      ClayShadow(0, 0, 0, JwTile.selectedRing, c.tileSelected),
    ],
  };
}

/// A soft-clay [Decoration]: outer shadows (blurred with `MaskFilter.blur`),
/// a fill, then inset shadows drawn as blurred inverse paths clipped to the
/// rounded rect. Rendered pictures are cached per (size, radius, fill,
/// shadows) in an LRU-bounded [ClayPictureCache], so identical surfaces (every
/// playable tile, every chip of one size) share one picture.
@immutable
class ClayDecoration extends Decoration {
  const ClayDecoration({
    required this.level,
    required this.colors,
    this.color,
    this.gradient,
    this.radius = 0,
    this.extraShadows = const [],
  });

  final ClayLevel level;

  /// Theme colours the level resolves against.
  final JwColors colors;

  /// Fill override. Defaults to [ClayLevel.fill].
  final Color? color;

  /// Gradient fill; wins over [color] when set.
  final Gradient? gradient;

  /// Corner radius, clamped to half the shortest side (so 999 = pill/circle).
  final double radius;

  /// Shadows appended below the level's own (rings, glows, outlines).
  final List<ClayShadow> extraShadows;

  Color get resolvedFill => color ?? level.fill(colors);

  List<ClayShadow> get resolvedShadows =>
      extraShadows.isEmpty
          ? level.shadows(colors)
          : [...level.shadows(colors), ...extraShadows];

  ClayDecoration copyWith({
    ClayLevel? level,
    JwColors? colors,
    Color? color,
    Gradient? gradient,
    double? radius,
    List<ClayShadow>? extraShadows,
  }) => ClayDecoration(
    level: level ?? this.level,
    colors: colors ?? this.colors,
    color: color ?? this.color,
    gradient: gradient ?? this.gradient,
    radius: radius ?? this.radius,
    extraShadows: extraShadows ?? this.extraShadows,
  );

  @override
  bool get isComplex => true;

  @override
  EdgeInsetsGeometry get padding => EdgeInsets.zero;

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      Path()..addRRect(_rrect(rect, radius));

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      _rrect(Offset.zero & size, radius).contains(position);

  @override
  Decoration? lerpFrom(Decoration? a, double t) {
    if (a is ClayDecoration) return ClayBlendDecoration(a, this, t);
    return super.lerpFrom(a, t);
  }

  @override
  Decoration? lerpTo(Decoration? b, double t) {
    if (b is ClayDecoration) return ClayBlendDecoration(this, b, t);
    return super.lerpTo(b, t);
  }

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _ClayPainter(this);

  @override
  bool operator ==(Object other) =>
      other is ClayDecoration &&
      other.level == level &&
      other.colors == colors &&
      other.color == color &&
      other.gradient == gradient &&
      other.radius == radius &&
      listEquals(other.extraShadows, extraShadows);

  @override
  int get hashCode => Object.hash(
    level,
    colors,
    color,
    gradient,
    radius,
    Object.hashAll(extraShadows),
  );

  /// Paints this decoration into [canvas] at [rect] (uses the cache).
  void paintInto(Canvas canvas, Rect rect) {
    final picture = ClayPictureCache.instance.obtain(this, rect.size);
    canvas
      ..save()
      ..translate(rect.left, rect.top)
      ..drawPicture(picture)
      ..restore();
  }
}

/// Cross-fade between two clay decorations (`t` = 0 shows [a], 1 shows [b]).
/// Used for press transitions: both pictures stay cached, only opacity moves.
@immutable
class ClayBlendDecoration extends Decoration {
  const ClayBlendDecoration(this.a, this.b, this.t);

  final ClayDecoration a;
  final ClayDecoration b;
  final double t;

  @override
  bool get isComplex => true;

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      (t < 0.5 ? a : b).getClipPath(rect, textDirection);

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      (t < 0.5 ? a : b).hitTest(size, position);

  @override
  Decoration? lerpTo(Decoration? b, double t) {
    if (b is ClayDecoration) {
      return ClayBlendDecoration(this.t < 0.5 ? a : this.b, b, t);
    }
    return super.lerpTo(b, t);
  }

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _ClayBlendPainter(this);

  @override
  bool operator ==(Object other) =>
      other is ClayBlendDecoration && other.a == a && other.b == b && other.t == t;

  @override
  int get hashCode => Object.hash(a, b, t);
}

class _ClayPainter extends BoxPainter {
  _ClayPainter(this.decoration);

  final ClayDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    decoration.paintInto(canvas, offset & size);
  }
}

class _ClayBlendPainter extends BoxPainter {
  _ClayBlendPainter(this.decoration);

  final ClayBlendDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final t = decoration.t.clamp(0.0, 1.0);
    if (t <= 0.001) {
      decoration.a.paintInto(canvas, rect);
      return;
    }
    if (t >= 0.999) {
      decoration.b.paintInto(canvas, rect);
      return;
    }
    decoration.a.paintInto(canvas, rect);
    final bounds = rect.inflate(60);
    canvas.saveLayer(bounds, Paint()..color = Color.fromRGBO(0, 0, 0, t));
    decoration.b.paintInto(canvas, rect);
    canvas.restore();
  }
}

RRect _rrect(Rect rect, double radius) {
  final r = math.min(radius, rect.shortestSide / 2);
  return RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, r)));
}

/// LRU cache of recorded clay pictures.
class ClayPictureCache {
  ClayPictureCache._();

  static final ClayPictureCache instance = ClayPictureCache._();

  /// Maximum number of pictures kept. Tiles need about 3 per theme; every
  /// distinct component size adds one.
  int maxEntries = 400;

  final LinkedHashMap<_ClayKey, ui.Picture> _entries = LinkedHashMap();

  int get length => _entries.length;

  /// Test hook: number of pictures recorded since start.
  int recordCount = 0;

  void clear() => _entries.clear();

  ui.Picture obtain(ClayDecoration d, Size size) {
    final key = _ClayKey(
      size,
      d.radius,
      d.resolvedFill,
      d.gradient,
      d.resolvedShadows,
    );
    final hit = _entries.remove(key);
    if (hit != null) {
      _entries[key] = hit; // move to most-recent
      return hit;
    }
    final picture = _record(key);
    recordCount++;
    _entries[key] = picture;
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    return picture;
  }

  static ui.Picture _record(_ClayKey k) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rect = Offset.zero & k.size;
    final rrect = _rrect(rect, k.radius);
    final baseRadius = rrect.tlRadiusX;

    // Outer shadows: below the fill, clipped to the outside of the box (CSS
    // never paints a box-shadow under its own box). Painted bottom-most first.
    final outer = k.shadows.where((s) => !s.inset).toList().reversed;
    if (outer.isNotEmpty) {
      final reach = outer.fold<double>(
        0,
        (m, s) => math.max(m, s.blur * 1.5 + s.spread.abs() + s.dx.abs() + s.dy.abs()),
      );
      canvas
        ..save()
        ..clipPath(
          Path()
            ..fillType = PathFillType.evenOdd
            ..addRect(rect.inflate(reach + 4))
            ..addRRect(rrect),
        );
      for (final s in outer) {
        final shape = _spread(rect, baseRadius, s.spread).shift(s.offset);
        final paint = Paint()..color = s.color;
        if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.sigma);
        canvas.drawRRect(shape, paint);
      }
      canvas.restore();
    }

    // Fill.
    final fill = Paint()..color = k.fill;
    if (k.gradient != null) fill.shader = k.gradient!.createShader(rect);
    canvas.drawRRect(rrect, fill);

    // Inset shadows: clip to the box, then paint a blurred inverse of the
    // (spread-shrunk, offset) inner shape.
    final inset = k.shadows.where((s) => s.inset).toList().reversed;
    if (inset.isNotEmpty) {
      canvas
        ..save()
        ..clipRRect(rrect);
      for (final s in inset) {
        final hole = _spread(rect, baseRadius, -s.spread).shift(s.offset);
        final path = Path()
          ..fillType = PathFillType.evenOdd
          ..addRect(rect.inflate(s.blur * 2 + s.dx.abs() + s.dy.abs() + 8))
          ..addRRect(hole);
        final paint = Paint()..color = s.color;
        if (s.blur > 0) paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.sigma);
        canvas.drawPath(path, paint);
      }
      canvas.restore();
    }
    return recorder.endRecording();
  }

  /// CSS spread: grows (or, negative, shrinks) the box and its radius.
  static RRect _spread(Rect rect, double radius, double spread) {
    final r = rect.inflate(spread);
    if (r.width <= 0 || r.height <= 0) {
      return RRect.fromRectAndRadius(Rect.fromCenter(center: rect.center, width: 0, height: 0), Radius.zero);
    }
    final rr = radius <= 0 ? 0.0 : math.max(0.0, radius + spread);
    return RRect.fromRectAndRadius(r, Radius.circular(math.min(rr, r.shortestSide / 2)));
  }
}

@immutable
class _ClayKey {
  _ClayKey(this.size, this.radius, this.fill, this.gradient, this.shadows)
    : _hash = Object.hash(size, radius, fill, gradient, Object.hashAll(shadows));

  final Size size;
  final double radius;
  final Color fill;
  final Gradient? gradient;
  final List<ClayShadow> shadows;
  final int _hash;

  @override
  bool operator ==(Object other) =>
      other is _ClayKey &&
      other._hash == _hash &&
      other.size == size &&
      other.radius == radius &&
      other.fill == fill &&
      other.gradient == gradient &&
      listEquals(other.shadows, shadows);

  @override
  int get hashCode => _hash;
}
