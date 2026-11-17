import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../theme/clay.dart';
import '../../theme/jw_raster_cache.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../tile_motion.dart';
import 'tile_face_painter.dart';
import 'tile_face_spec.dart';
import 'tile_widget.dart';

/// Pre-rendered tile textures: clay (with its blurred shadows and edge) plus
/// glyphs, with the blocked look (glyph opacity and desaturation) baked in.
/// One texture per (face, visual state, theme, device scale), so a full board
/// is a few dozen textures drawn as plain quads: no per-tile blur, colour
/// filter or layer at frame time.
abstract final class TileRaster {
  /// The texture for [face] in [state], at [scale] device pixels per pt of
  /// the 1× tile (bucketed). Painted with its origin at the face box's
  /// top-left.
  static JwRaster? obtain(TileFaceSpec face, TileVisualState state, JwTheme jw, double scale) {
    final s = JwRasterCache.bucket(scale);
    final key = _TileKey(face.id, state, jw, s);
    final cache = JwRasterCache.instance;
    final hit = cache.peek(key);
    if (hit != null) return hit;
    final deco = TileVisual.decorationFor(state, jw);
    final box = Offset.zero & JwTile.face;
    final bounds = box.inflate(clayReach(deco.resolvedShadows) + 4);
    return cache.obtain(key, bounds, s, (canvas) => paintVisual(canvas, face, state, jw));
  }

  /// Paints the tile at 1× into the face box at the origin (clay, then the
  /// glyphs or the face-down panel). The clay comes from its own cached
  /// texture at the canvas scale, so the blurs run once per state, not once
  /// per face.
  static void paintVisual(Canvas canvas, TileFaceSpec face, TileVisualState state, JwTheme jw) {
    final box = Offset.zero & JwTile.face;
    TileVisual.decorationFor(state, jw).paintInto(canvas, box, devicePixelRatio: 1);
    final inner = box.deflate(JwTile.faceInset);
    if (state == TileVisualState.faceDown) {
      jw.clay(ClayLevel.sunken, radius: 6, color: jw.tileFace).paintInto(canvas, inner, devicePixelRatio: 1);
      return;
    }
    final blocked = state.isBlockedLook;
    canvas
      ..save()
      ..translate(inner.left, inner.top);
    TileFacePainter(
      face,
      glyphOpacity: blocked ? jw.blockedFaceOpacity : 1,
      saturation: blocked ? 0.35 : 1,
    ).paint(canvas, inner.size);
    canvas.restore();
  }

  /// Renders the playable and blocked textures of every face ahead of time
  /// (board loading), so the entry animation never waits on them.
  static void warm(Iterable<TileFaceSpec> faces, JwTheme jw, double scale) {
    for (final f in faces) {
      obtain(f, TileVisualState.playable, jw, scale);
      obtain(f, TileVisualState.blocked, jw, scale);
    }
  }
}

@immutable
class _TileKey {
  const _TileKey(this.face, this.state, this.jw, this.scale);
  final int face;
  final TileVisualState state;
  final JwTheme jw;
  final double scale;

  @override
  bool operator ==(Object other) =>
      other is _TileKey && other.face == face && other.state == state && identical(other.jw, jw) && other.scale == scale;

  @override
  int get hashCode => Object.hash(face, state, identityHashCode(jw), scale);
}

/// Paints one tile (sized [JwTile.face]) from [TileRaster] textures, with an
/// optional per-frame transform/opacity ([xf]) and crossfade from a previous
/// look ([fadeFrom] at 1 − [fade]). Motion only repaints this box: no widget
/// rebuild, no layout, and no layer (opacity is the texture's paint alpha).
class TilePaint extends LeafRenderObjectWidget {
  const TilePaint({
    super.key,
    required this.face,
    required this.state,
    required this.rasterScale,
    this.xf,
    this.fadeFrom,
    this.fade,
    this.outlineColor,
    this.flashColor,
    this.outlineEdge = JwTile.edge,
  });

  final TileFaceSpec face;
  final TileVisualState state;

  /// Device pixels per pt of the 1× tile, before the canvas transform (which
  /// is folded in when larger).
  final double rasterScale;
  final ValueListenable<TileXf>? xf;
  final (TileFaceSpec, TileVisualState)? fadeFrom;
  final ValueListenable<double>? fade;

  /// Blocker outline colour (2 pt, around face and edge); null for none.
  final Color? outlineColor;
  final double outlineEdge;

  /// Colour of the reduce-motion flash overlay.
  final Color? flashColor;

  @override
  RenderTilePaint createRenderObject(BuildContext context) => RenderTilePaint(
    face: face,
    state: state,
    jw: context.jw,
    rasterScale: rasterScale,
    xf: xf,
    fadeFrom: fadeFrom,
    fade: fade,
    outlineColor: outlineColor,
    outlineEdge: outlineEdge,
    flashColor: flashColor,
  )..devicePixelRatio = _dprOf(context);

  static double _dprOf(BuildContext context) =>
      MediaQuery.maybeDevicePixelRatioOf(context) ?? View.maybeOf(context)?.devicePixelRatio ?? 1;

  @override
  void updateRenderObject(BuildContext context, RenderTilePaint renderObject) {
    renderObject
      ..face = face
      ..state = state
      ..jw = context.jw
      ..rasterScale = rasterScale
      ..xf = xf
      ..fadeFrom = fadeFrom
      ..fade = fade
      ..outlineColor = outlineColor
      ..outlineEdge = outlineEdge
      ..flashColor = flashColor
      ..devicePixelRatio = _dprOf(context);
  }
}

