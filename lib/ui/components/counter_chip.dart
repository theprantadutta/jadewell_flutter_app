import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import 'icon_badge.dart';

/// Counter chip (DESIGN_SYSTEM §11 `cchip`): 38 tall pill, chip elevation,
/// a leading 30 pt [IconBadge] in [fill], the [value] in mono 16/700 and an
/// optional 13 pt muted [label]. Tiles = mint, pairs = pink, streak = coral.
///
/// [valueWidget] replaces the value text (an odometer); give it
/// [valueStyle] to match.
class CounterChip extends StatelessWidget {
  const CounterChip({
    super.key,
    required this.icon,
    required this.value,
    this.label,
    this.fill = JwFill.purple,
    this.valueWidget,
    this.semanticLabel,
  });

  /// A [JwIcons] name for the badge.
  final String icon;
  final String value;
  final String? label;
  final JwFill fill;
  final Widget? valueWidget;
  final String? semanticLabel;

  /// Chip height.
  static const double height = 38;

  /// The value style (mono 16/700, textPrimary) in [jw].
  static TextStyle valueStyle(JwTheme jw) => jw.text.numM.copyWith(fontSize: 16, fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Semantics(
      label: semanticLabel ?? [value, ?label].join(' '),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.chip, radius: height / 2),
        child: SizedBox(
          height: height,
          child: Padding(
            padding: const EdgeInsets.only(left: 4, right: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Lift the badge 1.5 pt so its 3 pt edge sits inside the pill.
                Transform.translate(offset: const Offset(0, -1.5), child: IconBadge(icon: icon, fill: fill)),
                const SizedBox(width: 9),
                valueWidget ?? Text(value, style: valueStyle(jw)),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(label!, style: jw.text.callout.copyWith(fontSize: 13, fontWeight: FontWeight.w500, color: jw.textMuted)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
