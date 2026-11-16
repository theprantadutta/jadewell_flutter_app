import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';

/// Row of three small stars; the first [earned] filled in accent.
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.earned, this.size = 12, this.gap = 2, this.semanticLabel});

  final int earned;
  final double size;
  final double gap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: gap),
            CustomPaint(
              size: Size.square(size),
              painter: _StarPainter(i < earned ? jw.accent : jw.tileBlockedEdge.withValues(alpha: jw.isDark ? 0.9 : 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}

class _StarPainter extends CustomPainter {
  _StarPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final outer = size.shortestSide / 2, inner = outer * 0.48;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.2,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = size.shortestSide * 0.12,
    );
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.color != color;
}

/// Accent check disc (cleared state).
class CheckDisc extends StatelessWidget {
  const CheckDisc({super.key, this.size = 22, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.chip, color: color ?? jw.accent),
      child: SizedBox.square(
        dimension: size,
        child: Center(child: JwIcon(JwIcons.check, size: size * 0.6, color: jw.isDark ? jw.onAccent : jw.surfaceHi)),
      ),
    );
  }
}

/// Small sunken track with an accent fill (resume state).
class MiniTrack extends StatelessWidget {
  const MiniTrack({super.key, required this.value, this.width = 54});

  final double value;
  final double width;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.sunken, radius: 4),
      child: SizedBox(
        width: width,
        height: 8,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: value.clamp(0.0, 1.0),
              child: DecoratedBox(
                decoration: BoxDecoration(color: jw.accent, borderRadius: BorderRadius.circular(2)),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Accent-soft pill label ("New", "Today · Sun 15 Nov").
class SoftPill extends StatelessWidget {
  const SoftPill({super.key, required this.label, this.expand = false, this.height = 26, this.style});

  final String label;
  final bool expand;
  final double height;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.flat, color: jw.accentSoft, radius: height / 2),
      child: SizedBox(
        height: height,
        width: expand ? double.infinity : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: expand ? Alignment.centerLeft : Alignment.center,
            widthFactor: expand ? null : 1,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style ?? jw.text.callout.copyWith(fontWeight: FontWeight.w600, fontSize: 14.5),
            ),
          ),
        ),
      ),
    );
  }
}
