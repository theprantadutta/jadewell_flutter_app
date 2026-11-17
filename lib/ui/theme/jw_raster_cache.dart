import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// A pre-rendered surface: [image] covers [bounds] (logical pixels, relative
/// to the origin the surface is painted at) at [scale] device pixels per
/// logical pixel.
class JwRaster {
  JwRaster._(this.image, this.bounds, this.scale);

  final ui.Image image;
  final Rect bounds;
  final double scale;

  int get bytes => image.width * image.height * 4;

  /// Destination rect for painting at [origin]: exactly one texel per device
  /// pixel at [scale].
  Rect destAt(Offset origin) => Rect.fromLTWH(
    origin.dx + bounds.left,
    origin.dy + bounds.top,
    image.width / scale,
    image.height / scale,
  );

  Rect get _src => Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  /// Draws the surface at [origin]. [opacity] < 1 draws it translucent (one
  /// textured quad, no layer).
  void paint(Canvas canvas, Offset origin, {double opacity = 1}) {
    if (opacity <= 0) return;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (opacity < 1) paint.color = Color.fromRGBO(0, 0, 0, opacity);
    canvas.drawImageRect(image, _src, destAt(origin), paint);
  }
}

/// Byte-bounded LRU of rasterized surfaces (clay, tiles, silhouettes).
///
/// Impeller has no raster cache: a recorded [ui.Picture] that blurs (clay
/// shadows) re-runs every blur on the GPU each frame it is drawn. Rendering
/// such pictures once into a texture ([ui.Picture.toImageSync]) and drawing
/// that texture instead turns dozens of offscreen blur passes per frame into
/// plain textured quads. Keys must capture everything that changes the
/// pixels (size, colours, state, device scale).
///
/// Evicted images are disposed; pictures that still reference them keep the
/// texture alive until they are dropped. The cache empties itself on memory
/// pressure.
class JwRasterCache with WidgetsBindingObserver {
  JwRasterCache._();

  static final JwRasterCache instance = JwRasterCache._();

  /// Upper bound for all cached textures together.
  int maxBytes = 96 << 20;

  /// Surfaces larger than this many device pixels are not cached (callers
  /// paint them directly).
  static const int maxPixels = 2600 * 2600;

  final LinkedHashMap<Object, JwRaster> _entries = LinkedHashMap();
  int _bytes = 0;
  bool _observing = false;

  /// Test hook: number of images rendered since start.
  int renderCount = 0;

  int get length => _entries.length;
  int get bytes => _bytes;

  /// Quantizes a device scale up to the next 1/8 so tiny transform jitter
  /// (springs, fitted boards) reuses one texture.
  static double bucket(double scale) => math.max(0.25, (scale * 8).ceil() / 8);

  /// The cached raster for [key], or null.
  JwRaster? peek(Object key) {
    final hit = _entries.remove(key);
    if (hit != null) _entries[key] = hit;
    return hit;
  }

  /// The raster for [key], rendering [bounds] (logical) at [scale] with
  /// [paint] on a miss. Returns null when the surface is too large to cache.
  JwRaster? obtain(Object key, Rect bounds, double scale, void Function(Canvas canvas) paint) {
    final hit = peek(key);
    if (hit != null) return hit;
    final w = (bounds.width * scale).ceil();
    final h = (bounds.height * scale).ceil();
    if (w <= 0 || h <= 0 || w * h > maxPixels) return null;
    _observe();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..scale(scale)
      ..translate(-bounds.left, -bounds.top);
    paint(canvas);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    renderCount++;
    final raster = JwRaster._(image, bounds, scale);
    _entries[key] = raster;
    _bytes += raster.bytes;
    while (_bytes > maxBytes && _entries.length > 1) {
      final oldest = _entries.keys.first;
      _drop(oldest);
    }
    return raster;
  }

  void _drop(Object key) {
    final r = _entries.remove(key);
    if (r == null) return;
    _bytes -= r.bytes;
    r.image.dispose();
  }

  /// Disposes every cached texture.
  void clear() {
    for (final r in _entries.values) {
      r.image.dispose();
    }
    _entries.clear();
    _bytes = 0;
  }

  void _observe() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didHaveMemoryPressure() => clear();
}

/// Largest axis scale of [canvas]'s current transform (1 when it has none).
double canvasScale(Canvas canvas) {
  final m = canvas.getTransform();
  final sx = math.sqrt(m[0] * m[0] + m[1] * m[1]);
  final sy = math.sqrt(m[4] * m[4] + m[5] * m[5]);
  final s = math.max(sx, sy);
  return s.isFinite && s > 0 ? s : 1;
}
