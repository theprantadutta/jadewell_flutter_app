import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/jw_mask.dart';

/// Fades a vertical scrollable out at its edges instead of cutting it off.
///
/// Top: content scrolled up is fully transparent for the first [topClear]
/// pixels (e.g. under the status bar), then ramps to opaque over [top]
/// pixels, so cards slide away softly under the status bar or a fixed
/// header. Bottom: the last [bottom] pixels ramp out above a fixed footer
/// (0 = no bottom fade).
///
/// The mask is an offscreen pass, so it is only pushed while there is
/// content hidden past a faded edge (scrolled away from the top, or more
/// below); at rest at the top of a short list the child paints directly and
/// costs nothing extra. The widget tree never changes shape, so the
/// scrollable keeps its state and any drag in progress.
class JwScrollFade extends StatefulWidget {
  const JwScrollFade({super.key, required this.child, this.topClear = 0, this.top = 28, this.bottom = 0});

  final Widget child;

  /// Height of the fully transparent band at the top.
  final double topClear;

  /// Height of the ramp from transparent to opaque below [topClear].
  final double top;

  /// Height of the ramp from opaque to transparent at the bottom (0 = none).
  final double bottom;

  @override
  State<JwScrollFade> createState() => _JwScrollFadeState();
}

class _JwScrollFadeState extends State<JwScrollFade> {
  bool _above = false;
  bool _below = false;

  bool _onMetrics(ScrollMetrics m) {
    if (m.axis == Axis.vertical) {
      final above = m.extentBefore > 0.5;
      final below = widget.bottom > 0 && m.extentAfter > 0.5;
      if (above != _above || below != _below) {
        setState(() {
          _above = above;
          _below = below;
        });
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => _FadeMask(
    top: _above ? widget.top : 0,
    topClear: _above ? widget.topClear : 0,
    bottom: _below ? widget.bottom : 0,
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
      child: NotificationListener<ScrollNotification>(onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics), child: widget.child),
    ),
  );
}

class _FadeMask extends SingleChildRenderObjectWidget {
  const _FadeMask({required this.top, required this.topClear, required this.bottom, super.child});

  final double top;
  final double topClear;
  final double bottom;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFadeMask(top, topClear, bottom);

  @override
  void updateRenderObject(BuildContext context, _RenderFadeMask renderObject) => renderObject.set(top, topClear, bottom);
}

class _RenderFadeMask extends RenderProxyBox {
  _RenderFadeMask(this._top, this._topClear, this._bottom);

  double _top;
  double _topClear;
  double _bottom;

  bool get _enabled => _top > 0 || _topClear > 0 || _bottom > 0;

  void set(double top, double topClear, double bottom) {
    if (top == _top && topClear == _topClear && bottom == _bottom) return;
    final wasEnabled = _enabled;
    _top = top;
    _topClear = topClear;
    _bottom = bottom;
    if (wasEnabled != _enabled) markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null && _enabled;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (!_enabled) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    final h = size.height <= 0 ? 1.0 : size.height;
    final a = (_topClear / h).clamp(0.0, 1.0);
    final b = ((_topClear + _top) / h).clamp(a, 1.0);
    final c = (1 - _bottom / h).clamp(b, 1.0);
    const clear = JwMask.clear, solid = JwMask.solid;
    final shader = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [clear, clear, solid, solid, _bottom > 0 ? clear : solid],
      stops: [0, a, b, c, 1],
    ).createShader(Offset.zero & size);
    final mask = (layer is ShaderMaskLayer ? layer! as ShaderMaskLayer : ShaderMaskLayer())
      ..shader = shader
      ..maskRect = offset & size
      ..blendMode = BlendMode.dstIn;
    layer = mask;
    context.pushLayer(mask, (ctx, o) => ctx.paintChild(child, o), offset);
  }
}
