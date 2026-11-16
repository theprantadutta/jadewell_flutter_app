import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import '../theme/jw_tokens.dart';

/// The per-frame transform of one tile: translation (pt, CSS convention:
/// negative y is up), scale about the face centre, rotation (radians),
/// opacity, and an optional dark flash (reduce-motion blocked tap).
@immutable
class TileXf {
  const TileXf({this.dx = 0, this.dy = 0, this.sx = 1, this.sy = 1, this.rot = 0, this.opacity = 1, this.flash = false});

  static const identity = TileXf();

  final double dx, dy, sx, sy, rot, opacity;
  final bool flash;

  /// Combines two contributions: translations and rotations add, scales and
  /// opacities multiply.
  TileXf operator +(TileXf o) => TileXf(
    dx: dx + o.dx,
    dy: dy + o.dy,
    sx: sx * o.sx,
    sy: sy * o.sy,
    rot: rot + o.rot,
    opacity: opacity * o.opacity,
    flash: flash || o.flash,
  );

  @override
  bool operator ==(Object other) =>
      other is TileXf &&
      other.dx == dx &&
      other.dy == dy &&
      other.sx == sx &&
      other.sy == sy &&
      other.rot == rot &&
      other.opacity == opacity &&
      other.flash == flash;

  @override
  int get hashCode => Object.hash(dx, dy, sx, sy, rot, opacity, flash);

  @override
  String toString() => 'TileXf(dx $dx, dy $dy, s $sx×$sy, rot $rot, op $opacity${flash ? ', flash' : ''})';
}

/// One keyframe at [t] (0…1), CSS-style: every property interpolates between
/// neighbouring frames with the timing curve applied per segment.
@immutable
class Keyframe {
  const Keyframe(this.t, {this.dx = 0, this.dy = 0, this.sx = 1, this.sy = 1, this.rot = 0, this.opacity = 1});

  final double t, dx, dy, sx, sy, rot, opacity;
}

/// Samples [frames] at progress [t] (clamped) with [curve] per segment.
TileXf sampleKeyframes(List<Keyframe> frames, double t, Curve curve) {
  if (t <= frames.first.t) return _xf(frames.first);
  if (t >= frames.last.t) return _xf(frames.last);
  var i = 0;
  while (i < frames.length - 2 && t > frames[i + 1].t) {
    i++;
  }
  final a = frames[i], b = frames[i + 1];
  final local = b.t == a.t ? 1.0 : ((t - a.t) / (b.t - a.t)).clamp(0.0, 1.0);
  final c = curve.transform(local);
  double l(double x, double y) => lerpDouble(x, y, c)!;
  return TileXf(
    dx: l(a.dx, b.dx),
    dy: l(a.dy, b.dy),
    sx: l(a.sx, b.sx),
    sy: l(a.sy, b.sy),
    rot: l(a.rot, b.rot),
    opacity: l(a.opacity, b.opacity).clamp(0.0, 1.0),
  );
}

TileXf _xf(Keyframe k) => TileXf(dx: k.dx, dy: k.dy, sx: k.sx, sy: k.sy, rot: k.rot, opacity: k.opacity);

const double _deg = math.pi / 180;

/// Rest y-offset of a tile per visual (DESIGN_SYSTEM §8), CSS convention.
abstract final class TileRest {
  static const double playable = -JwTile.liftPlayable;
  static const double selected = -JwTile.liftSelected;
  static const double flat = 0;
}

/// A transient tile effect (MOTION_SPEC §2–§3). [sample] gets the time since
/// the effect started (may be negative while delayed) and returns its
/// contribution, relative to the tile's rest offset.
sealed class TileEffect {
  const TileEffect();

  /// Total length; null loops until removed.
  Duration? get duration;

  TileXf sample(Duration t);

  /// Exit effects keep the tile hidden at the end instead of snapping back.
  bool get holdsEnd => false;

  static double _p(Duration t, Duration d) => d.inMicroseconds == 0 ? 1 : (t.inMicroseconds / d.inMicroseconds).clamp(0.0, 1.0);
}

/// Moves from a previous rest offset to the current one: select (400 ms
/// springPop with the 1.04 × 0.94 squash), deselect (350 ms springSoft),
/// re-block (400 ms standard).
class RestShift extends TileEffect {
  const RestShift({required this.fromDelta, required this.duration, required this.curve, this.squash = false});

