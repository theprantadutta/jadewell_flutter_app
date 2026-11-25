import 'dart:async';

import 'package:jadewell_flutter_app/platform/notifications/notification_service.dart';

/// Records what the reminder code asks of the platform.
class FakeNotifications implements NotificationService {
  FakeNotifications({this.permitted = false, this.grantOnRequest = true, this.launchPayload});

  bool permitted;
  bool grantOnRequest;
  String? launchPayload;
  int requests = 0;
  final List<LocalReminder> pending = [];
  final List<List<int>> cancelled = [];
  final StreamController<String> tapController = StreamController<String>.broadcast();

  @override
  bool get isSupported => true;
  @override
  Future<void> init() async {}
  @override
  Future<bool> hasPermission() async => permitted;
  @override
  Future<bool> requestPermission() async {
    requests++;
    if (grantOnRequest) permitted = true;
    return permitted;
  }

  @override
  Future<void> schedule(List<LocalReminder> reminders, {required Iterable<int> ids}) async {
    await cancel(ids);
    pending.addAll(reminders);
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    final list = ids.toList();
    cancelled.add(list);
    pending.removeWhere((r) => list.contains(r.id));
  }

  @override
  Future<String?> takeLaunchPayload() async {
    final p = launchPayload;
    launchPayload = null;
    return p;
  }

  @override
  Stream<String> get taps => tapController.stream;
}
