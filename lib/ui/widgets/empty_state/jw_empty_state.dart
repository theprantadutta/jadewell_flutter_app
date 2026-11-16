import 'package:flutter/widgets.dart';

import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../jw_buttons.dart';
import '../jw_icon.dart';

/// Empty state (screens 17a–17c): a clay illustration, an h3-ish title, a
/// muted body and an optional primary action, all centred.
///
/// Pass any widget as [illustration] (e.g. [JwEmptyBars]) or an [icon] name
/// from [JwIcons] for a sunken icon disc.
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
  });

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
            : DecoratedBox(
                decoration: jw.clay(ClayLevel.sunken),
                child: SizedBox.square(
                  dimension: 88,
                  child: Center(child: JwIcon(icon!, size: 36, color: jw.textMuted)),
                ),
              ));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (art != null) ...[ExcludeSemantics(child: art), const SizedBox(height: 26)],
          Semantics(
            header: true,
            child: Text(title, textAlign: TextAlign.center, style: jw.text.h3.copyWith(fontSize: 22, height: 28 / 22)),
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
            JwButton.primary(
              label: actionLabel!,
              icon: actionIcon,
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

/// The statistics empty illustration: five sunken clay bars (17c).
class JwEmptyBars extends StatelessWidget {
  const JwEmptyBars({super.key, this.height = 84, this.barWidth = 28, this.gap = 10});

  final double height;
  final double barWidth;
  final double gap;

  static const _levels = [0.47, 0.75, 0.35, 1.0, 0.6];

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return SizedBox(
      height: height,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < _levels.length; i++) ...[
            if (i > 0) SizedBox(width: gap),
            DecoratedBox(
              decoration: jw.clay(ClayLevel.sunken, radius: barWidth / 2),
              child: SizedBox(width: barWidth, height: height * _levels[i]),
            ),
          ],
        ],
      ),
    );
  }
}
