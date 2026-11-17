import 'package:flutter/widgets.dart';

import '../../board/tile/tile_face_spec.dart';
import '../../board/tile/tile_widget.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';

/// Design frame of the illustration card (pt); children are placed in this
/// space and scaled with the card.
const Size kIllustrationFrame = Size(342, 400);

/// A real tile placed at [left]/[top] in frame coordinates.
class _Placed extends StatelessWidget {
  const _Placed({required this.s, required this.left, required this.top, required this.child});

  final double s;
  final double left;
  final double top;
  final Widget child;

  @override
  Widget build(BuildContext context) => Positioned(left: left * s, top: top * s, child: child);
}

/// Centred label at frame x [cx] (frame units), y [top].
class _Label extends StatelessWidget {
  const _Label({required this.s, required this.cx, required this.top, required this.text, this.width = 120});

  final double s;
  final double cx;
  final double top;
  final String text;
  final double width;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Positioned(
      left: (cx - width / 2) * s,
      top: top * s,
      width: width * s,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: jw.text.callout.copyWith(fontSize: 15.5 * s, fontWeight: FontWeight.w400, height: 1.3),
      ),
    );
  }
}

/// Green check / red cross disc.
class _Verdict extends StatelessWidget {
  const _Verdict({required this.s, required this.cx, required this.cy, required this.ok});

  final double s;
  final double cx;
  final double cy;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final d = 26 * s;
    return Positioned(
      left: cx * s - d / 2,
      top: cy * s - d / 2,
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.chip, color: ok ? jw.success : jw.danger),
        child: SizedBox.square(
          dimension: d,
          child: Center(child: JwIcon(ok ? JwIcons.check : JwIcons.x, size: 15 * s, color: jw.onAccent)),
        ),
      ),
    );
  }
}

/// Accent-soft pill badge centred at the top or bottom of the frame.
class _Badge extends StatelessWidget {
  const _Badge({required this.s, required this.top, required this.text, this.icon});

  final double s;
  final double top;
  final String text;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Positioned(
      left: 0,
      right: 0,
      top: top * s,
      child: Center(
        child: DecoratedBox(
          decoration: jw.clay(ClayLevel.flat, color: jw.accentSoft, radius: 15 * s),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 6 * s),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[JwIcon(icon!, size: 16 * s, color: jw.textPrimary), SizedBox(width: 10 * s)],
                Text(text, style: jw.text.callout.copyWith(fontSize: 15.5 * s, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Page 1: a selected 5-circles tile, its playable twin and two blocked tiles.
class MatchIllustration extends StatelessWidget {
  const MatchIllustration({super.key, required this.faces, required this.s, required this.badge});

  final List<TileFaceSpec> faces;
  final double s;
  final String badge;

  @override
  Widget build(BuildContext context) {
    final t = 1.75 * s;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _Badge(s: s, top: 40, text: badge),
        _Placed(s: s, left: 90, top: 120, child: TileWidget(face: faces[4], state: TileVisualState.selected, scale: t)),
        _Placed(s: s, left: 214, top: 152, child: TileWidget(face: faces[4], scale: t)),
        _Placed(s: s, left: 120, top: 252, child: TileWidget(face: faces[22], state: TileVisualState.blocked, scale: t)),
        _Placed(s: s, left: 190, top: 272, child: TileWidget(face: faces[30], state: TileVisualState.blocked, scale: t)),
      ],
    );
  }
}

/// Labels for [FreeRuleIllustration].
class FreeRuleLabels {
  const FreeRuleLabels({
    required this.leftClear,
    required this.bothBlocked,
    required this.covered,
    required this.middle,
    required this.edge,
  });

  final String leftClear;
  final String bothBlocked;
  final String covered;
  final String middle;
  final String edge;
}

/// Page 2: playable vs blocked, with verdicts.
class FreeRuleIllustration extends StatelessWidget {
  const FreeRuleIllustration({super.key, required this.faces, required this.s, required this.labels});

  final List<TileFaceSpec> faces;
  final double s;
  final FreeRuleLabels labels;

  @override
  Widget build(BuildContext context) {
    final t = 1.5 * s;
    const blocked = TileVisualState.blocked;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Row: free (left edge open) · blocked (both sides) · free.
        _Placed(s: s, left: 26, top: 70, child: TileWidget(face: faces[10], scale: t)),
        _Placed(s: s, left: 77, top: 70, child: TileWidget(face: faces[13], state: blocked, scale: t)),
        _Placed(s: s, left: 128, top: 70, child: TileWidget(face: faces[14], scale: t)),
        _Verdict(s: s, cx: 52, cy: 163, ok: true),
        _Label(s: s, cx: 52, top: 180, text: labels.leftClear, width: 74),
        _Verdict(s: s, cx: 128, cy: 163, ok: false),
        _Label(s: s, cx: 129, top: 180, text: labels.bothBlocked, width: 76),
        // Covered from above: a blocked tile under a free one.
        _Placed(s: s, left: 200, top: 82, child: TileWidget(face: faces[20], state: blocked, scale: t)),
        _Placed(s: s, left: 225, top: 72, child: TileWidget(face: faces[21], scale: t)),
        _Verdict(s: s, cx: 254, cy: 163, ok: false),
        _Label(s: s, cx: 254, top: 180, text: labels.covered),
        // A blocked middle row and a free edge tile.
        _Placed(s: s, left: 52, top: 220, child: TileWidget(face: faces[24], state: blocked, scale: t)),
        _Placed(s: s, left: 103, top: 220, child: TileWidget(face: faces[25], state: blocked, scale: t)),
        _Placed(s: s, left: 154, top: 220, child: TileWidget(face: faces[26], state: blocked, scale: t)),
        _Verdict(s: s, cx: 128, cy: 313, ok: false),
        _Label(s: s, cx: 128, top: 330, text: labels.middle, width: 150),
        _Placed(s: s, left: 252, top: 220, child: TileWidget(face: faces[9], scale: t)),
        _Verdict(s: s, cx: 284, cy: 313, ok: true),
        _Label(s: s, cx: 284, top: 330, text: labels.edge),
      ],
    );
  }
}

/// Page 3: a small mixed board of real tiles, free ones raised, blocked ones
/// sunk, with the "Guaranteed solution" badge.
class SolvableIllustration extends StatelessWidget {
  const SolvableIllustration({super.key, required this.faces, required this.s, required this.badge});

