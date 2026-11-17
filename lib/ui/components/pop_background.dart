import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/jw_raster_cache.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';

/// One decorative pastel sphere on a [PopBackground]: [center] as fractions
/// of the screen (x of the width, y of the height; values outside 0…1 sit
/// partly off-screen) and [radius] as a fraction of the screen width.
@immutable
class PopBlob {
  const PopBlob(this.fill, this.center, this.radius);

  final JwFill fill;
  final Offset center;
  final double radius;

  @override
  bool operator ==(Object other) =>
      other is PopBlob && identical(other.fill, fill) && other.center == center && other.radius == radius;

  @override
  int get hashCode => Object.hash(identityHashCode(fill), center, radius);
}

/// Blob placements per screen (DESIGN_SYSTEM §3: at most 4, at the edges,
/// never behind the board).
abstract final class PopBlobs {
  /// No blobs.
  static const none = <PopBlob>[];

  /// Default: big purple top-right, yellow left, pink right (cleared,
  /// collection, settings).
  static const standard = [
    PopBlob(JwFill.purple, Offset(0.93, 0.025), 0.2),
    PopBlob(JwFill.yellow, Offset(-0.03, 0.545), 0.13),
    PopBlob(JwFill.pink, Offset(1.0, 0.66), 0.09),
  ];

  /// Game board (screen 03): purple top-right behind the timer, yellow and
  /// mint on the left edge, pink bottom-right, all clear of the board.
  static const board = [
    PopBlob(JwFill.purple, Offset(0.97, 0.03), 0.17),
    PopBlob(JwFill.yellow, Offset(-0.02, 0.15), 0.085),
    PopBlob(JwFill.mint, Offset(-0.02, 0.73), 0.08),
    PopBlob(JwFill.pink, Offset(1.0, 0.8), 0.09),
  ];

  /// One sphere in each corner (splash, onboarding).
  static const corners = [
    PopBlob(JwFill.purple, Offset(0.95, 0.04), 0.19),
    PopBlob(JwFill.yellow, Offset(0.02, 0.2), 0.1),
    PopBlob(JwFill.mint, Offset(0.0, 0.86), 0.13),
    PopBlob(JwFill.sky, Offset(1.0, 0.93), 0.11),
  ];
}

/// Clay Pop screen background (DESIGN_SYSTEM §2–3): a linear gradient
/// `bgTop → bgBottom` (lavender, or indigo → plum in dark) plus up to four
/// static glossy pastel [blobs] (opacity 1 light, .42 dark). Paints edge to
/// edge behind safe areas.
///
/// Each blob is a cached texture ([JwRasterCache]) and the whole background
/// sits in its own [RepaintBoundary], so content above it never repaints it
/// and nothing is re-rendered per frame. Blobs never animate.
class PopBackground extends StatelessWidget {
  const PopBackground({super.key, this.child, this.blobs = PopBlobs.standard});

  final Widget? child;

  /// Blob placement for this screen ([PopBlobs]); at most 4 are drawn.
  final List<PopBlob> blobs;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final painter = PopBackgroundPainter(jw, blobs: blobs, devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context));
    // Sized like a childless CustomPaint (the parent's minimum, so tight
    // constraints fill the screen).
    if (child == null) return RepaintBoundary(child: CustomPaint(painter: painter));
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: painter))),
        child!,
      ],
    );
  }
}

/// Painter behind [PopBackground]; usable directly in other painters.
class PopBackgroundPainter extends CustomPainter {
  PopBackgroundPainter(this.jw, {this.blobs = PopBlobs.standard, this.devicePixelRatio});

  final JwTheme jw;
  final List<PopBlob> blobs;

  /// When set, blobs are drawn from cached textures at this ratio.
  final double? devicePixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas
      ..save()
      ..clipRect(rect)
      ..drawRect(
        rect,
        Paint()..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [jw.bgTop, jw.bgBottom]),
      );
    for (final b in blobs.take(4)) {
      final r = b.radius * size.width;
      _blob(canvas, Offset(b.center.dx * size.width, b.center.dy * size.height), r, b.fill);
    }
    canvas.restore();
  }

  void _blob(Canvas canvas, Offset c, double r, JwFill fill) {
    final opacity = jw.blobOpacity;
    final dpr = devicePixelRatio;
    if (dpr != null) {
      final scale = JwRasterCache.bucket(dpr * math.max(1.0, canvasScale(canvas)));
      final raster = JwRasterCache.instance.obtain(
        _BlobKey(fill, r, scale),
        Rect.fromCircle(center: Offset.zero, radius: r + 2),
        scale,
        (canvas) => paintBlob(canvas, Offset.zero, r, fill),
      );
      if (raster != null) {
        raster.paint(canvas, c, opacity: opacity);
        return;
      }
    }
    if (opacity < 1) canvas.saveLayer(Rect.fromCircle(center: c, radius: r + 2), JwBase.alphaPaint(opacity));
    paintBlob(canvas, c, r, fill);
    if (opacity < 1) canvas.restore();
  }

  /// A glossy pastel sphere of radius [r] at [c]: a radial body (lit
  /// top-left, deepening toward the fill's mid at the rim) and a soft
  /// specular spot.
  static void paintBlob(Canvas canvas, Offset c, double r, JwFill fill) {
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-0.34 * r, -0.4 * r),
          r * 1.45,
          [JwFaceInks.lighten(fill.top, 0.6), JwFaceInks.lighten(fill.top, 0.15), fill.top, Color.lerp(fill.top, fill.mid, 0.7)!],
          const [0, 0.3, 0.7, 1],
        ),
    );
    final spot = c + Offset(-0.36 * r, -0.42 * r);
    canvas.drawCircle(
      spot,
      r * 0.42,
      Paint()
        ..shader = ui.Gradient.radial(
          spot,
          r * 0.42,
          [JwBase.white.withValues(alpha: 0.7), JwBase.white.withValues(alpha: 0)],
        ),
    );
  }

  @override
  bool shouldRepaint(PopBackgroundPainter old) =>
      !identical(old.jw, jw) || !listEquals(old.blobs, blobs) || old.devicePixelRatio != devicePixelRatio;
}

@immutable
class _BlobKey {
  const _BlobKey(this.fill, this.r, this.scale);
  final JwFill fill;
  final double r, scale;

  @override
  bool operator ==(Object other) => other is _BlobKey && identical(other.fill, fill) && other.r == r && other.scale == scale;

  @override
  int get hashCode => Object.hash(identityHashCode(fill), r, scale);
}
