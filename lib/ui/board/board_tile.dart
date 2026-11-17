import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import 'tile/tile_face_spec.dart';
import 'tile/tile_paint.dart';
import 'tile/tile_widget.dart';
import 'tile_motion.dart';

/// One tile on the board, at 1× inside its 32 × 39 footprint.
///
/// The tile is painted by one [TilePaint] box from cached textures; motion
/// only changes the transform and opacity it paints with (a repaint, no
/// rebuild or layer), driven by one [Ticker] that runs while an effect is
/// active (MOTION_SPEC §6). Visual-state changes
/// play their own transitions (select squash/lift, deselect, blocked ↔
/// playable crossfade with the settle inflate, re-block); one-shot effects
/// (entry, exit, shake, wobble, press, shuffle, undo) are started by the
/// board through [BoardTileState.play].
class BoardTile extends StatefulWidget {
  const BoardTile({
    super.key,
    required this.face,
    required this.visual,
    required this.reduceMotion,
    this.onTap,
    this.exiting = false,
    this.outlined = false,
    this.initialEffects = const [],
    this.faceFade,
    this.semanticLabel,
  });

  final TileFaceSpec face;
  final TileVisualState visual;
  final bool reduceMotion;
  final VoidCallback? onTap;

  /// Leaving the board: never hit-testable.
  final bool exiting;

  /// Blocker outline (2 pt `textMuted`) while a blocked tap points at it.
  final bool outlined;

  /// Effects to start as soon as the tile mounts (entry, undo pop-in).
  final List<TileEffect> initialEffects;

  /// When set, a face change crossfades over this long (reduce-motion
  /// shuffle); otherwise faces swap instantly (the normal shuffle swaps them
  /// at its flattened midpoint).
  final Duration? faceFade;
  final String? semanticLabel;

  @override
  State<BoardTile> createState() => BoardTileState();
}

class _Running {
  _Running(this.effect, this.start);
  final TileEffect effect;
  final Duration start;
}

