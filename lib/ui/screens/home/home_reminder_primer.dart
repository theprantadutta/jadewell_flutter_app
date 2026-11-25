import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../state/reminder_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../reminder/reminder_primer_sheet.dart';
import '../settings/screen_chrome.dart';

/// Opens the reminder primer on Home at a calm moment: [settle] after Home
/// appears, only while Home is the current route (nothing pushed or open
/// on top), and only when `ReminderController.homePromptAttempt` allows it
/// (a board cleared, setting on, OS permission missing, the retry rules of
/// `ReminderPromptPolicy`, nothing else one-time this app session).
///
/// Home is rebuilt by `context.go` from the cleared screen, so returning
/// to it after the first clear (the Sprout warm-up counts) is the moment.
class HomeReminderPrimer extends ConsumerStatefulWidget {
  const HomeReminderPrimer({super.key, required this.child, this.settle = const Duration(milliseconds: 900)});

  final Widget child;
  final Duration settle;

  @override
  ConsumerState<HomeReminderPrimer> createState() => _HomeReminderPrimerState();
}

class _HomeReminderPrimerState extends ConsumerState<HomeReminderPrimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.settle, () => unawaited(_maybeAsk()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _homeIsCurrent => mounted && (ModalRoute.of(context)?.isCurrent ?? true);

  Future<void> _maybeAsk() async {
    if (!_homeIsCurrent) return;
    final reminders = ref.read(reminderControllerProvider);
    final attempt = await reminders.homePromptAttempt();
    if (attempt == null || !mounted || !_homeIsCurrent) return;
    reminders.markPrimerShown();
    final yes = await showReminderPrimer(context);
    final result = await reminders.answerPrompt(accepted: yes, source: ReminderPromptSource.home);
    if (!mounted) return;
    ref.invalidate(reminderPermissionProvider);
    if (result == ReminderPromptResult.accepted) {
      showJwToast(context, AppLocalizations.of(context).reminderPromptOn);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
