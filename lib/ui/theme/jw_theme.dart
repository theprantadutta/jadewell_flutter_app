import 'package:material_ui/material_ui.dart';

import 'clay.dart';
import 'fill.dart';
import 'jw_fonts.dart';
import 'jw_palette.dart';
import 'jw_tokens.dart';

export 'fill.dart' show FillDecoration;
export 'jw_palette.dart';

/// Text styles of DESIGN_SYSTEM.md §4, resolved against one theme's colours.
///
/// Every style carries `textPrimary`; use `copyWith(color: …)` for others.
/// Mono styles (num*) use JetBrains Mono with tabular figures and −0.02em.
@immutable
class JwTextStyles {
  JwTextStyles(JwColors c)
    : display = _ui(40, 44, FontWeight.w700, -0.02, c.textPrimary),
      h1 = _ui(28, 32, FontWeight.w700, -0.02, c.textPrimary),
      h2 = _ui(26, 29, FontWeight.w700, -0.02, c.textPrimary),
      h3 = _ui(19, 24, FontWeight.w700, -0.01, c.textPrimary),
      title = _ui(21, 23, FontWeight.w700, -0.01, c.textPrimary),
      body = _ui(15, 22, FontWeight.w400, 0, c.textPrimary),
      callout = _ui(14, 19, FontWeight.w500, 0, c.textPrimary),
      button = _ui(16, 20, FontWeight.w700, 0, c.textPrimary),
      caption = _ui(12.5, 16, FontWeight.w500, 0, c.textMuted),
      eyebrow = _ui(12, 14, FontWeight.w700, 0.14, c.textMuted),
      numXl = mono(52, FontWeight.w700, c.textPrimary),
      numL = mono(24, FontWeight.w700, c.textPrimary),
      numM = mono(15, FontWeight.w600, c.textPrimary),
      glyph = const TextStyle(
        fontFamily: JwFonts.glyph,
        fontSize: 17,
        height: 1,
        fontWeight: FontWeight.w700,
      );

  final TextStyle display;
  final TextStyle h1;
  final TextStyle h2;
  final TextStyle h3;
  final TextStyle title;
  final TextStyle body;
  final TextStyle callout;
  final TextStyle button;
  final TextStyle caption;

  /// Group label. Render the string upper-cased (`'Feedback'.toUpperCase()`).
  final TextStyle eyebrow;
  final TextStyle numXl;
  final TextStyle numL;
  final TextStyle numM;

  /// Tile glyph (Noto Sans SC 700). Sizes 11 / 12 / 17 per §3.
  final TextStyle glyph;

  static TextStyle _ui(double size, double lh, FontWeight w, double em, Color color) =>
      TextStyle(
        fontFamily: JwFonts.ui,
        fontSize: size,
        height: lh / size,
        fontWeight: w,
        letterSpacing: em * size,
        color: color,
        leadingDistribution: TextLeadingDistribution.even,
      );

  /// A JetBrains Mono numeral style at any size (tabular, −0.02em).
  static TextStyle mono(double size, FontWeight weight, Color color) => TextStyle(
    fontFamily: JwFonts.mono,
    fontSize: size,
    height: 1.2,
    fontWeight: weight,
    letterSpacing: -0.02 * size,
    color: color,
    fontFeatures: const [FontFeature.tabularFigures()],
    leadingDistribution: TextLeadingDistribution.even,
  );
}

/// Spacing scale (pt): 4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 56 · 72.
@immutable
class JwSpacing {
  const JwSpacing();
  double get s1 => JwSpace.s1;
  double get s2 => JwSpace.s2;
  double get s3 => JwSpace.s3;
  double get s4 => JwSpace.s4;
  double get s5 => JwSpace.s5;
  double get s6 => JwSpace.s6;
  double get s8 => JwSpace.s8;
  double get s10 => JwSpace.s10;
  double get s14 => JwSpace.s14;
  double get s18 => 72;

  /// Side margin for cards.
  double get cardMargin => 16;

  /// Side margin for text blocks and the tray.
  double get textMargin => 22;
}

/// Corner radii (pt).
@immutable
class JwRadii {
  const JwRadii();
  double get xs => JwRadius.xs;
  double get tile => JwRadius.tile;
  double get sm => JwRadius.sm;
  double get md => JwRadius.md;
  double get lg => JwRadius.lg;
  double get xl => JwRadius.xl;
  double get xxl => JwRadius.xxl;
  double get pill => JwRadius.pill;
}

/// Jadewell theme extension: every colour token, the §4 text styles,
/// spacing, radii and clay helpers. Read with `JwTheme.of(context)` or
/// `context.jw`.
@immutable
class JwTheme extends ThemeExtension<JwTheme> {
  JwTheme._(this.brightness, this.colors) : text = JwTextStyles(colors);

  static final JwTheme light = JwTheme._(Brightness.light, JwColors.light);
  static final JwTheme dark = JwTheme._(Brightness.dark, JwColors.dark);

  static JwTheme forBrightness(Brightness b) => b == Brightness.dark ? dark : light;

  /// The nearest [JwTheme]; falls back to the light theme.
  static JwTheme of(BuildContext context) =>
      Theme.of(context).extension<JwTheme>() ?? light;

  final Brightness brightness;
  final JwColors colors;
  final JwTextStyles text;
  final JwSpacing space = const JwSpacing();
  final JwRadii radius = const JwRadii();

  bool get isDark => brightness == Brightness.dark;

