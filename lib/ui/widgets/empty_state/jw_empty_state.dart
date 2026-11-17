import 'package:flutter/widgets.dart';

import '../../components/components.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../jw_icon.dart';

/// Empty state (screens 17a–17c): a clay illustration, an h3-ish title, a
/// muted body and an optional primary action, all centred.
///
/// Pass any widget as [illustration] (e.g. [JwEmptyBars]) or an [icon] name
/// from [JwIcons] for a 72 pt fill badge in [iconFill] (sky, "info", by
/// default).
class JwEmptyState extends StatelessWidget {
  const JwEmptyState({
    super.key,
    required this.title,
    this.body,
    this.illustration,
    this.icon,
    this.actionLabel,
    this.actionIcon,
    this.onAction,
    this.onHaptic,
    this.iconFill = JwFill.sky,
  });

  /// Fill of the [icon] badge.
  final JwFill iconFill;

  final String title;
  final String? body;
  final Widget? illustration;
  final String? icon;
  final String? actionLabel;

  /// [JwIcons] name shown in the action button (e.g. `JwIcons.play`).
  final String? actionIcon;
  final VoidCallback? onAction;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final art = illustration ??
        (icon == null
            ? null
            : IconBadge(icon: icon, fill: iconFill, size: 72));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (art != null) ...[ExcludeSemantics(child: art), const SizedBox(height: 26)],
          Semantics(
            header: true,
            child: Text(title, textAlign: TextAlign.center, style: jw.text.h3.copyWith(fontSize: 23, height: 28 / 23)),
          ),
          if (body != null) ...[
            const SizedBox(height: 10),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: jw.text.body.copyWith(fontSize: 16, color: jw.textMuted),
            ),
          ],
          if (actionLabel != null) ...[
            const SizedBox(height: 26),
            PrimaryButton(
              label: actionLabel!,
              icon: actionIcon,
              height: 62,
              onPressed: onAction,
              onHaptic: onHaptic,
              expand: true,
            ),
          ],
        ],
      ),
    );
  }
}

/// The statistics empty illustration (17c): five faded colour fill bars.
class JwEmptyBars extends StatelessWidget {
  const JwEmptyBars({super.key, this.height = 88, this.barWidth = 28, this.gap = 10});

  final double height;
  final double barWidth;
  final double gap;

  static const _levels = [0.47, 0.75, 0.35, 1.0, 0.6];
  static const _fills = [JwFill.sky, JwFill.pink, JwFill.mint, JwFill.yellow, JwFill.purple];

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    // One opacity layer over the whole static group, not one per bar.
    return Opacity(
      opacity: jw.isDark ? 0.5 : 0.45,
      child: SizedBox(
        height: height + 3,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < _levels.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: DecoratedBox(
                  decoration: jw.fill(_fills[i], radius: 12, edge: 3, glow: false),
                  child: SizedBox(width: barWidth, height: height * _levels[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
