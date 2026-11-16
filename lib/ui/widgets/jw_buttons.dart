import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import 'clay_pressable.dart';
import 'jw_icon.dart';
import 'reduce_motion.dart';

enum JwButtonVariant { primary, secondary, tertiary }

/// Primary / secondary / tertiary button (DESIGN_SYSTEM §11).
///
/// Height 56 (42 when [small]), pill. Primary: accent fill, onAccent label,
/// `primary` clay. Secondary: surfaceRaised, e2. Tertiary: text only in
/// textMuted. [icon] is a [JwIcons] name. [expand] stretches to the width.
class JwButton extends StatelessWidget {
  const JwButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = JwButtonVariant.primary,
    this.icon,
    this.small = false,
    this.expand = false,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
  });

  const JwButton.primary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.expand = false,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
  }) : variant = JwButtonVariant.primary;

  const JwButton.secondary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.expand = false,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
  }) : variant = JwButtonVariant.secondary;

  const JwButton.tertiary({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.small = false,
    this.expand = false,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
  }) : variant = JwButtonVariant.tertiary;

  final String label;
  final VoidCallback? onPressed;
  final JwButtonVariant variant;
  final String? icon;
  final bool small;
  final bool expand;
  final VoidCallback? onHaptic;
  final String? semanticLabel;
  final bool? reduceMotion;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final height = small ? 42.0 : 56.0;
    final fg = switch (variant) {
      JwButtonVariant.primary => jw.onAccent,
      JwButtonVariant.secondary => jw.textPrimary,
      JwButtonVariant.tertiary => jw.textMuted,
    };
    final style = variant == JwButtonVariant.tertiary
        ? jw.text.button.copyWith(color: fg, fontWeight: FontWeight.w500, fontSize: 17)
        : jw.text.button.copyWith(color: fg, fontSize: small ? 15.5 : 16);
    final iconSize = variant == JwButtonVariant.primary ? 19.0 : 17.0;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          JwIcon(icon!, size: iconSize, color: fg),
          const SizedBox(width: 8),
        ],
        // Shrink a label that doesn't fit (narrow dialogs, long translations)
        // rather than cutting it off with an ellipsis.
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, style: style, maxLines: 1),
          ),
        ),
      ],
    );

    if (variant == JwButtonVariant.tertiary) {
      return _TertiaryButton(
        height: height,
        expand: expand,
        onPressed: onPressed,
        onHaptic: onHaptic,
        semanticLabel: semanticLabel ?? label,
        reduceMotion: reduceMotion,
        child: content,
      );
    }

    final primary = variant == JwButtonVariant.primary;
    final deco = jw.clay(primary ? ClayLevel.primary : ClayLevel.raised);
    final pressed = deco.copyWith(level: ClayLevel.pressed);
    return ClayPressable(
      decoration: deco,
      pressedDecoration: pressed,
      onTap: onPressed,
      onHaptic: onHaptic,
      semanticLabel: semanticLabel ?? label,
      reduceMotion: reduceMotion,
      height: height,
      width: expand ? double.infinity : null,
      padding: EdgeInsets.symmetric(horizontal: small ? 22 : (expand ? 16 : 28)),
      child: Center(widthFactor: 1, child: content),
    );
  }
}

class _TertiaryButton extends StatefulWidget {
  const _TertiaryButton({
    required this.height,
    required this.expand,
    required this.onPressed,
    required this.onHaptic,
    required this.semanticLabel,
    required this.reduceMotion,
    required this.child,
  });

  final double height;
  final bool expand;
  final VoidCallback? onPressed;
  final VoidCallback? onHaptic;
  final String semanticLabel;
  final bool? reduceMotion;
  final Widget child;

  @override
  State<_TertiaryButton> createState() => _TertiaryButtonState();
}

class _TertiaryButtonState extends State<_TertiaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final reduce = JwReduceMotion.of(context, widget.reduceMotion);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      onTap: enabled ? _tap : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: enabled ? _tap : null,
        child: SizedBox(
          height: widget.height,
          width: widget.expand ? double.infinity : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: AnimatedOpacity(
              opacity: !enabled ? 0.5 : (_down ? 0.6 : 1),
              duration: reduce ? JwMotion.instant : JwMotion.quick,
              child: Center(widthFactor: 1, child: widget.child),
            ),
          ),
        ),
      ),
    );
  }

  void _tap() {
    widget.onHaptic?.call();
    widget.onPressed?.call();
  }
}

/// 46 pt circular icon button, e2, icon 22 pt (back, close, top-bar actions).
class JwIconButton extends StatelessWidget {
  const JwIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.onHaptic,
    this.size = 46,
    this.iconSize = 22,
    this.color,
    this.reduceMotion,
  });

  final String icon;
  final String semanticLabel;
  final VoidCallback? onPressed;
  final VoidCallback? onHaptic;
  final double size;
  final double iconSize;
  final Color? color;
  final bool? reduceMotion;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return ClayPressable(
      decoration: jw.clay(ClayLevel.raised),
      onTap: onPressed,
      onHaptic: onHaptic,
      semanticLabel: semanticLabel,
      reduceMotion: reduceMotion,
      width: size,
      height: size,
      child: Center(child: JwIcon(icon, size: iconSize, color: color ?? jw.textPrimary)),
    );
  }
}