  // Colour tokens.
  Color get bgTop => colors.bgTop;
  Color get bgBottom => colors.bgBottom;
  Color get surface => colors.surface;
  Color get surfaceRaised => colors.surfaceRaised;
  Color get surfaceHi => colors.surfaceHi;
  Color get surfaceSunken => colors.surfaceSunken;
  Color get tileFace => colors.tileFace;
  Color get tileEdge => colors.tileEdge;
  Color get tileBlocked => colors.tileBlocked;
  Color get tileBlockedEdge => colors.tileBlockedEdge;
  Color get tileSelected => colors.tileSelected;
  Color get accent => colors.accent;
  Color get onAccent => colors.onAccent;
  Color get accentSoft => colors.accentSoft;
  Color get jade => colors.jade;
  Color get jadeDeep => colors.jadeDeep;
  Color get textPrimary => colors.textPrimary;
  Color get textMuted => colors.textMuted;
  Color get success => colors.success;
  Color get warning => colors.warning;
  Color get danger => colors.danger;
  Color get shadow => colors.shadow;
  Color get inner => colors.inner;
  Color get highlight => colors.highlight;
  Color get highlightSoft => colors.highlightSoft;
  Color get scrim => colors.scrim;
  double get blockedFaceOpacity => colors.blockedFaceOpacity;

  /// Glyph saturation on blocked tiles (35 % light, 45 % dark).
  double get blockedFaceSaturation => isDark ? 0.45 : 0.35;

  /// Hint ring + glow on tiles (`#FFC93C` / dark `#FFD15C`).
  Color get tileHinted => isDark ? colors.warning : JwFill.yellow.mid;

  /// The six fills with this theme's recipe strengths:
  /// `jw.fills.purple`, `jw.fills.all`, `jw.fills.glowAlpha`.
  JwFills get fills => isDark ? JwFills.dark : JwFills.light;

  /// Small text in the purple fill colour (light `#4F3CC9`, 7:1 on white;
  /// dark uses [accent]).
  Color get purpleText => isDark ? colors.accent : JwFill.purple.edge;

  /// Blob opacity on [PopBackground]-style decor (1 light, .42 dark).
  double get blobOpacity => isDark ? 0.42 : 1;

  /// A [ClayDecoration] at [level] in this theme.
  ClayDecoration clay(
    ClayLevel level, {
    double radius = JwRadius.pill,
    Color? color,
    Gradient? gradient,
    List<ClayShadow> extraShadows = const [],
  }) => ClayDecoration(
    level: level,
    colors: colors,
    radius: radius,
    color: color,
    gradient: gradient,
    extraShadows: extraShadows,
  );

  /// A [FillDecoration] of [fill] with this theme's recipe strengths.
  /// Cards/knobs/buttons: edge 5 + glow (the defaults); badges: `edge: 3,
  /// glow: false`.
  FillDecoration fill(
    JwFill fill, {
    double radius = JwRadius.lg,
    double edge = JwFills.cardEdge,
    bool glow = true,
    double pressed = 0,
    bool dip = false,
  }) => FillDecoration(fill: fill, colors: colors, radius: radius, edge: edge, glow: glow, pressed: pressed, dip: dip);

  /// The knob/orb gradient (surfaceHi → surfaceRaised, lit top-left).
  Gradient get knobGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [surfaceHi, surfaceRaised],
  );

  @override
  JwTheme copyWith() => this;

  /// Themes snap rather than interpolate: clay pictures are cached per theme
  /// and an interpolated palette would record a new set every frame.
  @override
  JwTheme lerp(covariant JwTheme? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

extension JwThemeContext on BuildContext {
  /// Shorthand for [JwTheme.of].
  JwTheme get jw => JwTheme.of(this);
}

/// The app [ThemeData] for [brightness], with [JwTheme] attached, bundled
/// fonts and no ink splashes (clay presses instead).
ThemeData buildJwThemeData(Brightness brightness) {
  final jw = JwTheme.forBrightness(brightness);
  final c = jw.colors;
  final t = jw.text;
  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.jade,
    onSecondary: c.onAccent,
    tertiary: c.jadeDeep,
    onTertiary: c.surfaceHi,
    error: c.danger,
    onError: c.surfaceHi,
    surface: c.surface,
    onSurface: c.textPrimary,
    onSurfaceVariant: c.textMuted,
    surfaceContainerHighest: c.surfaceRaised,
    outline: c.textMuted,
    shadow: c.shadow,
    scrim: c.scrim,
  );
  return ThemeData(
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: JwFonts.ui,
    scaffoldBackgroundColor: c.surface,
    canvasColor: c.surface,
    splashFactory: NoSplash.splashFactory,
    splashColor: JwBase.transparent,
    highlightColor: JwBase.transparent,
    hoverColor: JwBase.transparent,
    textTheme: TextTheme(
      displayLarge: t.display,
      headlineLarge: t.h1,
      headlineMedium: t.h2,
      headlineSmall: t.h3,
      titleLarge: t.title,
      titleMedium: t.button,
      titleSmall: t.callout,
      bodyLarge: t.body,
      bodyMedium: t.body,
      bodySmall: t.caption,
      labelLarge: t.button,
      labelMedium: t.callout,
      labelSmall: t.eyebrow,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.accent,
      selectionColor: c.accentSoft,
      selectionHandleColor: c.accent,
    ),
    extensions: [jw],
  );
}
