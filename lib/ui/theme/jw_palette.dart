import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'jw_tokens.dart';

/// Theme-independent base colours. The only place outside the generated
/// tokens where literal colours live, so painters can mix with white/black
/// (bead highlights, sheens) and build alpha-only paints without hard-coding
/// colours elsewhere (`test/theme/no_hardcoded_colors_test.dart`).
abstract final class JwBase {
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF000000);

  /// Fully transparent (sheet backgrounds, empty fills).
  static const transparent = Color(0x00000000);

  /// A colour whose only meaningful channel is alpha: for `saveLayer` /
  /// `drawImage` paints that fade content by [opacity].
  static Color alpha(double opacity) => Color.fromRGBO(0, 0, 0, opacity.clamp(0.0, 1.0));

  /// `Paint` that fades a layer or image by [opacity].
  static Paint alphaPaint(double opacity) => Paint()..color = alpha(opacity);

  /// Parses `#RRGGBB` (or `RRGGBB`); null when absent or malformed.
  static Color? fromHex(String? hex) {
    if (hex == null) return null;
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(hex.trim());
    if (m == null) return null;
    return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }
}

/// Tile face inks (DESIGN_SYSTEM §3, `tokens.json → faceInk`). The same in
/// both themes: glyphs always sit on a white face.
abstract final class JwFaceInks {
  static const circleBlue = Color(0xFF5867E8);
  static const circleGreen = Color(0xFF2FAE78);
  static const circleRed = Color(0xFFF2585B);
  static const bamboo = Color(0xFF1E9A8A);
  static const characterNumeral = Color(0xFF3B2F6B);
  static const characterWan = Color(0xFFF2585B);
  static const winds = Color(0xFF3B2F6B);
  static const flowers = Color(0xFFE0478E);
  static const seasons = Color(0xFFE08A0B);

  /// Green dragon and green bamboo/circle elements.
  static const green = circleGreen;

  /// Red dragon, 萬 and red elements.
  static const red = circleRed;

  /// White-dragon frame.
  static const blue = circleBlue;

  /// The 1-circle's jade ring (the logo bead green).
  static const jade = Color(0xFF4FCB98);

  /// `tile-faces.json` element colour keys → ink (`faceInk.elementKeys`).
  static Color element(String key) => switch (key) {
    'c1' => circleBlue,
    'c2' || 'g' => circleGreen,
    'c3' || 'r' => circleRed,
    'b' => bamboo,
    _ => characterNumeral,
  };

  /// Bead / capsule shading: how far highlights mix toward white and shades
  /// toward black.
  static Color lighten(Color c, double t) => Color.lerp(c, JwBase.white, t)!;
  static Color darken(Color c, double t) => Color.lerp(c, JwBase.black, t)!;
}

/// The six saturated clay fills (DESIGN_SYSTEM §3) plus the recipe strengths
/// for one theme. Fill colours are identical in light and dark; only the
/// inner highlight, inner shade and glow strengths differ.
@immutable
class JwFills {
  const JwFills._({
    required this.highlightAlpha,
    required this.shadeAlpha,
    required this.glowAlpha,
    required this.glowBlur,
  });

  static const light = JwFills._(highlightAlpha: .55, shadeAlpha: .08, glowAlpha: .55, glowBlur: 24);
  static const dark = JwFills._(highlightAlpha: .40, shadeAlpha: .18, glowAlpha: .50, glowBlur: 28);

  JwFill get purple => JwFill.purple;
  JwFill get mint => JwFill.mint;
  JwFill get yellow => JwFill.yellow;
  JwFill get pink => JwFill.pink;
  JwFill get sky => JwFill.sky;
  JwFill get coral => JwFill.coral;
  List<JwFill> get all => JwFill.all;

  /// Inset highlight `2 3 6 rgba(255,255,255,a)`.
  final double highlightAlpha;

  /// Inset shade `−3 −5 10 rgba(0,0,0,a)`.
  final double shadeAlpha;

  /// Glow `0 16 blur −10 rgba(glow,a)`.
  final double glowAlpha;
  final double glowBlur;

  /// Edge height under fill cards, knobs and buttons.
  static const double cardEdge = 5;

  /// Edge height under icon badges.
  static const double badgeEdge = 3;

  /// How far a pressed fill moves down.
  static const double pressDepth = 4;

  /// The 160° gradient (top → mid) of [fill]: CSS 160° points down and
  /// slightly right.
  static LinearGradient gradient(JwFill fill) => LinearGradient(
    begin: const Alignment(-0.342, -0.94),
    end: const Alignment(0.342, 0.94),
    colors: [fill.top, fill.mid],
  );

  /// The fill a layout plate uses, by layout index (Pyramid yellow, Turtle
  /// mint, Fortress pink, Bridge sky, Crab coral, Dragon purple, Butterfly
  /// pink, Cat yellow, then repeating).
  static JwFill plate(int index) => _plates[index % _plates.length];
  static const _plates = [
    JwFill.yellow,
    JwFill.mint,
    JwFill.pink,
    JwFill.sky,
    JwFill.coral,
    JwFill.purple,
    JwFill.pink,
    JwFill.yellow,
  ];
}

