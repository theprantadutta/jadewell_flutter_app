import 'package:flutter/widgets.dart';

import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import '../widgets/jw_icon.dart';

/// An icon in a coloured clay badge (DESIGN_SYSTEM §3 `b-*`, §11): [size]
/// 30 pt by default (26–48 in lists and chips, 64–68 leading dialogs),
/// radius ⅓ of the side, the [fill]'s gradient with a 3 pt base edge and no
/// glow; the icon is drawn in the fill's `on` colour at stroke 2.4.
///
/// [child] replaces the icon (a count, a "NEW" label); text in it defaults
/// to the fill's `on` colour.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    this.icon,
    this.fill = JwFill.purple,
    this.size = 30,
    this.iconSize,
    this.child,
    this.edge = JwFills.badgeEdge,
    this.semanticLabel,
  }) : assert(icon != null || child != null, 'Pass an icon or a child');

  /// A [JwIcons] name.
  final String? icon;
  final JwFill fill;

  /// Side length in pt.
  final double size;

  /// Icon size; defaults to [iconSizeFor] ([size]).
  final double? iconSize;
  final Widget? child;

  /// Base edge height (3 by default).
  final double edge;
  final String? semanticLabel;

  /// Default icon size for a badge of [side]: 17 at 30, 24-25 at 48, 32 at 64.
  static double iconSizeFor(double side) => side <= 30 ? side * 17 / 30 : 17 + (side - 30) * 0.45;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final content = child ??
        JwIcon(icon!, size: iconSize ?? iconSizeFor(size), color: fill.on, strokeWidth: JwIcon.badgeStroke);
    final badge = DecoratedBox(
      decoration: jw.fill(fill, radius: size / 3, edge: edge, glow: false),
      child: SizedBox.square(
        dimension: size,
        child: Center(
          child: DefaultTextStyle.merge(
            style: TextStyle(color: fill.on),
            child: IconTheme.merge(data: IconThemeData(color: fill.on), child: content),
          ),
        ),
      ),
    );
    if (semanticLabel == null) return ExcludeSemantics(child: badge);
    return Semantics(label: semanticLabel, excludeSemantics: true, child: badge);
  }
}