  /// Old rest minus new rest (pt).
  final double fromDelta;
  @override
  final Duration duration;
  final Curve curve;
  final bool squash;

  static RestShift select(double fromDelta) =>
      RestShift(fromDelta: fromDelta, duration: JwMotion.gentle, curve: JwMotion.springPop, squash: true);

  static RestShift deselect(double fromDelta) =>
      RestShift(fromDelta: fromDelta, duration: const Duration(milliseconds: 350), curve: JwMotion.springSoft);

  static RestShift settle(double fromDelta) =>
      RestShift(fromDelta: fromDelta, duration: JwMotion.gentle, curve: JwMotion.standard);

  @override
  TileXf sample(Duration t) {
    final c = curve.transform(TileEffect._p(t, duration));
    return TileXf(
      dy: fromDelta * (1 - c),
      sx: squash ? lerpDouble(1.04, 1, c)! : 1,
      sy: squash ? lerpDouble(0.94, 1, c)! : 1,
    );
  }
}

/// Board entry: falls 42 pt, opacity 0 → 1 in the first 60 %, landing
/// squash (1.04, 0.95) → (0.99, 1.01) → rest. 700 ms dropIn per segment,
/// after [delay]. Offsets are relative to the playable rest (−1.5).
class EntryDrop extends TileEffect {
  const EntryDrop(this.delay);

  final Duration delay;
  static const length = Duration(milliseconds: 700);

  static const frames = [
    Keyframe(0, dy: -40.5, opacity: 0),
    Keyframe(0.6, dy: 3.5, sx: 1.04, sy: 0.95),
    Keyframe(0.8, dy: 0.5, sx: 0.99, sy: 1.01),
    Keyframe(1),
  ];

  /// MOTION_SPEC §3: `layer × 250 + (col + row) × 9 + (index × 53 mod 5) × 8` ms.
  static Duration delayFor({required int layer, required double col, required double row, required int index}) =>
      Duration(microseconds: ((layer * 250 + (col + row) * 9 + (index * 53 % 5) * 8) * 1000).round());

  @override
  Duration get duration => delay + length;

  @override
  TileXf sample(Duration t) => sampleKeyframes(frames, TileEffect._p(t - delay, length), JwMotion.dropIn);
}

/// Matched exit: travel 55 % toward the pair's midpoint (320 ms travel) and,
/// in parallel, rise with a squash then shrink and fade (520 ms exit). The
/// final pair plays at 800 ms ([scale] ≈ 1.54).
class MatchExit extends TileEffect {
  const MatchExit({required this.travelX, required this.travelY, this.scale = 1});

  /// Final pair: 800 ms instead of 520 ms.
  static const double finalScale = 800 / 520;

  final double travelX, travelY, scale;

  static const travel = Duration(milliseconds: 320);
  static const out = Duration(milliseconds: 520);

  static const frames = [
    Keyframe(0),
    Keyframe(0.45, dy: -4, sx: 1.1, sy: 0.9),
    Keyframe(1, dy: -5, sx: 0.15, sy: 0.15, opacity: 0),
  ];

  @override
  Duration get duration => out * scale;

  @override
  bool get holdsEnd => true;

  @override
  TileXf sample(Duration t) {
    final tc = JwMotion.travel.transform(TileEffect._p(t, travel * scale));
    final o = sampleKeyframes(frames, TileEffect._p(t, out * scale), JwMotion.exit);
    return o + TileXf(dx: travelX * tc, dy: travelY * tc);
  }
}

/// Reduce motion: fade out in 150 ms linear (match) …
class FadeOut extends TileEffect {
  const FadeOut();
  @override
  Duration get duration => const Duration(milliseconds: 150);
  @override
  bool get holdsEnd => true;
  @override
  TileXf sample(Duration t) => TileXf(opacity: 1 - TileEffect._p(t, duration));
}

/// … and fade in (undo, 150 ms linear).
class FadeIn extends TileEffect {
  const FadeIn();
  @override
  Duration get duration => const Duration(milliseconds: 150);
  @override
  TileXf sample(Duration t) => TileXf(opacity: TileEffect._p(t, duration));
}

