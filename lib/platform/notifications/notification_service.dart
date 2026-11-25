/// One local notification to schedule.
class LocalReminder {
  const LocalReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});

  /// Stable id: scheduling the same id again replaces it.
  final int id;

  /// When it fires (an absolute instant; any time zone).
  final DateTime at;
  final String title;
  final String body;

  /// Handed back by [NotificationService.takeLaunchPayload] / [NotificationService.taps].
  final String payload;
}

/// Local notifications (the daily-board reminder, `ReminderController`).
///
/// No server push: everything is scheduled on the device, so guest players
/// get it too. Never asks for permission by itself: only
/// [requestPermission] shows the OS dialog, and only the reminder pre-prompt
/// and Settings → Daily reminder call it.
abstract interface class NotificationService {
  /// False where local notifications aren't wired (tests, desktop, web).
  bool get isSupported;

  /// Sets up the plugin and the tap callback. Safe to call more than once.
  Future<void> init();

  /// The OS lets the app post notifications right now (Android 13+ runtime
  /// permission or the app's notification switch; iOS authorisation).
  Future<bool> hasPermission();

  /// Shows the OS dialog where the platform has one (Android 13+, iOS);
  /// resolves to whether notifications are allowed afterwards.
  Future<bool> requestPermission();

  /// Replaces every pending reminder in [ids] with [reminders].
  Future<void> schedule(List<LocalReminder> reminders, {required Iterable<int> ids});

  /// Cancels pending and shown notifications with these ids.
  Future<void> cancel(Iterable<int> ids);

  /// The payload of the notification that cold-launched the app, once; null
  /// otherwise.
  Future<String?> takeLaunchPayload();

  /// Payloads of notifications tapped while the app was running (in the
  /// background or foreground).
  Stream<String> get taps;
}

class NoOpNotifications implements NotificationService {
  const NoOpNotifications();
  @override
  bool get isSupported => false;
  @override
  Future<void> init() async {}
  @override
  Future<bool> hasPermission() async => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> schedule(List<LocalReminder> reminders, {required Iterable<int> ids}) async {}
  @override
  Future<void> cancel(Iterable<int> ids) async {}
  @override
  Future<String?> takeLaunchPayload() async => null;
  @override
  Stream<String> get taps => const Stream.empty();
}
