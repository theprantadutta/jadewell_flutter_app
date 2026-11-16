import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'analytics_sanitizer.dart';
import 'analytics_service.dart';

/// Firebase Analytics, used in release builds only (docs/ARCHITECTURE.md §0).
/// Every event goes through [AnalyticsSanitizer]; failures are swallowed so
/// analytics can never break a flow.
class FirebaseAnalyticsImpl implements AnalyticsService {
  FirebaseAnalyticsImpl([FirebaseAnalytics? analytics]) : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;

  /// Collection is on only in release builds. Called at start-up whichever
  /// implementation is active, so debug/profile builds also stop the SDK's
  /// automatic events (first_open, screen_view, session_start).
  static Future<void> configureCollection() async {
    try {
      await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(kReleaseMode);
    } catch (e) {
      debugPrint('analytics: setAnalyticsCollectionEnabled failed: $e');
    }
  }

  @override
  Future<void> log(String event, [Map<String, Object> params = const {}]) async {
    final name = AnalyticsSanitizer.eventName(event);
    if (name == null) return;
    final clean = AnalyticsSanitizer.params(params);
    try {
      if (name == AnalyticsEvents.appOpen) {
        await _analytics.logAppOpen(parameters: clean.isEmpty ? null : clean);
      } else {
        await _analytics.logEvent(name: name, parameters: clean.isEmpty ? null : clean);
      }
    } catch (e) {
      debugPrint('analytics: $name failed: $e');
    }
  }

  @override
  Future<void> screen(String name) async {
    try {
      final screen = AnalyticsSanitizer.screenName(name);
      await _analytics.logScreenView(screenName: screen, screenClass: screen);
    } catch (e) {
      debugPrint('analytics: screen failed: $e');
    }
  }
}
