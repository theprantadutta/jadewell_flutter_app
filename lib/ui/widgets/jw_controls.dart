import 'package:flutter/widgets.dart';

import '../theme/clay.dart';
import '../theme/jw_theme.dart';
import '../theme/jw_tokens.dart';
import 'clay_pressable.dart';
import 'reduce_motion.dart';

LinearGradient _accentFill(JwTheme jw) => LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color.lerp(jw.accent, const Color(0xFFFFFFFF), 0.18)!, jw.accent],
);

/// Progress track: 14 tall, radius 7, e0, padding 3; accent fill 8 tall with
/// a highlight. Width animates over 1000 ms easeOutSoft (150 ms linear when
/// reducing motion).
class JwProgressTrack extends StatelessWidget {
  const JwProgressTrack({super.key, required this.value, this.semanticLabel, this.reduceMotion});

  /// 0…1.
  final double value;
  final String? semanticLabel;
  final bool? reduceMotion;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final reduce = JwReduceMotion.of(context, reduceMotion);
    final v = value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      value: '${(v * 100).round()}%',
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.sunken, radius: 7),
        child: SizedBox(
          height: 14,
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: v),
                duration: reduce ? const Duration(milliseconds: 150) : const Duration(milliseconds: 1000),
                curve: reduce ? JwMotion.linear : JwMotion.easeOutSoft,
                builder: (context, t, _) => FractionallySizedBox(
                  widthFactor: t,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: _accentFill(jw),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const SizedBox(height: 8),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented progress: 22 tall, e0, [segments] slots with 4 pt gaps, the
/// first [filled] in accent. A newly filled segment pops (600 ms springPop).
class JwSegmentedProgress extends StatelessWidget {
  const JwSegmentedProgress({
    super.key,
    required this.segments,
    required this.filled,
    this.semanticLabel,
    this.reduceMotion,
  });

  final int segments;
  final int filled;
  final String? semanticLabel;
  final bool? reduceMotion;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final reduce = JwReduceMotion.of(context, reduceMotion);
    return Semantics(
      label: semanticLabel,
      value: '$filled of $segments',
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.sunken, radius: 11),
        child: SizedBox(
          height: 22,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (var i = 0; i < segments; i++) ...[
                  if (i > 0) const SizedBox(width: 4),
                  Expanded(
                    child: AnimatedScale(
                      scale: i < filled ? 1 : 0.6,
                      duration: reduce ? Duration.zero : JwMotion.slow,
                      curve: JwMotion.springPop,
                      child: AnimatedOpacity(
                        opacity: i < filled ? 1 : 0,
                        duration: reduce ? const Duration(milliseconds: 150) : JwMotion.quick,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: _accentFill(jw),
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
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

/// Toggle: 52 × 32 sunken track, 24 pt e1 knob. On: accent track, knob at
/// x 24. Knob slides 220 ms springSoft; track colour crossfades.
class JwToggle extends StatelessWidget {
  const JwToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.onHaptic,
    this.semanticLabel,
    this.reduceMotion,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  /// Selection tick hook.
  final VoidCallback? onHaptic;
  final String? semanticLabel;
  final bool? reduceMotion;

  static const _dur = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final reduce = JwReduceMotion.of(context, reduceMotion);
    final enabled = onChanged != null;
    final off = jw.clay(ClayLevel.sunken, radius: 16);
    final on = jw.clay(ClayLevel.sunken, radius: 16, color: jw.accent);
    final knobColor = value ? (jw.isDark ? jw.tileFace : jw.surfaceHi) : (jw.isDark ? const Color(0xFF4A423D) : jw.surfaceHi);
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      onTap: enabled ? _toggle : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: enabled ? _toggle : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: kJwMinHitTarget, minHeight: kJwMinHitTarget),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: value ? 1 : 0),
                duration: reduce ? JwMotion.instant : _dur,
                curve: reduce ? JwMotion.linear : JwMotion.springSoft,
                builder: (context, t, _) => SizedBox(
                  width: 52,
                  height: 32,
                  child: DecoratedBox(
                    decoration: ClayBlendDecoration(off, on, t.clamp(0.0, 1.0)),
                    child: Stack(
                      children: [
                        Positioned(
                          left: 4 + 20 * t,
                          top: 4,
                          child: DecoratedBox(
                            decoration: jw.clay(ClayLevel.chip, color: knobColor),
                            child: const SizedBox(width: 24, height: 24),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggle() {
    onHaptic?.call();
    onChanged?.call(!value);
  }
}

/// Segmented control: 36 tall sunken track; the selection is a raised pill
/// that slides 280 ms springSoft.
class JwSegmented<T> extends StatelessWidget {
  const JwSegmented({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
    this.onHaptic,
    this.reduceMotion,
  });

  /// Value → label, in display order.
  final Map<T, String> segments;
  final T selected;
  final ValueChanged<T>? onChanged;
  final VoidCallback? onHaptic;
  final bool? reduceMotion;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final reduce = JwReduceMotion.of(context, reduceMotion);
    final keys = segments.keys.toList();
    final index = keys.indexOf(selected).clamp(0, keys.length - 1);
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 6) / keys.length;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTapUp: onChanged == null
              ? null
              : (d) => _pick(keys[((d.localPosition.dx - 3) / w).floor().clamp(0, keys.length - 1)]),
          child: Padding(
            // Visual track is 36 tall; the padding takes the hit area to 44.
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: DecoratedBox(
              decoration: jw.clay(ClayLevel.sunken, radius: 18),
              child: SizedBox(
                height: 36,
                child: Padding(
                  padding: const EdgeInsets.all(3),
                  child: Stack(
                    children: [
                      AnimatedPositioned(
                        left: w * index,
                        top: 0,
                        bottom: 0,
                        width: w,
                        duration: reduce ? Duration.zero : JwMotion.base,
                        curve: JwMotion.springSoft,
                        child: DecoratedBox(decoration: jw.clay(ClayLevel.chip)),
                      ),
                      Row(
                        children: [
                          for (final k in keys)
                            Expanded(
                              child: Semantics(
                                button: true,
                                selected: k == selected,
                                label: segments[k],
                                excludeSemantics: true,
                                onTap: onChanged == null ? null : () => _pick(k),
                                child: Center(
                                  child: AnimatedDefaultTextStyle(
                                    duration: reduce ? Duration.zero : JwMotion.quick,
                                    style: jw.text.callout.copyWith(
                                      fontSize: 15,
                                      color: k == selected ? jw.textPrimary : jw.textMuted,
                                      fontWeight: k == selected ? FontWeight.w600 : FontWeight.w500,
                                    ),
                                    child: Text(segments[k]!),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _pick(T k) {
    if (k == selected) return;
    onHaptic?.call();
    onChanged?.call(k);
  }
}
