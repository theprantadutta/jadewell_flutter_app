import 'package:flutter/widgets.dart';

import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import '../widgets/jw_icon.dart';
import 'fill_box.dart';

/// Primary button (DESIGN_SYSTEM §11): [height] 56–64, pill, purple
/// gradient `#8572F4 → #634FE0`, 5 pt base edge `#4F3CC9`, purple glow,
/// white 16–17/700 label and an optional 19 pt [icon] ([JwIcons] name).
/// Presses like every fill ([FillPressable]). [fill] swaps the colour (the
/// yellow Play pill on a purple hero).
///
/// The base edge paints 5 pt below the box.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.trailingIcon,
    this.height = 56,
    this.expand = false,
    this.fill = JwFill.purple,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
  });

  final String label;
  final VoidCallback? onPressed;

  /// Leading icon ([JwIcons] name).
  final String? icon;

  /// Trailing icon (an arrow on "Next").
  final String? trailingIcon;
  final double height;

  /// Stretch to the available width.
  final bool expand;
  final JwFill fill;
  final VoidCallback? onHaptic;
  final String? semanticLabel;
  final bool? reduceMotion;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final fg = fill.on;
    final small = height < 50;
    final style = jw.text.button.copyWith(color: fg, fontSize: small ? 15.5 : (height >= 60 ? 17 : 16.5), fontWeight: FontWeight.w700);
    final iconSize = small ? 17.0 : 19.0;
    return FillPressable(
      fill: fill,
      radius: JwRadius.pill,
      height: height,
      width: expand ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: small ? 20 : (expand ? 16 : 28)),
      onTap: onPressed,
      onHaptic: onHaptic,
      semanticLabel: semanticLabel ?? label,
      reduceMotion: reduceMotion,
      child: Center(
        widthFactor: 1,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[JwIcon(icon!, size: iconSize, color: fg), const SizedBox(width: 9)],
            // Shrink a label that doesn't fit rather than ellipsize it.
            Flexible(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, style: style, maxLines: 1))),
            if (trailingIcon != null) ...[const SizedBox(width: 9), JwIcon(trailingIcon!, size: iconSize, color: fg)],
          ],
        ),
      ),
    );
  }
}
