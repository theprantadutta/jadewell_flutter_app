import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import 'clay_pressable.dart';
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

/// 34 pt sunken icon well (leading slot of list rows).
class JwIconWell extends StatelessWidget {
  const JwIconWell({super.key, required this.icon, this.color, this.size = 34});

  final String icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.sunken, radius: 11),
      child: SizedBox.square(
        dimension: size,
        child: Center(child: JwIcon(icon, size: 20, color: color ?? jw.accent)),
      ),
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
  });

  final String title;
  final String? icon;
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
              JwIconWell(icon: widget.icon!, color: widget.destructive ? jw.danger : jw.accent),
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

/// Tool knob: 54 pt circle, surfaceHi → surfaceRaised gradient with chip
/// clay, caption label below, optional accent badge with a mono count.
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
    this.size = 54,
  });

  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onHaptic;

  /// Count shown in the badge (null hides it).
  final int? badge;

  /// Draw the icon in accent (Hint).
  final bool accentIcon;
  final String? semanticLabel;
  final bool? reduceMotion;
  final double size;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final deco = jw.clay(ClayLevel.chip, gradient: jw.knobGradient).copyWith(
      extraShadows: [ClayShadow(0, 8, 14, -6, jw.shadow)],
    );
    return Semantics(
      container: true,
      label: semanticLabel ?? (badge == null ? label : '$label, $badge left'),
      button: true,
      excludeSemantics: true,
      onTap: onPressed == null ? null : () {
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
                ClayPressable(
                  decoration: deco,
                  pressedDecoration: deco.copyWith(level: ClayLevel.pressed, extraShadows: const []),
                  onTap: onPressed,
                  onHaptic: onHaptic,
                  reduceMotion: reduceMotion,
                  width: size,
                  height: size,
                  child: Center(
                    child: JwIcon(icon, size: 23, color: accentIcon ? jw.accent : jw.textPrimary),
                  ),
                ),
                if (badge != null)
                  Positioned(
                    right: -6,
                    top: -5,
                    child: _Badge(count: badge!),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(label, style: jw.text.callout.copyWith(fontSize: 15, color: jw.textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.flat, color: jw.accent).copyWith(
        extraShadows: [ClayShadow(0, 2, 4, 0, jw.shadow)],
      ),
      child: SizedBox(
        height: 20,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Center(
              widthFactor: 1,
              child: Text(
                '$count',
                style: jw.text.numM.copyWith(fontSize: 11.5, fontWeight: FontWeight.w700, color: jw.onAccent, height: 1),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Game tray: inset 22, radius 32, height 96, e2, children evenly spaced.
class JwTray extends StatelessWidget {
  const JwTray({super.key, required this.children, this.margin = const EdgeInsets.symmetric(horizontal: 22)});

  final List<Widget> children;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.raised, radius: 32),
        child: SizedBox(
          height: 96,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: children,
          ),
        ),
      ),
    );
  }
}
