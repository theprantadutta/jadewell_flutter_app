import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_raster_cache.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import 'clay_pressable.dart';

/// One tile position on the half-tile grid (a tile covers [x, x+2) × [y, y+2)
/// on layer [z]), as in `assets/layouts/*.json`.
@immutable
class SilhouetteTile {
  const SilhouetteTile(this.x, this.y, this.z);

  factory SilhouetteTile.fromJson(Map<String, Object?> j) =>
      SilhouetteTile((j['x']! as num).toInt(), (j['y']! as num).toInt(), (j['z']! as num).toInt());

  final int x;
  final int y;
  final int z;
}

/// Layout silhouette in the mini clay style: every cell is a tiny tile
/// (`tileFace`, radius 2, 1.2 pt edge), higher layers shift up 1 pt per
/// level, the top layer is tinted `accentSoft`. [locked] draws it at 35%
/// (18% in dark, DESIGN_SYSTEM §11).
class JwSilhouette extends StatelessWidget {
  const JwSilhouette({super.key, required this.tiles, this.locked = false, this.semanticLabel});

  final List<SilhouetteTile> tiles;
  final bool locked;
  final String? semanticLabel;

  /// Alpha of a locked silhouette: 35 % light, 18 % dark.
  static double lockedOpacity(JwTheme jw) => jw.isDark ? 0.18 : 0.35;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    // Drawn from a cached texture (one per layout, size and theme): a full
    // silhouette is hundreds of blurred mini tiles. Locked is that texture at
    // 35 % (dark 18 %) alpha, the same as an opacity layer over a single image.
    final paint = CustomPaint(
      painter: _SilhouetteRasterPainter(
        tiles: tiles,
        colors: jw.colors,
        devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1,
        opacity: locked ? lockedOpacity(jw) : 1,
      ),
      size: Size.infinite,
    );
    return Semantics(
      image: true,
      label: semanticLabel,
      child: RepaintBoundary(child: paint),
    );
  }
}

class _SilhouetteRasterPainter extends CustomPainter {
  _SilhouetteRasterPainter({required this.tiles, required this.colors, required this.devicePixelRatio, required this.opacity});

  final List<SilhouetteTile> tiles;
  final JwColors colors;
  final double devicePixelRatio;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty || size.isEmpty) return;
    final scale = JwRasterCache.bucket(devicePixelRatio * math.max(1.0, canvasScale(canvas)));
    final raster = JwRasterCache.instance.obtain(
      _SilhouetteKey(tiles, size, colors, scale),
      (Offset.zero & size).inflate(3),
      scale,
      (c) => JwSilhouettePainter(tiles: tiles, colors: colors).paint(c, size),
    );
    if (raster != null) {
      raster.paint(canvas, Offset.zero, opacity: opacity);
      return;
    }
    if (opacity < 1) canvas.saveLayer(Offset.zero & size, JwBase.alphaPaint(opacity));
    JwSilhouettePainter(tiles: tiles, colors: colors).paint(canvas, size);
    if (opacity < 1) canvas.restore();
  }

  @override
  bool shouldRepaint(_SilhouetteRasterPainter old) =>
      !identical(old.tiles, tiles) ||
      old.colors != colors ||
      old.devicePixelRatio != devicePixelRatio ||
      old.opacity != opacity;
}

@immutable
class _SilhouetteKey {
  const _SilhouetteKey(this.tiles, this.size, this.colors, this.scale);
  final List<SilhouetteTile> tiles;
  final Size size;
  final JwColors colors;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is _SilhouetteKey &&
      identical(other.tiles, tiles) &&
      other.size == size &&
      identical(other.colors, colors) &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(identityHashCode(tiles), size, identityHashCode(colors), scale);
}

class JwSilhouettePainter extends CustomPainter {
  JwSilhouettePainter({required List<SilhouetteTile> tiles, required this.colors})
    : tiles = [...tiles]..sort((a, b) => a.z != b.z ? a.z - b.z : (a.y != b.y ? a.y - b.y : a.x - b.x));

  final List<SilhouetteTile> tiles;
  final JwColors colors;

  static const _edge = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    if (tiles.isEmpty) return;
    var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1, maxZ = 0;
    for (final t in tiles) {
      minX = math.min(minX, t.x);
      minY = math.min(minY, t.y);
      maxX = math.max(maxX, t.x + 2);
      maxY = math.max(maxY, t.y + 2);
      maxZ = math.max(maxZ, t.z);
    }
    // Half-cell size keeps the 32:39 tile aspect.
    final cols = (maxX - minX).toDouble();
    final rows = (maxY - minY).toDouble();
    final extraH = _edge + maxZ * 1.0;
    final unitW = math.min(size.width / cols, (size.height - extraH) / (rows * 39 / 32));
    final unitH = unitW * 39 / 32;
    final w = cols * unitW, h = rows * unitH + extraH;
    final origin = Offset((size.width - w) / 2, (size.height - h) / 2 + maxZ * 1.0);
    final gap = math.max(0.5, unitW * 0.16);

