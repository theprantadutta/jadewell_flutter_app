import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import 'fill_box.dart';

/// The one big fill per screen (DESIGN_SYSTEM §11 hero card): a [fill]
/// (purple by default) card, radius 30–34, white content, optional
/// [confetti] (small rotated badges in all six fills at fixed, deterministic
/// positions; [confettiSeed] rotates which colour lands where).
///
/// With [onTap] the whole card presses like a fill ([FillPressable]).
/// The card's 5 pt base edge paints below its box.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.child,
    this.fill = JwFill.purple,
    this.radius = 32,
    this.padding = const EdgeInsets.all(22),
    this.confetti = false,
    this.confettiSeed = 0,
    this.confettiCount = 8,
    this.width,
    this.height,
    this.onTap,
    this.onHaptic,
    this.semanticLabel,
  });

  final Widget child;
  final JwFill fill;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool confetti;
  final int confettiSeed;

  /// Number of confetti pieces (up to [ConfettiPainter.maxPieces]).
  final int confettiCount;
  final double? width;
  final double? height;
  final VoidCallback? onTap;
  final VoidCallback? onHaptic;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget content = DefaultTextStyle.merge(
      style: TextStyle(color: fill.on),
      child: Padding(padding: padding, child: child),
    );
    if (confetti) {
      content = CustomPaint(
        painter: ConfettiPainter(seed: confettiSeed, count: confettiCount, exclude: fill),
        child: content,
      );
    }
    if (onTap != null) {
      return FillPressable(
        fill: fill,
        radius: radius,
        width: width,
        height: height,
        onTap: onTap,
        onHaptic: onHaptic,
        semanticLabel: semanticLabel,
        child: content,
      );
    }
    final card = FillBox(fill: fill, radius: radius, width: width, height: height, child: content);
    if (semanticLabel == null) return card;
    return Semantics(container: true, label: semanticLabel, child: card);
  }
}

/// Confetti: small rotated clay badges (gradient + 2 pt edge) in the six
/// fills, at fixed normalized positions (top edge and right half). Plain
/// fills, no blur, so they paint directly.
class ConfettiPainter extends CustomPainter {
  ConfettiPainter({this.seed = 0, this.count = 8, this.exclude});

  final int seed;
  final int count;

  /// A fill to skip (the card's own colour).
  final JwFill? exclude;

  static const int maxPieces = 10;

  // x, y (fractions of the box), width, height (pt), rotation (rad).
  // Kept to the top edge and the right half, where hero text rarely sits.
  static const List<(double, double, double, double, double)> _pieces = [
    (0.66, 0.08, 10, 14, 0.50),
    (0.86, 0.17, 12, 17, -0.62),
    (0.50, 0.07, 8, 11, -0.10),
    (0.93, 0.47, 15, 10, -0.45),
    (0.74, 0.36, 7, 12, 0.0),
    (0.80, 0.74, 11, 15, 0.20),
    (0.60, 0.55, 9, 13, 0.35),
    (0.95, 0.86, 10, 13, 0.30),
    (0.64, 0.90, 8, 11, -0.40),
    (0.30, 0.06, 9, 12, 0.75),
  ];


  @override
  void paint(Canvas canvas, Size size) {
    final fills = [for (final f in JwFill.all) if (!identical(f, exclude)) f];
    final n = math.min(count, maxPieces);
    for (var i = 0; i < n; i++) {
      final (x, y, w, h, rot) = _pieces[i];
      final f = fills[(i + seed) % fills.length];
      final rect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
      final r = Radius.circular(math.min(w, h) * 0.38);
      canvas
        ..save()
        ..translate(size.width * x, size.height * y)
        ..rotate(rot)
        ..drawRRect(RRect.fromRectAndRadius(rect.shift(const Offset(0, 2)), r), Paint()..color = f.edge)
        ..drawRRect(RRect.fromRectAndRadius(rect, r), Paint()..shader = JwFills.gradient(f).createShader(rect))
        ..restore();
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter old) => old.seed != seed || old.count != count || !identical(old.exclude, exclude);
}
