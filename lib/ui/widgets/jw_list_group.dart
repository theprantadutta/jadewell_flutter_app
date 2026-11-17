import 'package:flutter/widgets.dart';

import '../components/fill_knob.dart';
import '../components/icon_badge.dart';
import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import 'jw_icon.dart';
import 'reduce_motion.dart';

/// List group: radius 24, e2, rows separated by 1 pt surfaceSunken lines.
class JwListGroup extends StatelessWidget {
  const JwListGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.raised, radius: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) ColoredBox(color: jw.surfaceSunken, child: const SizedBox(height: 1)),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// 34 pt leading icon of list rows: a coloured [IconBadge] in [fill]
/// (purple by default). With [color] and no [fill] it is a tinted well
/// instead (the colour at 16 % behind an icon in that colour), used for
/// destructive rows.
class JwIconWell extends StatelessWidget {
  const JwIconWell({super.key, required this.icon, this.color, this.size = 34, this.fill});

  final String icon;
  final Color? color;
  final double size;
  final JwFill? fill;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final tint = color;
    if (fill == null && tint != null) {
      return DecoratedBox(
        decoration: jw.clay(ClayLevel.flat, color: tint.withValues(alpha: 0.16), radius: size / 3),
        child: SizedBox.square(
          dimension: size,
          child: Center(child: JwIcon(icon, size: IconBadge.iconSizeFor(size), color: tint, strokeWidth: JwIcon.badgeStroke)),
        ),
      );
    }
    // Lift by half the 3 pt edge so the badge stays optically centred.
    return Transform.translate(
      offset: const Offset(0, -1.5),
      child: IconBadge(icon: icon, fill: fill ?? JwFill.purple, size: size),
    );
  }
}

/// A list row: ≥ 56 tall, 16 padding, leading icon well, title, optional
/// value text, trailing widget (toggle) and chevron. Tappable when [onTap].
class JwListRow extends StatefulWidget {
  const JwListRow({
    super.key,
    required this.title,
    this.icon,
    this.value,
    this.monoValue = false,
    this.trailing,
    this.chevron = false,
    this.destructive = false,
    this.onTap,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
    this.below,
    this.badgeFill,
  });

  final String title;
  final String? icon;

  /// Fill of the leading [icon] badge (DESIGN_SYSTEM §4 colour roles);
  /// purple when null. Destructive rows use a danger-tinted well.
  final JwFill? badgeFill;
  final String? value;

  /// Render [value] in mono (prices, versions).
  final bool monoValue;
  final Widget? trailing;
  final bool chevron;

  /// Danger colour for title and icon (Reset progress).
  final bool destructive;
  final VoidCallback? onTap;
  final VoidCallback? onHaptic;
  final String? semanticLabel;
  final bool? reduceMotion;

  /// Content under the row (e.g. a segmented control for Theme).
  final Widget? below;

  @override
  State<JwListRow> createState() => _JwListRowState();
}

class _JwListRowState extends State<JwListRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final reduce = JwReduceMotion.of(context, widget.reduceMotion);
    final titleColor = widget.destructive ? jw.danger : jw.textPrimary;
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            if (widget.icon != null) ...[
              JwIconWell(icon: widget.icon!, color: widget.destructive ? jw.danger : null, fill: widget.destructive ? null : widget.badgeFill),
              const SizedBox(width: 16),
            ],
            // With a value, the title keeps its natural width and the value
            // takes the rest (ellipsized), so a long value (an email) never
            // squeezes the title into wrapping.
            if (widget.value == null)
              Expanded(
                child: Text(widget.title, style: jw.text.body.copyWith(fontSize: 16.5, color: titleColor)),
              )
            else ...[
              Text(widget.title, maxLines: 1, style: jw.text.body.copyWith(fontSize: 16.5, color: titleColor)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: widget.monoValue
                      ? jw.text.numM.copyWith(fontSize: 15, color: jw.textMuted)
                      : jw.text.callout.copyWith(fontSize: 15.5, fontWeight: FontWeight.w400, color: jw.textMuted),
                ),
              ),
            ],
            if (widget.trailing != null) ...[const SizedBox(width: 8), widget.trailing!],
            if (widget.chevron) ...[
              const SizedBox(width: 8),
              JwIcon(JwIcons.chev, size: 18, color: jw.textMuted),
            ],
          ],
        ),
      ),
    );
    final content = widget.below == null
        ? row
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              row,
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 14), child: widget.below),
            ],
          );
    if (widget.onTap == null) {
      return Semantics(container: true, label: widget.semanticLabel, child: content);
    }
    return Semantics(
      container: true,
      button: true,
      label: widget.semanticLabel ?? [widget.title, ?widget.value].join(', '),
      excludeSemantics: true,
      onTap: _tap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: _tap,
        child: AnimatedContainer(
          duration: reduce ? JwMotion.instant : JwMotion.quick,
          color: _down ? jw.surfaceSunken.withValues(alpha: 0.6) : jw.surfaceSunken.withValues(alpha: 0),
          child: content,
        ),
      ),
    );
  }

  void _tap() {
    widget.onHaptic?.call();
    widget.onTap?.call();
  }
}

/// Tool knob: a [FillKnob] (58 pt coloured fill object, caption below,
/// optional purple count badge). [fill] defaults by icon: hint yellow,
/// undo sky, shuffle pink, anything else purple.
class JwToolKnob extends StatelessWidget {
  const JwToolKnob({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.onHaptic,
    this.badge,
    this.accentIcon = false,
    this.semanticLabel,
    this.reduceMotion,
    this.size = 58,
    this.fill,
  });

  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onHaptic;

  /// Count shown in the badge (null hides it).
  final int? badge;

  /// Unused since Clay Pop (the knob colour carries the meaning); kept for
  /// API compatibility.
  final bool accentIcon;
  final String? semanticLabel;
  final bool? reduceMotion;
  final double size;
  final JwFill? fill;

  /// The colour-role fill for a tool icon (DESIGN_SYSTEM §4).
  static JwFill fillFor(String icon) => switch (icon) {
    JwIcons.hint => JwFill.yellow,
    JwIcons.undo => JwFill.sky,
    JwIcons.shuffle => JwFill.pink,
    _ => JwFill.purple,
  };

  @override
  Widget build(BuildContext context) => FillKnob(
    icon: icon,
    label: label,
    fill: fill ?? fillFor(icon),
    onPressed: onPressed,
    onHaptic: onHaptic,
    badge: badge,
    semanticLabel: semanticLabel,
    reduceMotion: reduceMotion,
    size: size,
  );
}

/// Game tray: inset 16, radius 34, height 104, raised, children evenly
/// spaced.
class JwTray extends StatelessWidget {
  const JwTray({super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: 16), this.height = 104});

  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final double height;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.raised, radius: 34),
        child: SizedBox(
          height: height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: children,
          ),
        ),
      ),
    );
  }
}
