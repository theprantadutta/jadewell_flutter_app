import 'package:flutter/widgets.dart';

import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/reduce_motion.dart';
import 'tile_face_spec.dart';
import 'tile_paint.dart';

/// Visual states of a tile (DESIGN_SYSTEM §9).
enum TileVisualState {
  playable,
  blocked,
  selected,
  hinted,

  /// A blocked tile pointed out during a blocked tap (2 pt outline, pressed).
  blocker,

  /// Paused: face hidden behind a sunken inner panel.
  faceDown;

  /// Static y-lift in pt (positive = up). Hinted bobs 1.5…4.5 around 3.
  double get lift => switch (this) {
    TileVisualState.playable => JwTile.liftPlayable,
    TileVisualState.selected => JwTile.liftSelected,
    TileVisualState.hinted => 3,
    TileVisualState.blocker => -1.5,
    TileVisualState.blocked || TileVisualState.faceDown => 0,
  };

  bool get isBlockedLook => this == TileVisualState.blocked || this == TileVisualState.blocker;
}

/// In-app "Tile face size" setting: multiplies the tile footprint.
enum TileFaceSize {
  small(0.9),
  medium(1),
  large(1.12);

  const TileFaceSize(this.multiplier);
  final double multiplier;
}

/// The painted tile (face clay + glyphs) at 1× in a [JwTile.face] box, with
/// no transform. Drawn from a cached texture ([TileRaster]): one per face,
/// state and theme, rendered at the device pixel ratio × [rasterScale] (or
/// the canvas scale, when larger).
class TileVisual extends StatelessWidget {
  const TileVisual({super.key, required this.face, required this.state, this.rasterScale = 1});

  final TileFaceSpec face;
  final TileVisualState state;

  /// Scale the 1× tile is shown at (fitted boards, large previews), so the
  /// texture stays sharp under a parent transform that is composited.
  final double rasterScale;

  /// The clay decoration for [state] in theme [jw].
  static ClayDecoration decorationFor(TileVisualState state, JwTheme jw) {
    switch (state) {
      case TileVisualState.playable:
      case TileVisualState.faceDown:
        return jw.clay(ClayLevel.tile, radius: JwTile.radius);
      case TileVisualState.blocked:
        return jw.clay(ClayLevel.tileBlocked, radius: JwTile.radius);
      case TileVisualState.selected:
        return jw.clay(ClayLevel.tileLifted, radius: JwTile.radius);
      case TileVisualState.hinted:
        // Yellow ring + yellow glow (DESIGN_SYSTEM §9).
        return jw.clay(
          ClayLevel.tile,
          radius: JwTile.radius,
          extraShadows: [
            ...ClayLevel.tileRing(jw.tileHinted),
            ClayLevel.tileGlow(jw.tileHinted, jw.isDark ? 0.5 : 0.7),
          ],
        );
      case TileVisualState.blocker:
        return jw.clay(
          ClayLevel.tileBlocked,
          radius: JwTile.radius,
          extraShadows: [
            ClayShadow(0, 0, 0, 2, jw.textMuted),
            ClayShadow(0, 3, 0, 2, jw.textMuted),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) =>
      SizedBox.fromSize(size: JwTile.face, child: TilePaint(face: face, state: state, rasterScale: rasterScale));
}

/// A board tile: [TileVisual] inside a footprint (32 × 39 × scale), lifted by
/// the state's offset. Visual state and transform are separate: the visual
/// sits in its own [RepaintBoundary], and lift changes only move it.
///
/// [scale] is the board-fit scale; [faceSize] the in-app setting. Pass
/// [lift] to drive the y-offset from an external animation (board entry,
/// match exit); otherwise the state's lift animates (`quick`, springSoft)
/// and a hinted tile bobs, unless motion is reduced.
class TileWidget extends StatefulWidget {
  const TileWidget({
    super.key,
    required this.face,
    this.state = TileVisualState.playable,
    this.scale = 1,
    this.faceSize = TileFaceSize.medium,
    this.lift,
    this.reduceMotion,
    this.semanticLabel,
  });

  final TileFaceSpec face;
  final TileVisualState state;
  final double scale;
  final TileFaceSize faceSize;
  final double? lift;
  final bool? reduceMotion;
  final String? semanticLabel;

  /// Footprint in logical pixels for [scale] and [faceSize].
  static Size footprintFor(double scale, TileFaceSize faceSize) =>
      JwTile.footprint * (scale * faceSize.multiplier);

  @override
  State<TileWidget> createState() => _TileWidgetState();
}

class _TileWidgetState extends State<TileWidget> with SingleTickerProviderStateMixin {
  AnimationController? _bob;

  bool get _wantsBob =>
      widget.state == TileVisualState.hinted && widget.lift == null && !JwReduceMotion.of(context, widget.reduceMotion);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBob();
  }

  @override
  void didUpdateWidget(TileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncBob();
  }

  void _syncBob() {
    if (_wantsBob) {
      _bob ??= AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
        ..repeat(reverse: true);
    } else {
      _bob?.dispose();
      _bob = null;
    }
  }

  @override
  void dispose() {
    _bob?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = JwReduceMotion.of(context, widget.reduceMotion);
    final s = widget.scale * widget.faceSize.multiplier;
    final visual = RepaintBoundary(child: TileVisual(face: widget.face, state: widget.state, rasterScale: s));

    Widget lifted;
    if (widget.lift != null) {
      lifted = Transform.translate(offset: Offset(0, -widget.lift!), child: visual);
    } else if (_bob != null) {
      lifted = AnimatedBuilder(
        animation: _bob!,
        child: visual,
        builder: (context, child) {
          final t = Curves.easeInOut.transform(_bob!.value);
          return Transform.translate(offset: Offset(0, -(1.5 + 3 * t)), child: child);
        },
      );
    } else {
      lifted = TweenAnimationBuilder<double>(
        tween: Tween(end: widget.state.lift),
        duration: reduce ? Duration.zero : JwMotion.quick,
        curve: JwMotion.springSoft,
        child: visual,
        builder: (context, v, child) => Transform.translate(offset: Offset(0, -v), child: child),
      );
    }

    final blocked = widget.state.isBlockedLook;
    return Semantics(
      label: widget.semanticLabel ?? '${widget.face.name}${blocked ? ', blocked' : ''}',
      selected: widget.state == TileVisualState.selected,
      child: SizedBox.fromSize(
        size: JwTile.footprint * s,
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox.fromSize(
            size: JwTile.footprint,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: (JwTile.footprint.width - JwTile.face.width) / 2,
                  top: 0,
                  width: JwTile.face.width,
                  height: JwTile.face.height,
                  child: lifted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
