import 'package:flutter/foundation.dart';

import 'analytics_sanitizer.dart';
import 'analytics_service.dart';

/// Debug/profile analytics: prints each event exactly as the release build
/// would send it (same sanitisation), and sends nothing.
class DebugPrintAnalytics implements AnalyticsService {
  DebugPrintAnalytics({void Function(String line)? printer}) : _print = printer ?? debugPrint;

  final void Function(String line) _print;

  @override
  Future<void> log(String event, [Map<String, Object> params = const {}]) async {
    final name = AnalyticsSanitizer.eventName(event);
    if (name == null) {
      _print('analytics: dropped invalid event "$event"');
      return;
    }
    final clean = AnalyticsSanitizer.params(params);
    _print(clean.isEmpty ? 'analytics: $name' : 'analytics: $name $clean');
  }

  @override
  Future<void> screen(String name) async {
    _print('analytics: screen ${AnalyticsSanitizer.screenName(name)}');
  }

  @override
  Future<void> setUserProperty(String name, String? value) async {
    final key = AnalyticsSanitizer.userPropertyName(name);
    if (key == null) {
      _print('analytics: dropped invalid user property "$name"');
      return;
    }
    _print('analytics: user property $key = ${AnalyticsSanitizer.userPropertyValue(value)}');
  }
}
