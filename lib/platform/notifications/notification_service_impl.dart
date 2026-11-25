import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'notification_service.dart';

/// [NotificationService] on `package:flutter_local_notifications` (Android
/// and iOS).
///
/// * Android: inexact alarms (`inexactAllowWhileIdle`), so no exact-alarm
///   permission; the small icon is the white `ic_stat_jadewell` drawable
///   (kept through resource shrinking by `res/raw/keep.xml`); channel
///   `daily_reminder` at default importance (sound, no heads-up).
/// * iOS: initialised without asking; [requestPermission] asks for alert
///   and sound only.
/// * Times are scheduled as UTC instants, so no time-zone database is
///   needed: the policy already picked the local wall-clock time.
class LocalNotificationService implements NotificationService {
  LocalNotificationService({required this.channelName, required this.channelDescription, this.accent});

  /// Shown in the OS notification settings (localised by main.dart).
  final String channelName;
  final String channelDescription;

  /// Android accent for the small icon.
  final Color? accent;

  static const _channelId = 'daily_reminder';
  static const _smallIcon = 'ic_stat_jadewell';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController<String>.broadcast();
  Future<void>? _init;
  bool _launchTaken = false;

  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  @override
  bool get isSupported => _android || _ios;

  @override
  Future<void> init() => _init ??= _doInit();

  Future<void> _doInit() async {
    if (!isSupported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_smallIcon),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null) _taps.add(p);
        },
      );
    } catch (e) {
      debugPrint('notifications: init failed: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _iosPlugin =>
      _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> hasPermission() async {
    if (!isSupported) return false;
    await init();
    try {
      if (_android) return await _androidPlugin?.areNotificationsEnabled() ?? false;
      return (await _iosPlugin?.checkPermissions())?.isEnabled ?? false;
    } catch (e) {
      debugPrint('notifications: permission check failed: $e');
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!isSupported) return false;
    await init();
    try {
      if (_android) {
        // Below Android 13 there is no dialog; this reports the app switch.
        await _androidPlugin?.requestNotificationsPermission();
        return await _androidPlugin?.areNotificationsEnabled() ?? false;
      }
      return await _iosPlugin?.requestPermissions(alert: true, sound: true) ?? false;
    } catch (e) {
      debugPrint('notifications: permission request failed: $e');
      return false;
    }
  }

  NotificationDetails get _details => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          channelName,
          channelDescription: channelDescription,
          icon: _smallIcon,
          color: accent,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true, presentBadge: false),
      );

  @override
  Future<void> schedule(List<LocalReminder> reminders, {required Iterable<int> ids}) async {
    if (!isSupported) return;
    await init();
    await cancel(ids);
    final now = DateTime.now();
    for (final r in reminders) {
      if (!r.at.isAfter(now)) continue;
      try {
        await _plugin.zonedSchedule(
          id: r.id,
          title: r.title,
          body: r.body,
          payload: r.payload,
          scheduledDate: tz.TZDateTime.from(r.at.toUtc(), tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (e) {
        debugPrint('notifications: schedule ${r.id} failed: $e');
      }
    }
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    if (!isSupported) return;
    await init();
    for (final id in ids) {
      try {
        await _plugin.cancel(id: id);
      } catch (e) {
        debugPrint('notifications: cancel $id failed: $e');
      }
    }
  }

  @override
  Future<String?> takeLaunchPayload() async {
    if (!isSupported || _launchTaken) return null;
    _launchTaken = true;
    await init();
    try {
      final d = await _plugin.getNotificationAppLaunchDetails();
      if (d == null || !d.didNotificationLaunchApp) return null;
      return d.notificationResponse?.payload;
    } catch (e) {
      debugPrint('notifications: launch details failed: $e');
      return null;
    }
  }

  @override
  Stream<String> get taps => _taps.stream;
}
