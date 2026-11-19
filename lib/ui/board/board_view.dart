import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../../engine/engine.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import '../widgets/reduce_motion.dart';
import 'board_geometry.dart';
import 'board_overlays.dart';
import 'board_tile.dart';
import 'tile/tile_face_spec.dart';
import 'tile/tile_paint.dart';
import 'tile/tile_widget.dart';
import 'tile_motion.dart';

/// The board: a [Stack] of positioned tiles in canonical (z, y, x) order, one
/// [RepaintBoundary] per tile, fitted to the available area (DESIGN_SYSTEM §4)
/// and centred.
///
/// State comes in as an immutable [GameState]; animations come from [events]
/// (the controller's stream). The board never holds game logic: taps go to
/// [onTileTap] and every animation is presentation only (MOTION_SPEC §6).
/// Input is blocked only during the first 60 % of the board entry.
class BoardView extends StatefulWidget {
  const BoardView({
    super.key,
    required this.game,
    required this.faces,
    this.events,
    this.onTileTap,
    this.dealId = 0,
    this.hint,
    this.faceDown = false,
    this.faceSize = TileFaceSize.medium,
    this.animateEntry = true,
    this.reduceMotion,
    this.padding = 12,
    this.onClearWaveDone,
  });

  final GameState game;

  /// All 42 faces, indexed by face id.
  final List<TileFaceSpec> faces;
  final Stream<GameEvent>? events;
  final ValueChanged<int>? onTileTap;

  /// Changes on every new deal or restart: the entry replays.
  final int dealId;

  /// Hinted pair (ring, glow and bob).
  final (int, int)? hint;

  /// Paused: every tile face-down.
  final bool faceDown;
  final TileFaceSize faceSize;
  final bool animateEntry;
  final bool? reduceMotion;

  /// Space kept free around the fitted board.
  final double padding;

  /// Called when the board-cleared ghost wave has played (or right after the
  /// final exit with reduced motion).
  final VoidCallback? onClearWaveDone;

  @override
  State<BoardView> createState() => BoardViewState();
}

typedef _TileInputs = ({
  List<TileFaceSpec> faces,
  int face,
  TileVisualState visual,
  bool reduce,
  bool exiting,
  bool outlined,
  Duration? faceFade,
  bool tappable,
});

class _Exit {
  _Exit(this.face, this.visual);
  final int face;
  final TileVisualState visual;
}

class BoardViewState extends State<BoardView> with TickerProviderStateMixin {
  late Layout _layout;
  late BoardGeometry _geo;
  late List<GlobalKey<BoardTileState>> _keys;
  late Int8List _shownFaces;
  late List<TileVisualState?> _lastVisual;
  final Map<int, List<TileEffect>> _pending = {};
  final Map<int, _Exit> _exiting = {};
  final Set<int> _lagBlocked = {};
  final Map<int, int> _outlined = {};
  int _outlineToken = 0;
  int? _mismatchFrom;
  bool _swapPending = false;
  Duration? _faceFade;
  bool _inputLocked = false;
  final List<Timer> _timers = [];
  StreamSubscription<GameEvent>? _sub;

  AnimationController? _boardFade;
  final List<BeadPuff> _puffs = [];
  final List<AnimationController> _puffControllers = [];
  late final ValueNotifier<int> _puffTick = ValueNotifier(0);
  AnimationController? _wave;
  late final ValueNotifier<double> _waveMs = ValueNotifier(0);
  Offset? _waveOrigin;
  Set<int>? _freeCache;
  GameState? _freeCacheFor;

  /// The last tile widget built per position, with the inputs it was built
  /// from. Handing Flutter the identical widget again skips that tile's
  /// rebuild, so a tap rebuilds the two or three tiles it changed instead of
  /// all of them (docs/PERFORMANCE.md).
  final Map<int, (_TileInputs, Widget)> _tileCache = {};

  /// One tap callback per position, so the callback is stable across builds.
  final Map<int, VoidCallback> _tapHandlers = {};

  bool get _reduce => JwReduceMotion.of(context, widget.reduceMotion);

  /// Whether taps are currently ignored (first 60 % of the entry).
  bool get inputLocked => _inputLocked;

