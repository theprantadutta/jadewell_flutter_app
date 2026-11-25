/// Which copy a reminder carries.
enum ReminderMessage {
  /// "Keep your N-day streak going": the day-1 reminder after the player
  /// cleared today's daily with a streak of [ReminderPolicy.minStreakForCopy]+.
  streak,

  /// "Today's daily board is ready": every other day-1 reminder.
  daily,

  /// "A fresh board is waiting": days 2 and 3, when the player didn't come
  /// back after the first one (the streak has lapsed by then).
  comeback,
}

/// One reminder the policy wants on the device.
class PlannedReminder {
  const PlannedReminder({required this.day, required this.at, required this.message, required this.streak});

  /// 1 = the next day, 2 = the day after, …
  final int day;

  /// Local wall-clock time it fires.
  final DateTime at;
  final ReminderMessage message;

  /// The streak the copy names ([ReminderMessage.streak] only).
  final int streak;

  /// The notification payload (`reminder:<day>:<message>`), parsed back by
  /// [ReminderPayload.parse] when the player taps it.
  String get payload => 'reminder:$day:${message.name}';
}

/// What a tapped reminder's payload says.
class ReminderPayload {
  const ReminderPayload(this.day, this.message);

  final int day;
  final ReminderMessage message;

  static ReminderPayload? parse(String? raw) {
    final parts = raw?.split(':');
    if (parts == null || parts.length != 3 || parts[0] != 'reminder') return null;
    final day = int.tryParse(parts[1]);
    final message = ReminderMessage.values.where((m) => m.name == parts[2]).firstOrNull;
    if (day == null || message == null) return null;
    return ReminderPayload(day, message);
  }
}

/// When the daily-board reminder fires and what it says. Pure Dart; the
/// clock is the caller's.
///
/// Each time the app goes to the background the pending reminders are
/// replaced by a fresh plan; opening the app cancels them:
///
/// * Day 1: [delay] (24 h) after now, clamped into [earliestHour]:00 –
///   [latestHour]:00 local, so it never lands at night (23:30 → 20:00 the
///   next day; 01:00 → 10:00 the next day).
/// * Days 2 … [maxUnanswered]: the same wall-clock time on the following
///   days. These only fire if the player still hasn't opened the app, so
///   [maxUnanswered] (3) is the most reminders anyone gets in a row without
///   coming back; then nothing more until they open the app again.
/// * Nothing at all unless the setting is on, the OS allows notifications
///   and the player has played at least one board.
class ReminderPolicy {
  const ReminderPolicy({
    this.delay = const Duration(hours: 24),
    this.earliestHour = 10,
    this.latestHour = 20,
    this.maxUnanswered = 3,
    this.minStreakForCopy = 2,
    this.minGamesPlayed = 1,
  });

  final Duration delay;
  final int earliestHour;
  final int latestHour;
  final int maxUnanswered;
  final int minStreakForCopy;
  final int minGamesPlayed;

  /// Day-1 fire time for a player who leaves at [now] (local).
  DateTime firstFireTime(DateTime now) {
    final t = now.add(delay);
    if (t.hour < earliestHour) return DateTime(t.year, t.month, t.day, earliestHour);
    if (t.hour > latestHour || (t.hour == latestHour && (t.minute > 0 || t.second > 0))) {
      return DateTime(t.year, t.month, t.day, latestHour);
    }
    return DateTime(t.year, t.month, t.day, t.hour, t.minute);
  }

  ReminderMessage messageFor({required int day, required int streak, required bool clearedToday}) {
    if (day > 1) return ReminderMessage.comeback;
    return clearedToday && streak >= minStreakForCopy ? ReminderMessage.streak : ReminderMessage.daily;
  }

  /// The reminders to schedule when the player leaves at [now].
  List<PlannedReminder> plan({
    required DateTime now,
    required bool enabled,
    required bool permitted,
    required int gamesPlayed,
    required int streak,
    required bool clearedToday,
  }) {
    if (!enabled || !permitted || gamesPlayed < minGamesPlayed) return const [];
    final first = firstFireTime(now);
    return [
      for (var day = 1; day <= maxUnanswered; day++)
        PlannedReminder(
          day: day,
          // Calendar days, not 24 h steps, so a DST change keeps the time.
          at: DateTime(first.year, first.month, first.day + day - 1, first.hour, first.minute),
          message: messageFor(day: day, streak: streak, clearedToday: clearedToday),
          streak: streak,
        ),
    ];
  }
}

/// When the soft "Want a daily reminder?" sheet may appear on the cleared
/// screen: once ever, after the player's first or second cleared board,
/// only while the setting is on and the OS permission is still missing.
/// The cleared screen adds the stacking rules (never with the review sheet
/// or after an interstitial).
class ReminderPromptPolicy {
  const ReminderPromptPolicy({this.minClears = 1, this.maxClears = 2});

  final int minClears;
  final int maxClears;

  bool shouldOffer({
    required bool supported,
    required bool alreadyDecided,
    required bool enabled,
    required bool permitted,
    required int boardsCleared,
  }) =>
      supported && !alreadyDecided && enabled && !permitted && boardsCleared >= minClears && boardsCleared <= maxClears;
}
