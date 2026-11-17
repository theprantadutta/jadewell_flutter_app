import 'package:flutter/widgets.dart';

import '../components/icon_badge.dart';
import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import 'clay_pressable.dart';
import 'jw_icon.dart';

/// Small chip: height 30, padding 13, radius 15, chip clay; [value] in mono
/// 14.5/600 then [label] (e.g. "86" "tiles"). [accent] gives the coral fill
/// chip (streaks, "New best"). For the 38 pt game counters with a leading
/// badge use `CounterChip`.
class JwChip extends StatelessWidget {
  const JwChip({
    super.key,
    required this.value,
    this.label,
    this.accent = false,
    this.semanticLabel,
  });

  /// Accent chip (coral fill).
  const JwChip.accent({super.key, required this.value, this.label, this.semanticLabel})
    : accent = true;

  final String value;
  final String? label;
  final bool accent;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final deco = accent ? jw.fillFlat(JwFill.coral, radius: 15) : jw.clay(ClayLevel.chip, radius: 15);
    final fg = accent ? JwFill.coral.on : null;
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
                Text(value, style: jw.text.numM.copyWith(fontSize: 14.5, color: fg, fontWeight: accent ? FontWeight.w700 : null)),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    label!,
                    style: jw.text.callout.copyWith(
                      fontWeight: accent ? FontWeight.w600 : FontWeight.w400,
                      color: fg ?? jw.textMuted,
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

/// Timer pill: height 40 (46 [large]), pill, raised; a leading 30 pt yellow
/// badge with the pause glyph, then the time in mono 16/700. Tapping it
/// pauses ([onTap]).
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
      padding: EdgeInsets.only(left: large ? 7 : 5, right: large ? 20 : 18),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.translate(
            offset: const Offset(0, -1.5),
            child: IconBadge(icon: JwIcons.pause, fill: JwFill.yellow, size: large ? 32 : 30),
          ),
          SizedBox(width: large ? 12 : 10),
          Text(time, style: jw.text.numM.copyWith(fontSize: large ? 19 : 16, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