class RenderTilePaint extends RenderBox {
  RenderTilePaint({
    required this._face,
    required this._state,
    required this._jw,
    required this._rasterScale,
    this._xf,
    this._fadeFrom,
    this._fade,
    this._outlineColor,
    this._outlineEdge = JwTile.edge,
    this._flashColor,
  });

  TileFaceSpec _face;
  set face(TileFaceSpec v) {
    if (v.id == _face.id) return;
    _face = v;
    markNeedsPaint();
  }

  TileVisualState _state;
  set state(TileVisualState v) {
    if (v == _state) return;
    _state = v;
    markNeedsPaint();
  }

  JwTheme _jw;
  set jw(JwTheme v) {
    if (identical(v, _jw)) return;
    _jw = v;
    markNeedsPaint();
  }

  double _rasterScale;
  set rasterScale(double v) {
    if (v == _rasterScale) return;
    _rasterScale = v;
    markNeedsPaint();
  }

  ValueListenable<TileXf>? _xf;
  set xf(ValueListenable<TileXf>? v) {
    if (identical(v, _xf)) return;
    if (attached) _xf?.removeListener(markNeedsPaint);
    _xf = v;
    if (attached) _xf?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  (TileFaceSpec, TileVisualState)? _fadeFrom;
  set fadeFrom((TileFaceSpec, TileVisualState)? v) {
    if (v == _fadeFrom) return;
    _fadeFrom = v;
    markNeedsPaint();
  }

  ValueListenable<double>? _fade;
  set fade(ValueListenable<double>? v) {
    if (identical(v, _fade)) return;
    if (attached) _fade?.removeListener(markNeedsPaint);
    _fade = v;
    if (attached) _fade?.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  Color? _outlineColor;
  set outlineColor(Color? v) {
    if (v == _outlineColor) return;
    _outlineColor = v;
    markNeedsPaint();
  }

  double _outlineEdge;
  set outlineEdge(double v) {
    if (v == _outlineEdge) return;
    _outlineEdge = v;
    markNeedsPaint();
  }

  Color? _flashColor;
  set flashColor(Color? v) {
    if (v == _flashColor) return;
    _flashColor = v;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _xf?.addListener(markNeedsPaint);
    _fade?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _xf?.removeListener(markNeedsPaint);
    _fade?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(JwTile.face);

  @override
  bool hitTestSelf(Offset position) => false;

  double _dpr = 1;
  set devicePixelRatio(double v) {
    if (v == _dpr) return;
    _dpr = v;
    markNeedsPaint();
  }

  double _deviceScale(Canvas canvas) {
    final s = canvasScale(canvas);
    return _dpr * (s > _rasterScale ? s : _rasterScale);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final xf = _xf?.value ?? TileXf.identity;
    if (xf.opacity <= 0) return;
    final canvas = context.canvas;
    final w = size.width, h = size.height;
    final scale = _deviceScale(canvas);

    canvas.save();
    final c = offset + Offset(w / 2, h / 2);
    final moved = xf.dx != 0 || xf.dy != 0 || xf.rot != 0 || xf.sx != 1 || xf.sy != 1;
    if (moved) {
      canvas
        ..translate(c.dx + xf.dx, c.dy + xf.dy)
        ..rotate(xf.rot)
        ..scale(xf.sx, xf.sy)
        ..translate(-w / 2, -h / 2);
    } else {
      canvas.translate(offset.dx, offset.dy);
    }

    final from = _fadeFrom;
    final t = from == null ? 1.0 : (_fade?.value ?? 1).clamp(0.0, 1.0);
    final extras = from != null || _outlineColor != null || xf.flash;
    // Several overlapping draws at opacity < 1 need a group to match a
    // layer's opacity; this is rare (an outlined or crossfading tile that is
    // also fading), so the common fade stays a single translucent quad.
    final group = extras && xf.opacity < 1;
    if (group) {
      canvas.saveLayer((Offset.zero & size).inflate(48), Paint()..color = Color.fromRGBO(0, 0, 0, xf.opacity));
    }
    final alpha = group ? 1.0 : xf.opacity;
    if (from != null && t < 1) _draw(canvas, from.$1, from.$2, scale, alpha);
    _draw(canvas, _face, _state, scale, alpha * t);
    final outline = _outlineColor;
    if (outline != null) {
      final r = Rect.fromLTWH(-2, -2, w + 4, h + 4 + _outlineEdge).deflate(1);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(JwTile.radius + 1)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = outline.withValues(alpha: outline.a * alpha),
      );
    }
    final flash = _flashColor;
    if (xf.flash && flash != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(JwTile.radius)),
        Paint()..color = flash.withValues(alpha: flash.a * alpha),
      );
    }
    if (group) canvas.restore();
    canvas.restore();
  }

  void _draw(Canvas canvas, TileFaceSpec face, TileVisualState state, double scale, double opacity) {
    if (opacity <= 0) return;
    final raster = TileRaster.obtain(face, state, _jw, scale);
    if (raster != null) {
      raster.paint(canvas, Offset.zero, opacity: opacity);
      return;
    }
    // Too large to cache (extreme zoom): paint directly.
    if (opacity < 1) {
      canvas.saveLayer((Offset.zero & size).inflate(48), Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    }
    TileRaster.paintVisual(canvas, face, state, _jw);
    if (opacity < 1) canvas.restore();
  }
}
