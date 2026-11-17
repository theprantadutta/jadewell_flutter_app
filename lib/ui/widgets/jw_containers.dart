import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../components/icon_badge.dart';
import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';

/// Bottom sheet container: inset 12, radius 34, e3, padding 26/22/22, with a
/// 40 × 5 sunken grip. Presentation (scrim, rise) is the router's job.
class JwSheet extends StatelessWidget {
  const JwSheet({super.key, required this.child, this.grip = true, this.semanticLabel});

  final Widget child;
  final bool grip;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      container: true,
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: semanticLabel != null,
      label: semanticLabel,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: DecoratedBox(
          decoration: jw.clay(ClayLevel.floating, radius: 34),
          child: Padding(
            padding: EdgeInsets.fromLTRB(22, grip ? 12 : 26, 22, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (grip) ...[
                  Center(
                    child: DecoratedBox(
                      decoration: jw.clay(ClayLevel.sunken, radius: 3),
                      child: const SizedBox(width: 40, height: 5),
                    ),
                  ),
                  const SizedBox(height: 9),
                ],
                child,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dialog container: inset 28, radius 32, e3, centred, padding 26/22/20.
/// Optional [title], [body] and [actions] (laid out in a row, gap 14).
class JwDialog extends StatelessWidget {
  const JwDialog({super.key, this.title, this.body, this.actions = const [], this.child});

  final String? title;
  final String? body;
  final List<Widget> actions;

  /// Custom content placed between body and actions.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      container: true,
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: title != null,
      label: title,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: DecoratedBox(
          decoration: jw.clay(ClayLevel.floating, radius: 32),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (title != null)
                  Text(title!, textAlign: TextAlign.center, style: jw.text.h3.copyWith(fontSize: 21)),
                if (body != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    body!,
                    textAlign: TextAlign.center,
                    style: jw.text.body.copyWith(color: jw.textMuted),
                  ),
                ],
                ?child,
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 14),
                        Expanded(child: actions[i]),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Toast: height 42, pill, floating. Leads with a 30 pt [IconBadge] when
/// [icon] is set (in [fill], mint by default), otherwise a 16 pt clay bead.
class JwToast extends StatelessWidget {
  const JwToast({super.key, required this.message, this.beadColor, this.icon, this.fill});

  final String message;

  /// Bead colour, defaults to jade.
  final Color? beadColor;

  /// Leading badge icon ([JwIcons] name); replaces the bead.
  final String? icon;

  /// Badge fill (mint when null).
  final JwFill? fill;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      liveRegion: true,
      label: message,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.floating),
        child: SizedBox(
          height: 42,
          child: Padding(
            padding: EdgeInsets.only(left: icon == null ? 13 : 6, right: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon == null)
                  JwBead(color: beadColor ?? jw.jade, size: 16)
                else
                  Transform.translate(
                    offset: const Offset(0, -1.5),
                    child: IconBadge(icon: icon, fill: fill ?? JwFill.mint),
                  ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: jw.text.callout.copyWith(fontSize: 14.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A clay bead: radial highlight top-left, inner shade bottom-right.
class JwBead extends StatelessWidget {
  const JwBead({super.key, required this.color, this.size = 16});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: JwBeadPainter(color));
}

/// Paints a clay bead filling its square canvas.
class JwBeadPainter extends CustomPainter {
  JwBeadPainter(this.color);

  final Color color;

  /// Paints a bead of [diameter] centred at [c] (shared with tile faces).
  static void paintBead(Canvas canvas, Offset c, double diameter, Color color) {
    final r = diameter / 2;
    final hi = JwFaceInks.lighten(color, 0.5);
    final lo = JwFaceInks.darken(color, 0.22);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = ui.Gradient.radial(
          c + Offset(-0.32 * r, -0.4 * r),
          r * 1.45,
          [hi, color, lo],
          const [0, 0.42, 1],
        ),
    );
  }

  @override
  void paint(Canvas canvas, Size size) =>
      paintBead(canvas, size.center(Offset.zero), size.shortestSide, color);

  @override
  bool shouldRepaint(JwBeadPainter old) => old.color != color;
}

/// Avatar: 36 pt circle, chip clay, initial 14/600. Without [color] the
/// fill is one of the six Clay Pop fills (derived from [name]) with the
/// initial in its `on` colour; a [color] (a profile colour) is drawn flat
/// with dark ink.
class JwAvatar extends StatelessWidget {
  const JwAvatar({super.key, required this.name, this.size = 36, this.color});

  final String name;
  final double size;

  /// Fill colour; a Clay Pop fill derived from [name] when null.
  final Color? color;

  /// The fill an avatar for [name] uses.
  static JwFill fillFor(String name) => JwFill.all[name.codeUnits.fold<int>(0, (a, b) => a + b) % JwFill.all.length];

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final custom = color;
    final fill = fillFor(name);
    final decoration = custom == null
        ? jw.fillFlat(fill, extraShadows: jw.clay(ClayLevel.chip).resolvedShadows.where((s) => !s.inset).toList())
        : jw.clay(ClayLevel.chip, color: custom);
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: decoration,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              initial,
              style: jw.text.callout.copyWith(
                fontSize: size * 0.39,
                fontWeight: FontWeight.w700,
                color: custom == null ? fill.on : JwTheme.light.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
