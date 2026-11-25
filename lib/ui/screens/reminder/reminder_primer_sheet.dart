import 'package:material_ui/material_ui.dart';

import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import '../game/game_widgets.dart';

/// Opens the reminder primer as a bottom sheet. True for "Turn on
/// reminders"; false or null for "Not now" or a dismiss.
Future<bool> showReminderPrimer(BuildContext context) async =>
    await showGameModal<bool>(context, bottom: true, builder: (_) => const ReminderPrimerSheet()) ?? false;

/// The reminder primer ("Never miss a daily board"): says what the daily
/// reminder brings in Jadewell's own words before the one-shot OS dialog,
/// which only "Turn on reminders" leads to (`ReminderController.answerPrompt`).
/// Opened by Home at a calm moment and by Settings → Daily reminder.
class ReminderPrimerSheet extends StatelessWidget {
  const ReminderPrimerSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    // Scrolls instead of overflowing on a short screen at a large text size.
    return SingleChildScrollView(
      child: JwSheet(
        semanticLabel: l.reminderPromptTitle,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Center(child: GameIconWell(icon: JwIcons.bell, fill: JwFill.mint, size: 68)),
            const SizedBox(height: 14),
            Text(l.reminderPromptTitle, textAlign: TextAlign.center, style: jw.text.h3.copyWith(fontSize: 22)),
            const SizedBox(height: 6),
            Text(
              l.reminderPromptBody,
              textAlign: TextAlign.center,
              style: jw.text.callout.copyWith(fontWeight: FontWeight.w400, color: jw.textMuted),
            ),
            const SizedBox(height: 20),
            _Benefit(icon: JwIcons.cal, fill: JwFill.sky, title: l.reminderPromptFreshTitle, body: l.reminderPromptFreshBody),
            const SizedBox(height: 14),
            _Benefit(icon: JwIcons.flame, fill: JwFill.coral, title: l.reminderPromptStreakTitle, body: l.reminderPromptStreakBody),
            const SizedBox(height: 14),
            _Benefit(icon: JwIcons.moon, fill: JwFill.purple, title: l.reminderPromptQuietTitle, body: l.reminderPromptQuietBody),
            const SizedBox(height: 22),
            JwButton.primary(
              label: l.reminderPromptYes,
              icon: JwIcons.bell,
              expand: true,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 6),
            JwButton.tertiary(label: l.reminderPromptNotNow, onPressed: () => Navigator.of(context).pop(false)),
          ],
        ),
      ),
    );
  }
}

/// One benefit row: a small fill badge, a bold line and a muted one-liner.
class _Benefit extends StatelessWidget {
  const _Benefit({required this.icon, required this.fill, required this.title, required this.body});

  final String icon;
  final JwFill fill;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBadge(icon: icon, fill: fill, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: jw.text.callout.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(body, style: jw.text.caption.copyWith(color: jw.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