class BoardTileState extends State<BoardTile> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_onTick);
  Duration _now = Duration.zero;
  final List<_Running> _running = [];
  _Running? _bob;
  late final ValueNotifier<TileXf> _xf = ValueNotifier(TileXf.identity);
  late double _rest = _restFor(widget.visual);

  // Crossfade from the previous look (blocked ↔ playable, face swap).
  (TileFaceSpec, TileVisualState)? _fadeFrom;
  Duration _fadeStart = Duration.zero;
  Duration _fadeLength = Duration.zero;
  Curve _fadeCurve = Curves.linear;
  late final ValueNotifier<double> _fade = ValueNotifier(1);

  static double _restFor(TileVisualState v) => switch (v) {
    TileVisualState.playable || TileVisualState.hinted => TileRest.playable,
    TileVisualState.selected => TileRest.selected,
    _ => TileRest.flat,
  };

  @override
  void initState() {
    super.initState();
    for (final e in widget.initialEffects) {
      play(e);
    }
    _syncBob();
    _publish();
  }

  @override
  void didUpdateWidget(BoardTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    final reduce = widget.reduceMotion;
    final from = old.visual, to = widget.visual;
    if (from != to) {
      final newRest = _restFor(to);
      final delta = _currentRestOffset() - newRest;
      _rest = newRest;
      final wasBlocked = from.isBlockedLook || from == TileVisualState.faceDown;
      final nowBlocked = to.isBlockedLook || to == TileVisualState.faceDown;
      _removeWhere((e) => e is RestShift);
      if (to == TileVisualState.selected) {
        if (!reduce) _add(RestShift.select(delta));
      } else if (from == TileVisualState.selected) {
        if (!reduce) _add(RestShift.deselect(delta));
      } else if (from == TileVisualState.blocked && to == TileVisualState.playable) {
        // Layers settling: colours 400 ms standard, inflate 550 ms springSoft.
        _crossfade(old, reduce ? JwMotion.instant : JwMotion.gentle, JwMotion.standard);
        if (!reduce) _add(const Settle());
      } else if (wasBlocked != nowBlocked && from != TileVisualState.blocker && to != TileVisualState.blocker) {
        _crossfade(old, reduce ? JwMotion.instant : JwMotion.gentle, JwMotion.standard);
        if (!reduce && delta != 0) _add(RestShift.settle(delta));
      } else if (!reduce && delta != 0 && to != TileVisualState.blocker && from != TileVisualState.blocker) {
        _add(RestShift.settle(delta));
      }
    } else if (old.face.id != widget.face.id && widget.faceFade != null) {
      _crossfade(old, widget.faceFade!, Curves.linear);
    }
    if (reduce && !old.reduceMotion) _removeWhere((e) => e is! FadeOut && e is! FadeIn && e is! Flash);
    _syncBob();
    _publish();
  }

  /// Starts [effect] now. Undo cancels a running exit.
  void play(TileEffect effect) {
    if (effect is UndoPop || effect is FadeIn) _removeWhere((e) => e.holdsEnd);
    if (effect is ShuffleFlip) _removeWhere((e) => e is ShuffleFlip);
    _add(effect);
    _publish();
  }

  void _add(TileEffect effect) {
    _ensureTicking();
    _running.add(_Running(effect, _now));
  }

  void _removeWhere(bool Function(TileEffect) test) => _running.removeWhere((r) => test(r.effect));

  void _ensureTicking() {
    if (!_ticker.isActive) {
      _now = Duration.zero;
      _ticker.start();
    }
  }

  void _syncBob() {
    final wants = widget.visual == TileVisualState.hinted && !widget.reduceMotion;
    if (wants && _bob == null) {
      _ensureTicking();
      _bob = _Running(const HintBob(), _now);
    } else if (!wants) {
      _bob = null;
    }
  }

  void _crossfade(BoardTile old, Duration length, Curve curve) {
    if (length == Duration.zero) return;
    _fadeFrom = (old.face, old.visual);
    _fadeLength = length;
    _fadeCurve = curve;
    _ensureTicking();
    _fadeStart = _now;
    _fade.value = 0;
  }

  /// The rest offset currently shown (rest plus any running rest shift).
  double _currentRestOffset() {
    var dy = _rest;
    for (final r in _running) {
      if (r.effect is RestShift) dy += r.effect.sample(_now - r.start).dy;
    }
    return dy;
  }

  void _onTick(Duration elapsed) {
    _now = elapsed;
    _publish();
    if (_running.isEmpty && _bob == null && _fadeFrom == null) _ticker.stop();
  }

  void _publish() {
    var xf = TileXf(dy: _rest);
    final done = <_Running>[];
    for (final r in _running) {
      final t = _now - r.start;
      final d = r.effect.duration;
      if (d != null && t >= d && !r.effect.holdsEnd) {
        done.add(r);
        continue;
      }
      xf = xf + r.effect.sample(t);
    }
    _running.removeWhere(done.contains);
    if (_bob != null) xf = xf + _bob!.effect.sample(_now - _bob!.start);
    _xf.value = xf;
    if (_fadeFrom != null) {
      final p = _fadeLength.inMicroseconds == 0 ? 1.0 : (_now - _fadeStart).inMicroseconds / _fadeLength.inMicroseconds;
      if (p >= 1) {
        _fade.value = 1;
        // Drop the old layer after this frame so the last blend still paints.
        final from = _fadeFrom;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted && identical(_fadeFrom, from)) setState(() => _fadeFrom = null);
        });
      } else {
        _fade.value = _fadeCurve.transform(p.clamp(0.0, 1.0));
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _xf.dispose();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final edge = widget.visual.isBlockedLook ? 3.0 : JwTile.edge;
    // One render box paints the tile texture under the per-frame transform
    // and opacity; ticks only repaint it (no rebuild, no layers).
    final moving = TilePaint(
      face: widget.face,
      state: widget.visual,
      rasterScale: TileRasterScope.of(context),
      xf: _xf,
      fadeFrom: _fadeFrom,
      fade: _fade,
      outlineColor: widget.outlined ? jw.textMuted : null,
      outlineEdge: edge,
      flashColor: jw.textPrimary.withValues(alpha: 0.28),
    );

    final faceLeft = (JwTile.footprint.width - JwTile.face.width) / 2;
    final blocked = widget.visual.isBlockedLook;
    return Semantics(
      label: widget.semanticLabel ?? '${widget.face.name}${blocked ? ', blocked' : ''}',
      selected: widget.visual == TileVisualState.selected,
      button: widget.onTap != null && !widget.exiting,
      excludeSemantics: true,
      onTap: widget.exiting ? null : widget.onTap,
      child: IgnorePointer(
        ignoring: widget.exiting,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: SizedBox.fromSize(
            size: JwTile.footprint,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: faceLeft,
                  top: 0,
                  width: JwTile.face.width,
                  height: JwTile.face.height,
                  child: moving,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Scale the board's 1× tiles are shown at (board fit × face size, plus
/// zoom headroom), so tile textures are rendered sharp for it.
class TileRasterScope extends InheritedWidget {
  const TileRasterScope({super.key, required this.scale, required super.child});

  final double scale;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TileRasterScope>()?.scale ?? 1;

  @override
  bool updateShouldNotify(TileRasterScope oldWidget) => oldWidget.scale != scale;
}
