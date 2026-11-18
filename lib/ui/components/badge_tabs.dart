import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import '../widgets/reduce_motion.dart';
import 'icon_badge.dart';

/// One option of a [BadgeTabs]: its label, icon and the fill of its badge
/// (colour-role map: yellow today/light, sky week/system, mint friends,
/// purple dark…).
class BadgeTab {
  const BadgeTab({required this.label, required this.icon, required this.fill});

  final String label;
  final String icon;
  final JwFill fill;
}

/// Clay Pop picker for 2–4 options (replaces the sunken segmented control):
/// each option is its own white / lifted-indigo clay card with a coloured
/// icon badge above its label. The selected card is raised, lifted 2 pt and
/// ringed in purple; the others sit flat at chip elevation with muted text.
class BadgeTabs<T> extends StatelessWidget {
  const BadgeTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    this.onHaptic,
    this.reduceMotion,
    this.gap = 10,
    this.inset = false,
  });

  /// Value → tab, in display order.
  final Map<T, BadgeTab> tabs;
  final T selected;
  final ValueChanged<T>? onChanged;
  final VoidCallback? onHaptic;
  final bool? reduceMotion;
  final double gap;

  /// Unselected cards sit sunken instead of at chip elevation. Use it when
  /// the tabs live inside a raised white card (Settings), where white chips
  /// would vanish into the card.
  final bool inset;

  @override
  Widget build(BuildContext context) {
    final keys = tabs.keys.toList();
    return Row(
      children: [
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: _BadgeTabCard(
              tab: tabs[keys[i]]!,
              selected: keys[i] == selected,
              inset: inset,
              reduceMotion: reduceMotion,
              onTap: onChanged == null ? null : () => _pick(keys[i]),
            ),
          ),
        ],
      ],
    );
  }

  void _pick(T k) {
    if (k == selected) return;
    onHaptic?.call();
    onChanged?.call(k);
  }
}

class _BadgeTabCard extends StatelessWidget {
  const _BadgeTabCard({required this.tab, required this.selected, required this.onTap, required this.inset, this.reduceMotion});

  final BadgeTab tab;
  final bool selected;
  final bool inset;
  final VoidCallback? onTap;
  final bool? reduceMotion;

  static const double _radius = 20;
  static const double _ring = 2.5;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final reduce = JwReduceMotion.of(context, reduceMotion);
    final duration = reduce ? Duration.zero : JwMotion.quick;
    final label = Text(
      tab.label,
      maxLines: 1,
      softWrap: false,
      style: jw.text.callout.copyWith(
        fontSize: 14,
        color: selected ? jw.textPrimary : jw.textMuted,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: tab.label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedSlide(
          // 2 pt lift for the chosen card (fraction of a ~72 pt card).
          offset: Offset(0, selected ? -0.028 : 0),
          duration: duration,
          curve: JwMotion.springPop,
          child: DecoratedBox(
            decoration: jw.clay(selected ? ClayLevel.raised : (inset ? ClayLevel.sunken : ClayLevel.chip), radius: _radius),
            child: AnimatedContainer(
              duration: duration,
              curve: JwMotion.standard,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_radius),
                border: Border.all(color: selected ? jw.tileSelected : JwBase.transparent, width: _ring),
              ),
              padding: const EdgeInsets.fromLTRB(6, 9, 6, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconBadge(icon: tab.icon, fill: tab.fill, size: 30),
                  const SizedBox(height: 6),
                  FittedBox(fit: BoxFit.scaleDown, child: label),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
