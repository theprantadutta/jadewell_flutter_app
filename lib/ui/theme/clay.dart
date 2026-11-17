import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'jw_palette.dart';
import 'jw_raster_cache.dart';
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

  /// Primary buttons: the purple fill (gradient, inner highlight and shade,
  /// 5 pt solid base edge, same-hue glow). With a custom colour the edge and
  /// glow derive from it.
  primary,

  /// [primary] while pressed: base edge and glow gone, a dark inset added.
  /// `copyWith(level: ClayLevel.pressed)` on a primary decoration yields
  /// this level.
  primaryPressed,

  /// Playable tile (4 pt edge).
  tile,

  /// Blocked tile (3 pt edge).
  tileBlocked,

  /// Selected tile: tile with the lifted shadow and the 2.5 pt ring.
  tileLifted;

  /// The default fill for this level.
  Color fill(JwColors c) => switch (this) {
    ClayLevel.sunken => c.surfaceSunken,
    ClayLevel.primary || ClayLevel.primaryPressed => JwFill.purple.mid,
    ClayLevel.tile || ClayLevel.tileLifted => c.tileFace,
    ClayLevel.tileBlocked => c.tileBlocked,
    _ => c.surfaceRaised,
  };

  /// Resolved shadow stack, listed top-most first (CSS order). [tint]
  /// recolours the [primary] edge and glow for a non-purple fill.
  List<ClayShadow> shadows(JwColors c, {Color? tint}) => switch (this) {
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
    ClayLevel.primary => _primary(c, tint),
    ClayLevel.primaryPressed => [
      ..._fillInsets(c),
      ClayShadow.inset(2, 3, 6, 0, JwBase.black.withValues(alpha: 0.12)),
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
      ...tileRing(c.tileSelected),
      ClayShadow(0, 18, 18, -5, c.shadow),
      tileGlow(c.tileSelected, identical(c, JwColors.dark) ? 0.5 : 0.4),
    ],
  };

  /// A 2.5 pt ring around a tile's face and its 4 pt edge (selected,
  /// hinted).
  static List<ClayShadow> tileRing(Color color, {double width = JwTile.selectedRing, double edge = JwTile.edge}) => [
    ClayShadow(0, 0, 0, width, color),
    ClayShadow(0, edge, 0, width, color),
  ];

  /// A soft same-hue glow under a ringed tile.
  static ClayShadow tileGlow(Color color, double alpha) => ClayShadow(0, 4, 18, 1, color.withValues(alpha: alpha));

  static JwFills _strengths(JwColors c) => identical(c, JwColors.dark) ? JwFills.dark : JwFills.light;

  /// The fill recipe's inner highlight and shade for theme [c].
  static List<ClayShadow> _fillInsets(JwColors c) {
    final f = _strengths(c);
    return [
      ClayShadow.inset(2, 3, 6, 0, JwBase.white.withValues(alpha: f.highlightAlpha)),
      ClayShadow.inset(-3, -5, 10, 0, JwBase.black.withValues(alpha: f.shadeAlpha)),
    ];
  }

  static List<ClayShadow> _primary(JwColors c, Color? tint) {
    final f = _strengths(c);
    final edge = tint == null ? JwFill.purple.edge : JwFaceInks.darken(tint, 0.2);
    final glow = tint ?? JwFill.purple.glow;
    return [
      ..._fillInsets(c),
      ClayShadow(0, JwFills.cardEdge, 0, 0, edge),
      ClayShadow(0, 16, f.glowBlur, -10, glow.withValues(alpha: f.glowAlpha)),
    ];
  }
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

  /// [gradient], or the purple fill gradient for an untinted primary.
  Gradient? get resolvedGradient =>
      gradient ??
      ((level == ClayLevel.primary || level == ClayLevel.primaryPressed) && color == null
          ? JwFills.gradient(JwFill.purple)
          : null);

  List<ClayShadow> get resolvedShadows {
    final own = level.shadows(colors, tint: color);
    return extraShadows.isEmpty ? own : [...own, ...extraShadows];
  }

  ClayDecoration copyWith({
    ClayLevel? level,
    JwColors? colors,
    Color? color,
    Gradient? gradient,
    double? radius,
    List<ClayShadow>? extraShadows,
  }) => ClayDecoration(
    level: level == ClayLevel.pressed && this.level == ClayLevel.primary ? ClayLevel.primaryPressed : level ?? this.level,
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
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _ClayPainter(this, onChanged);

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

  /// Paints this decoration into [canvas] at [rect].
  ///
  /// With [devicePixelRatio] the surface is drawn from a cached texture
  /// ([JwRasterCache]) rendered at that ratio times the canvas scale, so its
  /// blurred shadows are not re-rendered every frame. [opacity] < 1 draws it
  /// translucent (same result as a layer, since it is one texture). Without
  /// a ratio (or with [allowRaster] false, or a surface too large to cache)
  /// the recorded picture is replayed.
  void paintInto(
    Canvas canvas,
    Rect rect, {
    double? devicePixelRatio,
    double opacity = 1,
    bool allowRaster = true,
  }) {
    if (opacity <= 0) return;
    final raster = devicePixelRatio == null ? null : rasterFor(canvas, rect.size, devicePixelRatio, create: allowRaster);
    if (raster != null) {
      raster.paint(canvas, rect.topLeft, opacity: opacity);
      return;
    }
    final picture = ClayPictureCache.instance.obtain(this, rect.size);
    if (opacity < 1) {
      canvas.saveLayer(rect.inflate(clayReach(resolvedShadows) + 4), Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    } else {
      canvas.save();
    }
    canvas
      ..translate(rect.left, rect.top)
      ..drawPicture(picture)
      ..restore();
  }

  /// The cached texture for this decoration at [size], rendered at
  /// [devicePixelRatio] × the canvas scale (never below 1×). Null for
  /// shadowless surfaces (a plain fill is cheaper to draw directly), for
  /// surfaces too large to cache, and on a miss when [create] is false.
  JwRaster? rasterFor(Canvas canvas, Size size, double devicePixelRatio, {bool create = true}) {
    final shadows = resolvedShadows;
    if (shadows.isEmpty) return null;
    final scale = JwRasterCache.bucket(devicePixelRatio * math.max(1.0, canvasScale(canvas)));
    final key = _ClayRasterKey(_ClayKey(size, radius, resolvedFill, resolvedGradient, shadows), scale);
    final cache = JwRasterCache.instance;
    if (!create) return cache.peek(key);
    final reach = clayReach(shadows);
    final bounds = (Offset.zero & size).inflate(reach > 0 ? reach + 4 : 1);
    return cache.obtain(key, bounds, scale, (c) => c.drawPicture(ClayPictureCache.instance.obtain(this, size)));
  }
}

/// How far (pt) outer [shadows] reach beyond the box (3 σ of the blur plus
/// spread and offset).
double clayReach(List<ClayShadow> shadows) => shadows
    .where((s) => !s.inset)
    .fold<double>(0, (m, s) => math.max(m, s.blur * 1.5 + s.spread.abs() + s.dx.abs() + s.dy.abs()));

@immutable
class _ClayRasterKey {
  const _ClayRasterKey(this.clay, this.scale);
  final _ClayKey clay;
  final double scale;

  @override
  bool operator ==(Object other) => other is _ClayRasterKey && other.scale == scale && other.clay == clay;

  @override
  int get hashCode => Object.hash(clay, scale);
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
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _ClayBlendPainter(this, onChanged);

  @override
  bool operator ==(Object other) =>
      other is ClayBlendDecoration && other.a == a && other.b == b && other.t == t;

  @override
  int get hashCode => Object.hash(a, b, t);
}

/// Shared by the clay and fill box painters: decides whether a paint may render a new
/// texture. A box whose size changes every frame (AnimatedSize, an animated
/// container) would otherwise render and cache a texture per frame, so while
/// its size is moving it replays the picture, and once the size has held
/// still for [_settle] it asks for one more paint that rasterizes.
mixin ClayRasterGuard on BoxPainter {
  static const _settle = Duration(milliseconds: 250);

  Size? _lastSize;
  final Stopwatch _sinceResize = Stopwatch();
  bool _moving = false;
  Timer? _timer;

  /// Whether this paint at [size] may create a texture.
  bool allowRasterAt(Size size) {
    if (_lastSize != null && size != _lastSize) {
      if (_sinceResize.isRunning && _sinceResize.elapsed < _settle) _moving = true;
      _sinceResize
        ..reset()
        ..start();
    } else if (_lastSize == null) {
      _sinceResize.start();
    }
    _lastSize = size;
    if (!_moving) return true;
    _timer?.cancel();
    _timer = Timer(_settle, () {
      _moving = false;
      onChanged?.call();
    });
    return false;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class _ClayPainter extends BoxPainter with ClayRasterGuard {
  _ClayPainter(this.decoration, super.onChanged);

  final ClayDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    decoration.paintInto(
      canvas,
      offset & size,
      devicePixelRatio: configuration.devicePixelRatio,
      allowRaster: allowRasterAt(size),
    );
  }
}

class _ClayBlendPainter extends BoxPainter with ClayRasterGuard {
  _ClayBlendPainter(this.decoration, super.onChanged);

  final ClayBlendDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    final dpr = configuration.devicePixelRatio;
    final allow = allowRasterAt(size);
    final t = decoration.t.clamp(0.0, 1.0);
    if (t <= 0.001) {
      decoration.a.paintInto(canvas, rect, devicePixelRatio: dpr, allowRaster: allow);
      return;
    }
    if (t >= 0.999) {
      decoration.b.paintInto(canvas, rect, devicePixelRatio: dpr, allowRaster: allow);
      return;
    }
    // b over a at opacity t: one translucent texture, no layer.
    decoration.a.paintInto(canvas, rect, devicePixelRatio: dpr, allowRaster: allow);
    decoration.b.paintInto(canvas, rect, devicePixelRatio: dpr, allowRaster: allow, opacity: t);
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
      d.resolvedGradient,
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