/// Mismatch: x ±4 → ±2 pt, 280 ms easeInOut.
class Shake extends TileEffect {
  const Shake();
  static const frames = [Keyframe(0), Keyframe(0.25, dx: -4), Keyframe(0.5, dx: 4), Keyframe(0.75, dx: -2), Keyframe(1)];
  @override
  Duration get duration => JwMotion.base;
  @override
  TileXf sample(Duration t) => sampleKeyframes(frames, TileEffect._p(t, duration), Curves.easeInOut);
}

/// Blocked tap on this tile: squash (1.08, 0.9) and wobble ±3°, 500 ms.
class Wobble extends TileEffect {
  const Wobble();
  static const frames = [
    Keyframe(0),
    Keyframe(0.2, sx: 1.08, sy: 0.9),
    Keyframe(0.45, sx: 0.96, sy: 1.05, rot: -3 * _deg),
    Keyframe(0.7, rot: 2 * _deg),
    Keyframe(1),
  ];
  @override
  Duration get duration => const Duration(milliseconds: 500);
  @override
  TileXf sample(Duration t) => sampleKeyframes(frames, TileEffect._p(t, duration), Curves.easeInOut);
}

/// A blocker of the tapped tile presses down 1.5 pt, 500 ms.
class Press extends TileEffect {
  const Press();
  static const frames = [Keyframe(0), Keyframe(0.4, dy: 1.5, sx: 1.02, sy: 0.97), Keyframe(1)];
  @override
  Duration get duration => const Duration(milliseconds: 500);
  @override
  TileXf sample(Duration t) => sampleKeyframes(frames, TileEffect._p(t, duration), Curves.easeInOut);
}

/// Layers settling: a freed tile inflates 0.96 → 1.06 → 1, 550 ms
/// springSoft, ending at the playable rest. Offsets relative to that rest.
class Settle extends TileEffect {
  const Settle();
  static const frames = [
    Keyframe(0, dy: 1.5, sx: 0.96, sy: 0.96),
    Keyframe(0.5, dy: -0.5, sx: 1.06, sy: 1.06),
    Keyframe(1),
  ];
  @override
  Duration get duration => const Duration(milliseconds: 550);
  @override
  TileXf sample(Duration t) => sampleKeyframes(frames, TileEffect._p(t, duration), JwMotion.springSoft);
}

/// Shuffle: flatten to scaleY 0.08 (scaleX 1.1) in 280 ms, faces swap at the
/// midpoint, spring back in 280 ms (560 ms easeInOut).
class ShuffleFlip extends TileEffect {
  const ShuffleFlip();
  static const half = JwMotion.base;
  static const frames = [
    Keyframe(0),
    Keyframe(0.45, sx: 1.1, sy: 0.08),
    Keyframe(0.55, sx: 1.1, sy: 0.08),
    Keyframe(1),
  ];
  @override
  Duration get duration => half * 2;
  @override
  TileXf sample(Duration t) => sampleKeyframes(frames, TileEffect._p(t, duration), Curves.easeInOut);
}

/// Undo: the pair re-enters from scale 0.5 / opacity 0, 500 ms springPop.
class UndoPop extends TileEffect {
  const UndoPop();
  static const frames = [Keyframe(0, sx: 0.5, sy: 0.5, opacity: 0), Keyframe(1)];
  @override
  Duration get duration => const Duration(milliseconds: 500);
  @override
  TileXf sample(Duration t) => sampleKeyframes(frames, TileEffect._p(t, duration), JwMotion.springPop);
}

/// Hint: bob 3 pt (−1.5 → −4.5 → −1.5), 1600 ms easeInOut, looping.
class HintBob extends TileEffect {
  const HintBob();
  static const period = Duration(milliseconds: 1600);
  static const frames = [Keyframe(0), Keyframe(0.5, dy: -3), Keyframe(1)];
  @override
  Duration? get duration => null;
  @override
  TileXf sample(Duration t) {
    final us = t.inMicroseconds % period.inMicroseconds;
    return sampleKeyframes(frames, us / period.inMicroseconds, Curves.easeInOut);
  }
}

/// Reduce motion, blocked tap: one darker frame on the tapped tile.
class Flash extends TileEffect {
  const Flash();
  @override
  Duration get duration => const Duration(milliseconds: 16);
  @override
  TileXf sample(Duration t) => const TileXf(flash: true);
}