  final List<TileFaceSpec> faces;
  final double s;
  final String badge;

  /// Columns per row (tile units) of the bottom layer.
  static const _rows = <List<int>>[
    [1, 2, 3, 4, 5, 6],
    [0, 1, 2, 3, 4, 5],
    [1, 2],
    [0, 1, 2, 3, 4, 5, 6],
    [1, 2, 3, 4, 5],
    [2, 3],
    [0, 1, 2, 3, 4, 5, 6],
    [1, 2, 3, 4, 5],
  ];

  static final List<SilhouetteTile> positions = () {
    final out = <SilhouetteTile>[];
    for (var r = 0; r < _rows.length; r++) {
      for (final c in _rows[r]) {
        out.add(SilhouetteTile(c * 2, r * 2, 0));
      }
    }
    out
      ..addAll(const [SilhouetteTile(4, 6, 1), SilhouetteTile(6, 6, 1), SilhouetteTile(4, 8, 1), SilhouetteTile(6, 8, 1)])
      ..add(const SilhouetteTile(5, 7, 2));
    return out;
  }();

  /// The free rule: nothing above overlaps it, and not both sides taken.
  static bool isFree(SilhouetteTile t, List<SilhouetteTile> all) {
    var left = false, right = false;
    for (final o in all) {
      if (identical(o, t)) continue;
      final dx = o.x - t.x, dy = (o.y - t.y).abs();
      if (o.z == t.z + 1 && dx.abs() < 2 && dy < 2) return false;
      if (o.z == t.z && dy < 2) {
        if (dx == -2) left = true;
        if (dx == 2) right = true;
      }
    }
    return !(left && right);
  }

  @override
  Widget build(BuildContext context) {
    final t = 0.7 * s;
    final size = TileWidget.footprintFor(t, TileFaceSize.medium);
    const cols = 7, rows = 8;
    final boardW = cols * size.width, boardH = rows * size.height;
    final left0 = (kIllustrationFrame.width * s - boardW) / 2;
    final top0 = 60 * s + (250 * s - boardH) / 2;
    final layer = 6 * t;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (var i = 0; i < positions.length; i++)
          Positioned(
            left: left0 + positions[i].x / 2 * size.width,
            top: top0 + positions[i].y / 2 * size.height - positions[i].z * layer,
            child: TileWidget(
              face: faces[(i * 7 + 3) % faces.length],
              scale: t,
              state: isFree(positions[i], positions) ? TileVisualState.playable : TileVisualState.blocked,
            ),
          ),
        _Badge(s: s, top: 344, text: badge, icon: JwIcons.check),
      ],
    );
  }
}
