import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import '../widgets/jw_icon.dart';
import 'fill_box.dart';

/// Tool knob (DESIGN_SYSTEM §11 tool tray): a [size] 58 pt fill object,
/// radius 20 (scaled with the size), the icon in the fill's `on` colour,
/// a caption [label] below and an optional purple count [badge]
/// (top-right). Hint = yellow, Undo = sky, Shuffle = pink.
///
/// Press: down 4 pt losing the base edge in 120 ms, spring back with
/// springPop 280 ms; reduce motion dips brightness instead ([FillPressable]).
class FillKnob extends StatelessWidget {
  const FillKnob({
    super.key,
    required this.icon,
    required this.label,
    required this.fill,
    this.onPressed,
    this.onHaptic,
    this.badge,
    this.semanticLabel,
    this.reduceMotion,
    this.size = 58,
  });

  /// A [JwIcons] name.
  final String icon;
  final String label;
  final JwFill fill;
  final VoidCallback? onPressed;
  final VoidCallback? onHaptic;

  /// Count in the purple badge (null hides it).
  final int? badge;
  final String? semanticLabel;
  final bool? reduceMotion;
  final double size;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      container: true,
      button: true,
      enabled: onPressed != null,
      label: semanticLabel ?? (badge == null ? label : '$label, $badge left'),
      excludeSemantics: true,
      onTap: onPressed == null
          ? null
          : () {
              onHaptic?.call();
              onPressed!();
            },
      child: ExcludeSemantics(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                FillPressable(
                  fill: fill,
                  radius: size * 20 / 58,
                  width: size,
                  height: size,
                  onTap: onPressed,
                  onHaptic: onHaptic,
                  reduceMotion: reduceMotion,
                  child: Center(
                    child: JwIcon(icon, size: size * 26 / 58, color: fill.on, strokeWidth: JwIcon.badgeStroke),
                  ),
                ),
                if (badge != null) Positioned(right: -7, top: -7, child: CountBadge(count: badge!)),
              ],
            ),
            const SizedBox(height: 7),
            Text(label, style: jw.text.callout.copyWith(fontSize: 14.5, fontWeight: FontWeight.w500, color: jw.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// A small purple count bubble with a 2 pt raised-surface ring (the Hint
/// knob's remaining-hints count).
class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, this.fill = JwFill.purple, this.size = 24});

  final int count;
  final JwFill fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(
        ClayLevel.flat,
        color: fill.mid,
        gradient: JwFills.gradient(fill),
        extraShadows: [ClayShadow(0, 0, 0, 2, jw.surfaceRaised)],
      ),
      child: SizedBox(
        height: size,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: size),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Center(
              widthFactor: 1,
              child: Text(
                '$count',
                style: jw.text.numM.copyWith(fontSize: size * 0.54, fontWeight: FontWeight.w700, color: fill.on, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
