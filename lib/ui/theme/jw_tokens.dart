// GENERATED from design-system/tokens.json — Jadewell · Clay Pop
import 'package:flutter/animation.dart';
import 'package:flutter/painting.dart';

class JwColors {
  final Color bgTop;
  final Color bgBottom;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHi;
  final Color surfaceSunken;
  final Color tileFace;
  final Color tileEdge;
  final Color tileBlocked;
  final Color tileBlockedEdge;
  final Color tileSelected;
  final Color accent;
  final Color onAccent;
  final Color accentSoft;
  final Color jade;
  final Color jadeDeep;
  final Color textPrimary;
  final Color textMuted;
  final Color success;
  final Color warning;
  final Color danger;
  final Color shadow;
  final Color inner;
  final Color highlight;
  final Color highlightSoft;
  final Color scrim;
  final double blockedFaceOpacity;
  const JwColors({required this.bgTop, required this.bgBottom, required this.surface, required this.surfaceRaised, required this.surfaceHi, required this.surfaceSunken, required this.tileFace, required this.tileEdge, required this.tileBlocked, required this.tileBlockedEdge, required this.tileSelected, required this.accent, required this.onAccent, required this.accentSoft, required this.jade, required this.jadeDeep, required this.textPrimary, required this.textMuted, required this.success, required this.warning, required this.danger, required this.shadow, required this.inner, required this.highlight, required this.highlightSoft, required this.scrim, required this.blockedFaceOpacity});

  static const light = JwColors(
    bgTop: Color(0xFFF5F3FF),
    bgBottom: Color(0xFFE2DDFB),
    surface: Color(0xFFEEEBFD),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceHi: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFECE8FC),
    tileFace: Color(0xFFFFFFFF),
    tileEdge: Color(0xFFD9D2F6),
    tileBlocked: Color(0xFFDAD5F1),
    tileBlockedEdge: Color(0xFFC1B9E4),
    tileSelected: Color(0xFF6E5CE8),
    accent: Color(0xFF5A47DB),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFE4DFFF),
    jade: Color(0xFF4FCB98),
    jadeDeep: Color(0xFF1F9A6A),
    textPrimary: Color(0xFF2B2550),
    textMuted: Color(0xFF5B5480),
    success: Color(0xFF1F9A6A),
    warning: Color(0xFFB9780A),
    danger: Color(0xFFD93D4A),
    shadow: Color(0x386250C8),
    inner: Color(0x296E5CD2),
    highlight: Color(0xF2FFFFFF),
    highlightSoft: Color(0x99FFFFFF),
    scrim: Color(0x572B2550),
    blockedFaceOpacity: .38,
  );
  static const dark = JwColors(
    bgTop: Color(0xFF2B2557),
    bgBottom: Color(0xFF14112B),
    surface: Color(0xFF1C1838),
    surfaceRaised: Color(0xFF2A2550),
    surfaceHi: Color(0xFF3B3572),
    surfaceSunken: Color(0xFF18142F),
    tileFace: Color(0xFFF6F4FF),
    tileEdge: Color(0xFFA89EE6),
    tileBlocked: Color(0xFF3F3873),
    tileBlockedEdge: Color(0xFF2C2758),
    tileSelected: Color(0xFFA797FF),
    accent: Color(0xFFA08FFF),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0x3DA08FFF),
    jade: Color(0xFF5EDDA8),
    jadeDeep: Color(0xFF5EDDA8),
    textPrimary: Color(0xFFF2EFFF),
    textMuted: Color(0xFFADA6DA),
    success: Color(0xFF5EDDA8),
    warning: Color(0xFFFFD15C),
    danger: Color(0xFFFF7A84),
    shadow: Color(0x9E040214),
    inner: Color(0x57000000),
    highlight: Color(0x1CFFFFFF),
    highlightSoft: Color(0x0FFFFFFF),
    scrim: Color(0x9E08061A),
    blockedFaceOpacity: .5,
  );
}

class JwRadius { static const xs = 6.0, tile = 9.0, sm = 12.0, md = 18.0, lg = 24.0, xl = 30.0, xxl = 38.0, pill = 999.0; }

/// Saturated clay fills. Identical in light and dark (dark only deepens the shadow).
/// Paint: LinearGradient(160°, [top, mid]) + a solid [edge] offset 5 px below (3 px for badges)
/// + a soft glow of [glow] at 55% alpha, blur 24, y 16, spread -10. Text/icons on a fill use [on].
class JwFill {
  final Color top, mid, edge, glow, on;
  const JwFill(this.top, this.mid, this.edge, this.glow, this.on);
  static const purple = JwFill(Color(0xFF8572F4), Color(0xFF634FE0), Color(0xFF4F3CC9), Color(0xFF6450E1), Color(0xFFFFFFFF));
  static const mint = JwFill(Color(0xFF8BE8C2), Color(0xFF4FCB98), Color(0xFF2FAE7C), Color(0xFF3CBE8C), Color(0xFF0F3B2A));
  static const yellow = JwFill(Color(0xFFFFE07A), Color(0xFFFFC93C), Color(0xFFE7A818), Color(0xFFE6AA1E), Color(0xFF4A3200));
  static const pink = JwFill(Color(0xFFFFAACB), Color(0xFFFF7DB0), Color(0xFFE55A92), Color(0xFFF06496), Color(0xFF4A0F2A));
  static const sky = JwFill(Color(0xFF9CD6FF), Color(0xFF5CB8FF), Color(0xFF3A96E0), Color(0xFF46A0F0), Color(0xFF0C2F52));
  static const coral = JwFill(Color(0xFFFFB39C), Color(0xFFFF8A6B), Color(0xFFE8664A), Color(0xFFF0785A), Color(0xFF4A160A));
  static const all = [purple, mint, yellow, pink, sky, coral];
}
class JwSpace { static const s1 = 4.0, s2 = 8.0, s3 = 12.0, s4 = 16.0, s5 = 20.0, s6 = 24.0, s8 = 32.0, s10 = 40.0, s14 = 56.0; }

class JwMotion {
  static const instant = Duration(milliseconds: 120);
  static const quick = Duration(milliseconds: 180);
  static const base = Duration(milliseconds: 280);
  static const gentle = Duration(milliseconds: 400);
  static const slow = Duration(milliseconds: 600);
  static const lingering = Duration(milliseconds: 900);
  static const easeOutSoft = Cubic(0.2, 0.8, 0.2, 1);
  static const standard = Cubic(0.4, 0, 0.2, 1);
  static const springSoft = Cubic(0.3, 1.5, 0.5, 1);
  static const springPop = Cubic(0.3, 1.8, 0.5, 1);
  static const dropIn = Cubic(0.3, 0.9, 0.4, 1);
  static const exit = Cubic(0.4, 0, 0.5, 1);
  static const travel = Cubic(0.45, 0, 0.25, 1);
  static const linear = Cubic(0, 0, 1, 1);
}

class JwTile {
  static const footprint = Size(32, 39), face = Size(29.5, 36.5);
  static const gap = 2.5, radius = 9.0, faceInset = 4.0, edge = 4.0, layerStep = 6.0;
  static const liftPlayable = 1.5, liftSelected = 7.0, selectedRing = 2.5;
}
