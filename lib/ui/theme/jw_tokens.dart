// GENERATED from design-system/tokens.json — Jadewell · Soft 3D Clay
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
    bgTop: Color(0xFFFBF2EC),
    bgBottom: Color(0xFFEED9CD),
    surface: Color(0xFFF6E9E1),
    surfaceRaised: Color(0xFFF9EEE7),
    surfaceHi: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEEDCD1),
    tileFace: Color(0xFFFFF9F5),
    tileEdge: Color(0xFFE6CDBE),
    tileBlocked: Color(0xFFE5CDBF),
    tileBlockedEdge: Color(0xFFCFB2A2),
    tileSelected: Color(0xFFE8735F),
    accent: Color(0xFFE8735F),
    onAccent: Color(0xFF3A1A12),
    accentSoft: Color(0xFFF6D3C8),
    jade: Color(0xFF4FA585),
    jadeDeep: Color(0xFF2F7D63),
    textPrimary: Color(0xFF4A3934),
    textMuted: Color(0xFF6C544E),
    success: Color(0xFF3F8F67),
    warning: Color(0xFFB97A1E),
    danger: Color(0xFFC2472F),
    shadow: Color(0x478C553E),
    inner: Color(0x38AA6E55),
    highlight: Color(0xE6FFFFFF),
    highlightSoft: Color(0x8CFFFFFF),
    scrim: Color(0x474A3934),
    blockedFaceOpacity: .36,
  );
  static const dark = JwColors(
    bgTop: Color(0xFF2C2523),
    bgBottom: Color(0xFF1B1715),
    surface: Color(0xFF241F1C),
    surfaceRaised: Color(0xFF332C28),
    surfaceHi: Color(0xFF3F3732),
    surfaceSunken: Color(0xFF1E1A18),
    tileFace: Color(0xFFF1E8DE),
    tileEdge: Color(0xFFB8A291),
    tileBlocked: Color(0xFF5E524B),
    tileBlockedEdge: Color(0xFF463C36),
    tileSelected: Color(0xFFF0846F),
    accent: Color(0xFFF0846F),
    onAccent: Color(0xFF2A0F08),
    accentSoft: Color(0x33F0846F),
    jade: Color(0xFF5DB592),
    jadeDeep: Color(0xFF3E9476),
    textPrimary: Color(0xFFF3E9E2),
    textMuted: Color(0xFFB5A39A),
    success: Color(0xFF6CC092),
    warning: Color(0xFFE6B25A),
    danger: Color(0xFFF07A62),
    shadow: Color(0x8C000000),
    inner: Color(0x61000000),
    highlight: Color(0x1AFFFFFF),
    highlightSoft: Color(0x0FFFFFFF),
    scrim: Color(0x80000000),
    blockedFaceOpacity: .5,
  );
}

class JwRadius { static const xs = 6.0, tile = 9.0, sm = 12.0, md = 16.0, lg = 22.0, xl = 28.0, xxl = 34.0, pill = 999.0; }
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
