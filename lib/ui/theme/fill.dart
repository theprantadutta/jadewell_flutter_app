import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'clay.dart';
import 'jw_palette.dart';
import 'jw_tokens.dart';

/// A saturated Clay Pop fill (DESIGN_SYSTEM §3 recipe): 160° gradient
/// top → mid, inner highlight and shade, a solid base [edge] below the box
/// and an optional same-hue glow.
///
/// Rendering follows docs/PERFORMANCE.md: the glow and the body (gradient +
/// blurred insets) are separate cached textures (through [ClayDecoration] /
/// `JwRasterCache`), and the edge is a plain rounded rect between them, so a
/// press ([pressed] 0…1) only moves textures and slides the edge under the
/// body. Nothing is blurred or re-rasterized per frame.
///
/// The edge (and glow) paint outside the box, like shadows: leave
/// [edge] pt of room below.
@immutable
class FillDecoration extends Decoration {
  const FillDecoration({
    required this.fill,
    required this.colors,
    this.radius = JwRadius.lg,
    this.edge = JwFills.cardEdge,
    this.glow = true,
    this.pressed = 0,
    this.dip = false,
  });

  final JwFill fill;

  /// Theme colours; selects the light or dark recipe strengths.
  final JwColors colors;

  /// Corner radius, clamped to half the shortest side.
  final double radius;

  /// Base edge height (5 for cards, knobs and buttons, 3 for badges, 2 for
  /// progress bars, 0 for none).
  final double edge;

  /// Draw the same-hue glow (cards, knobs, buttons; not badges).
  final bool glow;

  /// Press progress: 0 at rest, 1 fully pressed (moved down
  /// [JwFills.pressDepth], edge hidden, glow gone, dark inset). Values a
  /// little below 0 (spring overshoot) lift the body and lengthen the edge.
  final double pressed;

  /// Reduce motion: the press is a brightness dip only (no translation, the
  /// edge stays).
  final bool dip;

  bool get isDark => identical(colors, JwColors.dark);
  JwFills get strengths => isDark ? JwFills.dark : JwFills.light;

  FillDecoration copyWith({
    JwFill? fill,
    JwColors? colors,
    double? radius,
    double? edge,
    bool? glow,
    double? pressed,
    bool? dip,
  }) => FillDecoration(
    fill: fill ?? this.fill,
    colors: colors ?? this.colors,
    radius: radius ?? this.radius,
    edge: edge ?? this.edge,
    glow: glow ?? this.glow,
    pressed: pressed ?? this.pressed,
    dip: dip ?? this.dip,
  );

  /// Inner highlight + shade of the body.
  List<ClayShadow> get _insets {
    final f = strengths;
    return [
      ClayShadow.inset(2, 3, 6, 0, JwBase.white.withValues(alpha: f.highlightAlpha)),
      ClayShadow.inset(-3, -5, 10, 0, JwBase.black.withValues(alpha: f.shadeAlpha)),
    ];
  }

  ClayDecoration get _body => ClayDecoration(
    level: ClayLevel.flat,
    colors: colors,
    color: fill.mid,
    gradient: JwFills.gradient(fill),
    radius: radius,
    extraShadows: _insets,
  );

  ClayDecoration get _pressedBody => _body.copyWith(
    extraShadows: [..._insets, ClayShadow.inset(2, 3, 6, 0, JwBase.black.withValues(alpha: 0.12))],
  );

  ClayDecoration get _glow {
    final f = strengths;
    return ClayDecoration(
      level: ClayLevel.flat,
      colors: colors,
      color: JwBase.transparent,
      radius: radius,
      extraShadows: [ClayShadow(0, 16, f.glowBlur, -10, fill.glow.withValues(alpha: f.glowAlpha))],
    );
  }

  /// Paints the fill into [rect] (the resting box). [devicePixelRatio]
  /// enables the cached textures; [allowRaster] false replays pictures (an
  /// animating size).
  void paintInto(Canvas canvas, Rect rect, {double? devicePixelRatio, bool allowRaster = true, double opacity = 1}) {
    if (opacity <= 0 || rect.isEmpty) return;
    final t = pressed;
    final tc = t.clamp(0.0, 1.0);
    final d = dip ? 0.0 : JwFills.pressDepth * math.max(t, -0.5);
    final body = rect.shift(Offset(0, d));
    if (glow && tc < 1) {
      _glow.paintInto(canvas, body, devicePixelRatio: devicePixelRatio, allowRaster: allowRaster, opacity: opacity * (1 - tc));
    }
    final visibleEdge = dip ? edge : edge * (1 - t);
    if (edge > 0 && visibleEdge > 0.05) {
      final r = math.max(0.0, math.min(radius, rect.shortestSide / 2));
      canvas.drawRRect(
        RRect.fromRectAndRadius(body.shift(Offset(0, visibleEdge)), Radius.circular(r)),
        Paint()..color = fill.edge.withValues(alpha: fill.edge.a * opacity),
      );
    }
    _body.paintInto(canvas, body, devicePixelRatio: devicePixelRatio, allowRaster: allowRaster, opacity: opacity);
    if (tc > 0) {
      _pressedBody.paintInto(canvas, body, devicePixelRatio: devicePixelRatio, allowRaster: allowRaster, opacity: opacity * tc);
      if (dip) {
        // Reduce motion: a brightness dip over the whole body.
        canvas.drawRRect(_rrect(body), Paint()..color = JwBase.black.withValues(alpha: 0.10 * tc * opacity));
      }
    }
  }

  @override
  bool get isComplex => true;

  @override
  EdgeInsetsGeometry get padding => EdgeInsets.zero;

  RRect _rrect(Rect rect) =>
      RRect.fromRectAndRadius(rect, Radius.circular(math.max(0, math.min(radius, rect.shortestSide / 2))));

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) => Path()..addRRect(_rrect(rect));

  @override
  bool hitTest(Size size, Offset position, {TextDirection? textDirection}) =>
      _rrect(Offset.zero & size).contains(position);

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _FillPainter(this, onChanged);

  @override
  bool operator ==(Object other) =>
      other is FillDecoration &&
      other.fill == fill &&
      identical(other.colors, colors) &&
      other.radius == radius &&
      other.edge == edge &&
      other.glow == glow &&
      other.pressed == pressed &&
      other.dip == dip;

  @override
  int get hashCode => Object.hash(fill, identityHashCode(colors), radius, edge, glow, pressed, dip);
}

class _FillPainter extends BoxPainter with ClayRasterGuard {
  _FillPainter(this.decoration, super.onChanged);

  final FillDecoration decoration;

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
