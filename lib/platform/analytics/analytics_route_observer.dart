import 'dart:async';

import 'package:flutter/widgets.dart';

import 'analytics_service.dart';

/// Logs a screen view whenever the visible route changes. Attach it to the
/// router (`GoRouter(observers: [AnalyticsRouteObserver(analytics)])`); it
/// reads `Route.settings.name`, which go_router fills from `GoRoute.name`
/// (falling back to the path). Popups and unnamed routes are skipped, and the
/// same screen is not logged twice in a row.
class AnalyticsRouteObserver extends NavigatorObserver {
  AnalyticsRouteObserver(this._analytics, {String? Function(Route<dynamic> route)? nameOf})
      : _nameOf = nameOf ?? _defaultName;

  final AnalyticsService _analytics;
  final String? Function(Route<dynamic> route) _nameOf;
  String? _last;

  static String? _defaultName(Route<dynamic> route) => route is PageRoute ? route.settings.name : null;

  void _track(Route<dynamic>? route) {
    if (route == null) return;
    final name = _nameOf(route);
    if (name == null || name.isEmpty || name == _last) return;
    _last = name;
    unawaited(_analytics.screen(name));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _track(route);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _track(previousRoute);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _track(newRoute);

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _track(previousRoute);
}