    final face = Paint();
    final edge = Paint()..color = colors.tileEdge;
    final top = Color.alphaBlend(
      colors.accentSoft.withValues(alpha: colors.accentSoft.a * (colors.accentSoft.a > 0.5 ? 0.75 : 1)),
      colors.tileFace,
    );
    final shadow = Paint()
      ..color = colors.shadow.withValues(alpha: colors.shadow.a * 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    for (final t in tiles) {
      final r = Rect.fromLTWH(
        origin.dx + (t.x - minX) * unitW + gap / 2,
        origin.dy + (t.y - minY) * unitH + gap / 2 - t.z * 1.0,
        2 * unitW - gap,
        2 * unitH - gap - _edge,
      );
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(2));
      canvas
        ..drawRRect(rr.shift(const Offset(0, _edge + 0.8)), shadow)
        ..drawRRect(rr.shift(const Offset(0, _edge)), edge);
      face.color = (maxZ > 0 && t.z == maxZ) ? top : colors.tileFace;
      canvas.drawRRect(rr, face);
    }
  }

  @override
  bool shouldRepaint(JwSilhouettePainter old) => old.colors != colors || old.tiles.length != tiles.length || !identical(old.tiles, tiles);
}

/// Layout card (DESIGN_SYSTEM §11): 172 × 196, radius 26, raised, padding
/// 10; a plate 104 tall (radius 20) holding [silhouette]; [name] 16/700;
/// [meta] caption; [stateRow] at the bottom. [plateFill] makes the plate a
/// Clay Pop coloured fill plate (`JwFills.plate(index)`) with a 4 pt base
/// edge; null keeps a sunken plate. [locked]: the whole card sunken, no
/// plate, silhouette at 35 % (dark 18 %; pass `locked: true` to the
/// [JwSilhouette] too, or use [JwLayoutCard.tiles]).
class JwLayoutCard extends StatelessWidget {
  const JwLayoutCard({
    super.key,
    required this.name,
    required this.silhouette,
    this.meta,
    this.stateRow,
    this.locked = false,
    this.onTap,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
    this.width = 172,
    this.height = 196,
    this.plateFill,
  });

  /// Convenience: builds the silhouette from tile positions.
  JwLayoutCard.tiles({
    super.key,
    required this.name,
    required List<SilhouetteTile> tiles,
    this.meta,
    this.stateRow,
    this.locked = false,
    this.onTap,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
    this.width = 172,
    this.height = 196,
    this.plateFill,
  }) : silhouette = JwSilhouette(tiles: tiles, locked: locked);

  final String name;
  final Widget silhouette;
  final String? meta;
  final Widget? stateRow;
  final bool locked;
  final VoidCallback? onTap;
  final VoidCallback? onHaptic;
  final String? semanticLabel;
  final bool? reduceMotion;
  final double width;

  /// Fixed height; null sizes the card from its content (give it a tight
  /// height from outside, e.g. an `IntrinsicHeight` row, to align cards).
  final double? height;

  /// Coloured plate fill; null keeps the sunken plate.
  final JwFill? plateFill;

  /// Plate height including its base edge.
  static const double plateHeight = 104;
  static const double _plateEdge = 4;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final deco = jw.clay(locked ? ClayLevel.sunken : ClayLevel.raised, radius: 26);
    final plate = plateFill;
    final Decoration? plateDeco = locked
        ? null
        : (plate == null ? jw.clay(ClayLevel.sunken, radius: 20) : jw.fill(plate, radius: 20, edge: _plateEdge, glow: false));
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The fill plate's edge paints below its box: the box is 100 tall
        // and the edge takes the plate to 104.
        SizedBox(
          height: plateHeight,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: plateHeight - _plateEdge,
              width: double.infinity,
              child: plateDeco == null
                  ? Padding(padding: const EdgeInsets.all(10), child: silhouette)
                  : DecoratedBox(
                      decoration: plateDeco,
                      child: Padding(padding: const EdgeInsets.all(10), child: silhouette),
                    ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: jw.text.button.copyWith(fontSize: 16.5, color: locked ? jw.textMuted : jw.textPrimary),
          ),
        ),
        if (meta != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, top: 1),
            child: Text(
              meta!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: jw.text.caption.copyWith(fontSize: 13.5, fontWeight: FontWeight.w400),
            ),
          ),
        // A minimum gap for content sizing; the rest goes above the state row.
        const SizedBox(height: 2),
        const Spacer(),
        if (stateRow != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: stateRow),
      ],
    );
    return ClayPressable(
      decoration: deco,
      pressedDecoration: locked ? deco : deco.copyWith(level: ClayLevel.pressed),
      onTap: onTap,
      onHaptic: onHaptic,
      semanticLabel: semanticLabel ?? [name, ?meta, if (locked) 'locked'].join(', '),
      reduceMotion: reduceMotion,
      pressedScale: locked ? 1 : 0.97,
      dimWhenDisabled: false,
      width: width,
      height: height,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 11),
      child: body,
    );
  }
}
