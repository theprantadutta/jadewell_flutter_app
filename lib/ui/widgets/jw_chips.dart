import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import 'clay_pressable.dart';
import 'jw_icon.dart';

/// Counter chip: height 30, padding 13, radius 15, e1; [value] in mono
/// 14/600 then [label] (e.g. "86" "tiles"). [accent] gives the accent chip
/// (accentSoft fill, no shadow), used for streaks and personal bests.
class JwChip extends StatelessWidget {
  const JwChip({
    super.key,
    required this.value,
    this.label,
    this.accent = false,
    this.semanticLabel,
  });

  /// Accent chip (accentSoft, no shadow).
  const JwChip.accent({super.key, required this.value, this.label, this.semanticLabel})
    : accent = true;

  final String value;
  final String? label;
  final bool accent;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final deco = accent
        ? jw.clay(ClayLevel.flat, color: jw.accentSoft, radius: 15)
        : jw.clay(ClayLevel.chip, radius: 15);
    return Semantics(
      label: semanticLabel ?? [value, ?label].join(' '),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: deco,
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(value, style: jw.text.numM.copyWith(fontSize: 14.5)),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    label!,
                    style: jw.text.callout.copyWith(
                      fontWeight: FontWeight.w400,
                      color: accent ? jw.textPrimary : jw.textMuted,
                    ),
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

/// Timer pill: height 40, radius 20, e2; accent pause glyph + mono 16/600.
/// Tapping it pauses ([onTap]).
class JwTimerPill extends StatelessWidget {
  const JwTimerPill({
    super.key,
    required this.time,
    this.onTap,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
    this.large = false,
  });

  final String time;
  final VoidCallback? onTap;
  final VoidCallback? onHaptic;
  final String? semanticLabel;
  final bool? reduceMotion;

  /// Top-bar variant (46 tall, 18 pt numerals) as on the game screen.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final h = large ? 46.0 : 40.0;
    return ClayPressable(
      decoration: jw.clay(ClayLevel.raised, radius: h / 2),
      onTap: onTap,
      onHaptic: onHaptic,
      semanticLabel: semanticLabel ?? 'Pause, $time',
      reduceMotion: reduceMotion,
      height: h,
      dimWhenDisabled: false,
      padding: EdgeInsets.only(left: large ? 22 : 18, right: large ? 22 : 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          JwIcon(JwIcons.pause, size: large ? 17 : 15, color: jw.accent),
          SizedBox(width: large ? 14 : 12),
          Text(time, style: jw.text.numM.copyWith(fontSize: large ? 19 : 16)),
        ],
      ),
    );
  }
}