  @override
  void initState() {
    super.initState();
    _resetBoard();
    _subscribe();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_needsEntry) {
      _needsEntry = false;
      _startEntry();
    }
  }

  bool _needsEntry = true;

  @override
  void didUpdateWidget(BoardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget;
    if (!identical(old.game.layout, widget.game.layout) || old.dealId != widget.dealId) {
      _cancelAll();
      _resetBoard();
      _startEntry();
    } else {
      if (!_swapPending) _shownFaces = Int8List.fromList(widget.game.faces);
      if (_mismatchFrom != null && widget.game.selected != old.game.selected) _mismatchFrom = null;
    }
    if (old.events != widget.events) {
      unawaited(_sub?.cancel());
      _subscribe();
    }
  }

  void _subscribe() => _sub = widget.events?.listen(_onEvent);

  void _resetBoard() {
    _layout = widget.game.layout;
    _geo = BoardGeometry(_layout);
    _keys = List.generate(_layout.length, (i) => GlobalKey<BoardTileState>(debugLabel: 'tile$i'));
    _lastVisual = List.filled(_layout.length, null);
    _shownFaces = Int8List.fromList(widget.game.faces);
    _pending.clear();
    _tileCache.clear();
    _exiting.clear();
    _lagBlocked.clear();
    _outlined.clear();
    _mismatchFrom = null;
    _swapPending = false;
    _faceFade = null;
    _waveOrigin = null;
  }

  void _cancelAll() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
    for (final c in _puffControllers) {
      c.dispose();
    }
    _puffControllers.clear();
    _puffs.clear();
    _wave?.dispose();
    _wave = null;
  }

  void _after(Duration d, VoidCallback f) {
    late Timer timer;
    timer = Timer(d, () {
      _timers.remove(timer);
      if (mounted) f();
    });
    _timers.add(timer);
  }

  // ---------------------------------------------------------------- entry

  void _startEntry() {
    _boardFade?.dispose();
    _boardFade = null;
    if (!widget.animateEntry) {
      _inputLocked = false;
      return;
    }
    if (_reduce) {
      _boardFade = AnimationController(vsync: this, duration: const Duration(milliseconds: 200))..forward();
      _inputLocked = false;
      return;
    }
    var total = Duration.zero;
    for (var i = 0; i < _layout.length; i++) {
      if (widget.game.removed.contains(i)) continue;
      final p = _layout.positions[i];
      final delay = EntryDrop.delayFor(layer: p.z, col: p.x / 2, row: p.y / 2, index: i);
      _play(i, EntryDrop(delay));
      if (delay + EntryDrop.length > total) total = delay + EntryDrop.length;
    }
    _inputLocked = true;
    _after(total * 0.6, () => setState(() => _inputLocked = false));
  }

  // --------------------------------------------------------------- events

  void _play(int pos, TileEffect effect) {
    final st = _keys[pos].currentState;
    if (st != null && st.mounted) {
      st.play(effect);
    } else {
      (_pending[pos] ??= []).add(effect);
    }
  }

  void _onEvent(GameEvent e) {
    if (!mounted) return;
    final reduce = _reduce;
    switch (e) {
      case Matched(:final a, :final b, :final freed):
        final g = widget.game;
        final alreadyApplied = g.removed.contains(a);
        final remainingAfter = alreadyApplied ? g.layout.length - g.tilesMatched : g.layout.length - g.tilesMatched - 2;
        final isFinal = remainingAfter == 0;
        final ca = _geo.faceCenter(a), cb = _geo.faceCenter(b);
        final mid = (ca + cb) / 2;
        for (final (p, c) in [(a, ca), (b, cb)]) {
          _exiting[p] = _Exit(_shownFaces[p], _lastVisual[p] ?? TileVisualState.playable);
          final TileEffect exit = reduce
              ? const FadeOut()
              : MatchExit(
                  travelX: (mid.dx - c.dx) * 0.55,
                  travelY: (mid.dy - c.dy) * 0.55,
                  scale: isFinal ? MatchExit.finalScale : 1,
                );
          _play(p, exit);
        }
        final exitLength = reduce ? const Duration(milliseconds: 150) : MatchExit.out * (isFinal ? MatchExit.finalScale : 1);
        _after(exitLength + const Duration(milliseconds: 20), () {
          setState(() {
            _exiting.remove(a);
            _exiting.remove(b);
          });
        });
        if (!reduce) {
          _startPuff(mid);
          if (freed.isNotEmpty) {
            _lagBlocked.addAll(freed);
            _after(const Duration(milliseconds: 540), () => setState(() => _lagBlocked.removeAll(freed)));
          }
        }
        if (isFinal) _after(exitLength, () => _startWave(mid));
        setState(() {});
      case Mismatch(:final a, :final b):
        if (!reduce) {
          _play(a, const Shake());
          _play(b, const Shake());
          setState(() => _mismatchFrom = a);
          _after(JwMotion.base, () {
            if (_mismatchFrom == a) setState(() => _mismatchFrom = null);
          });
        }
      case Blocked(:final tile, :final blockers):
        _play(tile, reduce ? const Flash() : const Wobble());
        final token = ++_outlineToken;
        for (final p in blockers) {
          if (!reduce) _play(p, const Press());
          _outlined[p] = token;
        }
        setState(() {});
        _after(const Duration(milliseconds: 780), () {
          setState(() => _outlined.removeWhere((_, t) => t == token));
        });
      case Shuffled(:final positions):
        _animateFaceChange(positions);
      case Undone(:final entry):
        switch (entry) {
          case MatchEntry(:final a, :final b):
            final effect = reduce ? const FadeIn() : const UndoPop();
            for (final p in [a, b]) {
              _lagBlocked.remove(p);
              if (_exiting.remove(p) != null) {
                _keys[p].currentState?.play(effect);
              } else {
                (_pending[p] ??= []).add(effect);
              }
            }
            setState(() {});
          case ShuffleEntry():
            _animateFaceChange([
              for (var i = 0; i < _layout.length; i++)
                if (!widget.game.removed.contains(i)) i,
            ]);
        }
      default:
        break;
    }
  }

  void _animateFaceChange(List<int> positions) {
    if (_reduce) {
      _faceFade = const Duration(milliseconds: 150);
      _swapPending = false;
      _after(const Duration(milliseconds: 200), () => _faceFade = null);
      return;
    }
    for (final p in positions) {
      _play(p, const ShuffleFlip());
    }
    _swapPending = true;
    _after(ShuffleFlip.half, () {
      setState(() {
        _swapPending = false;
        _shownFaces = Int8List.fromList(widget.game.faces);
      });
    });
  }

  void _startPuff(Offset mid) {
    final c = AnimationController(vsync: this, duration: BeadPuffPainter.duration);
    final puff = BeadPuff(mid, c);
    c.addListener(() => _puffTick.value++);
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _puffs.remove(puff);
        _puffControllers.remove(c);
        c.dispose();
      }
    });
    _puffs.add(puff);
    _puffControllers.add(c);
    c.forward();
  }

  void _startWave(Offset origin) {
    if (_reduce) {
      widget.onClearWaveDone?.call();
      return;
    }
    final centers = [for (var i = 0; i < _layout.length; i++) _geo.faceCenter(i)];
    final total = GhostWavePainter.totalMs(centers, origin);
    _wave?.dispose();
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: total.round()));
    c.addListener(() => _waveMs.value = c.value * total);
    c.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        widget.onClearWaveDone?.call();
      }
    });
    setState(() {
      _wave = c;
      _waveOrigin = origin;
    });
    c.forward();
  }

  double? _warmScale;
  JwTheme? _warmTheme;

  /// Renders the playable/blocked textures of every face before the first
  /// tiles paint (each is one clay texture plus glyphs, so this is cheap).
  void _warmTiles(BuildContext context, double rasterScale) {
    final jw = context.jw;
    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final s = dpr * rasterScale;
    if (s == _warmScale && identical(jw, _warmTheme)) return;
    _warmScale = s;
    _warmTheme = jw;
    TileRaster.warm(widget.faces, jw, s);
  }

  @override
  void dispose() {
    _cancelAll();
    unawaited(_sub?.cancel());
    _boardFade?.dispose();
    _puffTick.dispose();
    _waveMs.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- build

  Set<int> _free(GameState g) {
    if (!identical(_freeCacheFor, g)) {
      _freeCacheFor = g;
      _freeCache = g.freeTiles.toSet();
    }
    return _freeCache!;
  }

  TileVisualState _visualOf(int pos, GameState g, Set<int> free) {
    if (widget.faceDown) return TileVisualState.faceDown;
    final selected = g.selected;
    if (_mismatchFrom != null) {
      if (pos == _mismatchFrom) return TileVisualState.selected;
      if (pos == selected) return TileVisualState.playable;
    } else if (pos == selected) {
      return TileVisualState.selected;
    }
    final isFree = free.contains(pos) && !_lagBlocked.contains(pos);
    final h = widget.hint;
    if (h != null && (h.$1 == pos || h.$2 == pos) && free.contains(pos)) return TileVisualState.hinted;
    return isFree ? TileVisualState.playable : TileVisualState.blocked;
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final free = _free(g);
    final reduce = _reduce;
    final jw = context.jw;
    final tiles = <Widget>[];
    for (var i = 0; i < _layout.length; i++) {
      final exit = _exiting[i];
      if (g.removed.contains(i) && exit == null) {
        _lastVisual[i] = null;
        _tileCache.remove(i);
        continue;
      }
      final visual = exit?.visual ?? _visualOf(i, g, free);
      final faceId = exit?.face ?? _shownFaces[i];
      _lastVisual[i] = visual;
      final effects = _pending.remove(i);
      final inputs = (
        faces: widget.faces,
        face: faceId,
        visual: visual,
        reduce: reduce,
        exiting: exit != null,
        outlined: _outlined.containsKey(i) && exit == null,
        faceFade: _faceFade,
        tappable: exit == null && widget.onTileTap != null,
      );
      final cached = _tileCache[i];
      if (effects == null && cached != null && cached.$1 == inputs) {
        tiles.add(cached.$2);
        continue;
      }
      final origin = _geo.origins[i];
      final tile = Positioned(
        left: origin.dx,
        top: origin.dy,
        width: JwTile.footprint.width,
        height: JwTile.footprint.height,
        child: BoardTile(
          key: _keys[i],
          face: widget.faces[faceId],
          visual: visual,
          reduceMotion: reduce,
          exiting: inputs.exiting,
          outlined: inputs.outlined,
          faceFade: _faceFade,
          initialEffects: effects ?? const [],
          onTap: inputs.tappable ? _tapHandlers.putIfAbsent(i, () => () => widget.onTileTap?.call(i)) : null,
        ),
      );
      // A tile built with one-shot effects must not be reused as is.
      if (effects == null) {
        _tileCache[i] = (inputs, tile);
      } else {
        _tileCache.remove(i);
      }
      tiles.add(tile);
    }

    final tilesLeft = g.layout.length - g.tilesMatched;
    final showSlots = tilesLeft <= 12 && !widget.faceDown;
    final slots = <Rect>[
      if (showSlots)
        for (var i = 0; i < _layout.length; i++)
          if (_layout.positions[i].z == 0 && g.removed.contains(i) && !_exiting.containsKey(i))
            _geo.origins[i] + Offset((JwTile.footprint.width - JwTile.face.width) / 2, 0) & JwTile.face,
    ];

    final stack = SizedBox.fromSize(
      size: _geo.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: showSlots ? 1 : 0),
              duration: reduce ? Duration.zero : JwMotion.slow,
              curve: JwMotion.easeOutSoft,
              builder: (context, v, _) =>
                  CustomPaint(painter: GhostSlotsPainter(slots: slots, color: jw.textMuted, opacity: v)),
            ),
          ),
          AbsorbPointer(
            absorbing: _inputLocked,
            // Tiles paint cached textures; one boundary for the whole set
            // keeps their motion from repainting the rest of the screen.
            child: RepaintBoundary(
              child: SizedBox.fromSize(size: _geo.size, child: Stack(clipBehavior: Clip.none, children: tiles)),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: BeadPuffPainter(puffs: List.of(_puffs), colors: jw.colors, repaint: _puffTick),
              ),
            ),
          ),
          if (_wave != null && _waveOrigin != null)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: GhostWavePainter(
                    centers: [for (var i = 0; i < _layout.length; i++) _geo.faceCenter(i)],
                    origin: _waveOrigin!,
                    colors: jw.colors,
                    elapsed: _waveMs,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    Widget board = stack;
    if (_boardFade != null) board = FadeTransition(opacity: _boardFade!, child: board);

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = BoardFit.compute(constraints.biggest, _geo.size, faceSize: widget.faceSize, padding: widget.padding);
        // Zoomable boards get texture headroom for pinch-zoom.
        final rasterScale = fit.scale * (fit.zoomable ? 1.5 : 1);
        _warmTiles(context, rasterScale);
        final scaled = SizedBox(
          width: _geo.size.width * fit.scale,
          height: _geo.size.height * fit.scale,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: TileRasterScope(scale: rasterScale, child: board),
          ),
        );
        if (!fit.zoomable) return Center(child: scaled);
        return _ZoomableBoard(fit: fit, viewport: constraints.biggest, padding: widget.padding, child: scaled);
      },
    );
  }
}

/// Pan and pinch-zoom (up to 2×) for boards that do not fit at 0.8×.
class _ZoomableBoard extends StatefulWidget {
  const _ZoomableBoard({required this.fit, required this.viewport, required this.padding, required this.child});

  final BoardFit fit;
  final Size viewport;
  final double padding;
  final Widget child;

  @override
  State<_ZoomableBoard> createState() => _ZoomableBoardState();
}

class _ZoomableBoardState extends State<_ZoomableBoard> {
  final TransformationController _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      constrained: false,
      minScale: math.min(1, widget.fit.fitScale / widget.fit.scale),
      maxScale: BoardFit.maxZoom / widget.fit.scale,
      boundaryMargin: EdgeInsets.all(widget.padding * 4),
      child: Padding(
        padding: EdgeInsets.all(widget.padding),
        child: SizedBox(
          width: math.max(widget.viewport.width - 2 * widget.padding, 0),
          child: Center(child: widget.child),
        ),
      ),
    );
  }
}
