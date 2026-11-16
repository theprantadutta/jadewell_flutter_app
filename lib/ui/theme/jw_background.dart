import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'jw_theme.dart';
import 'jw_tokens.dart';

/// Screen background: the radial gradient (bgTop → bgBottom, ellipse 130% ×
/// 70% centred at 50% / 30%) plus the two decorative clay orbs (large top
/// right, smaller bottom left). Paints edge to edge, behind safe areas.
class JwBackground extends StatelessWidget {
  const JwBackground({super.key, this.child, this.orbs = true});

  final Widget? child;

  /// Draw the decorative orbs.
  final bool orbs;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return CustomPaint(
      painter: JwBackgroundPainter(jw.colors, orbs: orbs),
      child: child,
    );
  }
}

/// Painter behind [JwBackground]; usable directly in other painters.
class JwBackgroundPainter extends CustomPainter {
  JwBackgroundPainter(this.colors, {this.orbs = true});

  final JwColors colors;
  final bool orbs;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..save()
      ..clipRect(rect);
    // Elliptical radial gradient: draw a unit-circle gradient under a scale.
    canvas
      ..save()
      ..translate(size.width * 0.5, size.height * 0.3)
      ..scale(size.width * 1.3, size.height * 0.7)
      ..drawPaint(
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            1,
            [colors.bgTop, colors.bgBottom],
          ),
      )
      ..restore();

    if (orbs) {
      final w = size.width;
      _orb(canvas, Offset(w * 0.9, w * 0.09), w * 0.2, 1);
      _orb(canvas, Offset(-w * 0.02, size.height * 0.84), w * 0.21, 0.55);
    }
    canvas.restore();
  }

  void _orb(Canvas canvas, Offset c, double r, double opacity) {
    final shadow = Paint()
      ..color = colors.shadow.withValues(alpha: colors.shadow.a * 0.55 * opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.18);
    canvas.drawCircle(c + Offset(0, r * 0.16), r * 0.98, shadow);
    final hi = colors.surfaceHi;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        c + Offset(-r * 0.32, -r * 0.4),
        r * 1.5,
        [
          hi.withValues(alpha: opacity),
          colors.surfaceRaised.withValues(alpha: opacity),
          colors.bgBottom.withValues(alpha: opacity * 0.9),
        ],
        const [0, 0.55, 1],
      );
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(JwBackgroundPainter old) => old.colors != colors || old.orbs != orbs;
}
