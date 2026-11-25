import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import '../game/game_widgets.dart';

/// The soft "Want a daily reminder?" ask on the cleared screen, before the
/// OS permission dialog. Pops true for Yes; Not now or a dismiss pops
/// false / null (`ReminderController.answerPrompt`).
class ReminderPromptSheet extends StatelessWidget {
  const ReminderPromptSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return JwSheet(
      semanticLabel: l.reminderPromptTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              const GameIconWell(icon: JwIcons.cal, fill: JwFill.mint),
              const SizedBox(width: 16),
              Expanded(child: Text(l.reminderPromptTitle, style: jw.text.h3.copyWith(fontSize: 21))),
            ],
          ),
          const SizedBox(height: 16),
          Text(l.reminderPromptBody, style: jw.text.body.copyWith(color: jw.textMuted)),
          const SizedBox(height: 22),
          JwButton.primary(
            label: l.reminderPromptYes,
            icon: JwIcons.check,
            expand: true,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          const SizedBox(height: 6),
          JwButton.tertiary(label: l.reminderPromptNotNow, onPressed: () => Navigator.of(context).pop(false)),
        ],
      ),
    );
  }
}
