import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../engine/engine.dart';
import '../theme/jw_tokens.dart';
import 'tile/tile_widget.dart';

/// Tile positions of a layout at 1× (DESIGN_SYSTEM §4 and §8): footprint
/// 32 × 39, a tile on layer z drawn 6 pt higher per layer, no horizontal
/// offset. The content box is `cols × 32 + edge` by
/// `rows × 39 + layers × 6 + edge`.
@immutable
class BoardGeometry {
  const BoardGeometry._(this.origins, this.size, this.maxZ);

  factory BoardGeometry(Layout layout) {
    if (layout.length == 0) return BoardGeometry._(const [], Size.zero, 0);
    var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1, maxZ = 0;
    for (final p in layout.positions) {
      minX = math.min(minX, p.x);
      minY = math.min(minY, p.y);
      maxX = math.max(maxX, p.x);
      maxY = math.max(maxY, p.y);
      maxZ = math.max(maxZ, p.z);
    }
    final cols = (maxX - minX) / 2 + 1;
    final rows = (maxY - minY) / 2 + 1;
    final size = Size(
      cols * JwTile.footprint.width + JwTile.edge,
      rows * JwTile.footprint.height + maxZ * JwTile.layerStep + JwTile.edge,
    );
    final origins = [
      for (final p in layout.positions)
        Offset(
          (p.x - minX) * JwTile.footprint.width / 2 + JwTile.edge / 2,
          (p.y - minY) * JwTile.footprint.height / 2 + (maxZ - p.z) * JwTile.layerStep,
        ),
    ];
    return BoardGeometry._(List.unmodifiable(origins), size, maxZ);
  }

  /// Top-left of each position's footprint, by canonical index.
  final List<Offset> origins;

  /// Content size at 1×.
  final Size size;
  final int maxZ;

  /// Centre of the tile face of position [i] (at rest, before any lift).
  Offset faceCenter(int i) => origins[i] + Offset(JwTile.footprint.width / 2, JwTile.face.height / 2);

  /// Footprint rect of position [i].
  Rect footprint(int i) => origins[i] & JwTile.footprint;
}

/// Result of fitting a board into the area between the counters and the tray.
@immutable
class BoardFit {
  const BoardFit({required this.scale, required this.fitScale, required this.zoomable});

  /// Fits [content] (1× size) into [area] with [padding] on every side
  /// (DESIGN_SYSTEM §4): the scale never exceeds 1.25× and never drops below
  /// 0.8× (below that the board stays at 0.8× and pinch-zoom up to 2× is
  /// enabled instead). [faceSize] multiplies the footprint and the board
  /// re-fits around the resized tiles, so the clamp applies to that unit.
  /// [maxScale] defaults to the phone cap; tablets pass [tabletMaxScale] so
  /// the board fills the larger screen instead of floating small in the middle.
  factory BoardFit.compute(
    Size area,
    Size content, {
    TileFaceSize faceSize = TileFaceSize.medium,
    double padding = 12,
    double maxScale = BoardFit.maxScale,
  }) {
    final m = faceSize.multiplier;
    final availW = math.max(0.0, area.width - 2 * padding);
    final availH = math.max(0.0, area.height - 2 * padding);
    if (content.isEmpty || availW == 0 || availH == 0) return BoardFit(scale: m, fitScale: m, zoomable: false);
    final fit = math.min(availW / (content.width * m), availH / (content.height * m));
    final rel = fit.clamp(minScale, math.max(minScale, maxScale));
    return BoardFit(scale: rel * m, fitScale: fit * m, zoomable: fit < minScale);
  }

  static const double minScale = 0.8;
  static const double maxScale = 1.25;

  /// Upper bound on tablets (shortest screen side >= [tabletBreakpoint]).
  static const double tabletMaxScale = 2.2;

  /// Smallest iPad short side is 744 pt, largest phones ~440 pt.
  static const double tabletBreakpoint = 700;

  /// Pinch-zoom limit, as an absolute scale.
  static const double maxZoom = 2;

  /// Scale applied to the 1× board.
  final double scale;

  /// The scale that would fit exactly (may be below [scale] when zoomable).
  final double fitScale;

  /// The board does not fit at 0.8×: pan and pinch-zoom (up to 2×) are on.
  final bool zoomable;
}
