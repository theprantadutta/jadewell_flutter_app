import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../theme/jw_tokens.dart';

/// Six clay beads puffing 30 pt out of a match midpoint (MOTION_SPEC §2):
/// rotated 0°, 60°, … 300°, scale 0.3 → 0.9, opacity 1 → 0, 750 ms
/// easeOutSoft. Odd beads are accent, even beads tile-coloured.
class BeadPuffPainter extends CustomPainter {
  BeadPuffPainter({required this.puffs, required this.colors, required Listenable repaint}) : super(repaint: repaint);

  final List<BeadPuff> puffs;
  final JwColors colors;

  static const duration = Duration(milliseconds: 750);
  static const double distance = 30;
  static const double bead = 12;

  @override
  void paint(Canvas canvas, Size size) {
    for (final puff in puffs) {
      final p = puff.progress.value;
      if (p <= 0 || p >= 1) continue;
      final c = JwMotion.easeOutSoft.transform(p);
      final scale = ui.lerpDouble(0.3, 0.9, c)!;
      final opacity = 1 - c;
      for (var k = 0; k < 6; k++) {
        final angle = k * math.pi / 3;
        final offset = Offset(math.sin(angle), -math.cos(angle)) * (distance * c);
        final center = puff.center + offset;
        final odd = k.isOdd;
        _bead(
          canvas,
          center,
          bead * scale,
          odd ? [const Color(0xFFFFFFFF), colors.accentSoft, colors.accent] : [const Color(0xFFFFFFFF), colors.tileFace, colors.tileEdge],
          opacity,
        );
      }
    }
  }

  static void _bead(Canvas canvas, Offset c, double d, List<Color> stops, double opacity) {
    final r = d / 2;
    final paint = Paint()
      ..shader = ui.Gradient.radial(
        c + Offset(-0.3 * r, -0.4 * r),
        r * 1.3,
        [for (final s in stops) s.withValues(alpha: s.a * opacity)],
        const [0, 0.4, 1],
      );
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(BeadPuffPainter old) => old.puffs != puffs || old.colors != colors;
}

/// One running puff: its centre (board 1× coordinates) and progress 0…1.
class BeadPuff {
  BeadPuff(this.center, this.progress);
  final Offset center;
  final Animation<double> progress;
}

/// Board-cleared ghost wave (MOTION_SPEC §3): every tile position flashes as
/// a tile-coloured disc and drifts up 34 pt, 1100 ms easeOutSoft each,
/// delayed by the distance from the last pair × 1.2 ms/pt.
class GhostWavePainter extends CustomPainter {
  GhostWavePainter({required this.centers, required this.origin, required this.colors, required this.elapsed})
    : super(repaint: elapsed);

  final List<Offset> centers;
  final Offset origin;
  final JwColors colors;

  /// Milliseconds since the wave started.
  final ValueListenable<double> elapsed;

  static const each = 1100.0;
  static const double msPerPt = 1.2;
  static const double rise = 34;
  static const double disc = 22;

  /// Wave length for [centers] around [origin] (ms).
  static double totalMs(List<Offset> centers, Offset origin) =>
      centers.fold<double>(0, (m, c) => math.max(m, (c - origin).distance * msPerPt)) + each;

  @override
  void paint(Canvas canvas, Size size) {
    final now = elapsed.value;
    final shadow = Paint()
      ..color = colors.shadow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    for (final c in centers) {
      final t = (now - (c - origin).distance * msPerPt) / each;
      if (t <= 0 || t >= 1) continue;
      final e = JwMotion.easeOutSoft.transform(t);
      final opacity = (math.min(1.0, t * 6) * (1 - e)).clamp(0.0, 1.0);
      final center = c + Offset(0, -rise * e);
      final r = disc / 2 * (0.7 + 0.3 * e);
      canvas.drawCircle(center + const Offset(0, 3), r, shadow..color = colors.shadow.withValues(alpha: colors.shadow.a * opacity));
      canvas.drawCircle(
        center,
        r,
        Paint()
          ..shader = ui.Gradient.radial(
            center + Offset(-0.3 * r, -0.4 * r),
            r * 1.4,
            [
              const Color(0xFFFFFFFF).withValues(alpha: opacity),
              colors.tileFace.withValues(alpha: opacity),
              colors.tileEdge.withValues(alpha: opacity),
            ],
            const [0, 0.45, 1],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(GhostWavePainter old) => old.centers != centers || old.origin != origin || old.colors != colors;
}

/// Empty-slot outlines for removed ground-layer positions, shown as the
/// board nears its end (screen 05): 1.5 pt `textMuted` inset at 35 %.
class GhostSlotsPainter extends CustomPainter {
  GhostSlotsPainter({required this.slots, required this.color, required this.opacity});

  /// Face rects (board 1× coordinates).
  final List<Rect> slots;
  final Color color;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.35 * opacity);
    for (final r in slots) {
      canvas.drawRRect(RRect.fromRectAndRadius(r.deflate(0.75), const Radius.circular(JwTile.radius - 0.75)), paint);
    }
  }

  @override
  bool shouldRepaint(GhostSlotsPainter old) => old.slots != slots || old.color != color || old.opacity != opacity;
}
