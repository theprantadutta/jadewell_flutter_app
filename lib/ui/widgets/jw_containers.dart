import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_theme.dart';

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

/// Toast: height 40, pill, e3, leading 16 pt clay bead.
class JwToast extends StatelessWidget {
  const JwToast({super.key, required this.message, this.beadColor});

  final String message;

  /// Bead colour, defaults to jade.
  final Color? beadColor;

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
          height: 40,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                JwBead(color: beadColor ?? jw.jade, size: 16),
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
    final hi = Color.lerp(color, const Color(0xFFFFFFFF), 0.5)!;
    final lo = Color.lerp(color, const Color(0xFF000000), 0.22)!;
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

/// Avatar: 36 pt circle, e1, initial 14/600 on a pastel fill.
class JwAvatar extends StatelessWidget {
  const JwAvatar({super.key, required this.name, this.size = 36, this.color});

  final String name;
  final double size;

  /// Pastel fill; derived from [name] when null.
  final Color? color;

  static const _pastels = [
    Color(0xFFF6D3C8),
    Color(0xFFCFE6DA),
    Color(0xFFD7DBF2),
    Color(0xFFF3E1BF),
    Color(0xFFF0D2DE),
  ];

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final fill = color ?? _pastels[name.codeUnits.fold<int>(0, (a, b) => a + b) % _pastels.length];
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.chip, color: fill),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              initial,
              style: jw.text.callout.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF4A3934),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
