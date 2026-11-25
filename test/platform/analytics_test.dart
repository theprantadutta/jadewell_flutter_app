import 'package:flutter/widgets.dart' show PageRouteBuilder, RouteSettings, SizedBox;
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_route_observer.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_sanitizer.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/platform/analytics/debug_print_analytics_impl.dart';
import 'package:jadewell_flutter_app/state/platform_bridge.dart';

class _Recorder implements AnalyticsService {
  final screens = <String>[];
  @override
  Future<void> log(String event, [Map<String, Object> params = const {}]) async {}
  @override
  Future<void> screen(String name) async => screens.add(name);
  @override
  Future<void> setUserProperty(String name, String? value) async => userProperties[name] = value;
  final userProperties = <String, String?>{};
}

void main() {
  group('event names', () {
    test('every AnalyticsEvents name is already valid and unchanged', () {
      for (final e in const [
        AnalyticsEvents.appOpen,
        AnalyticsEvents.onboardingStep,
        AnalyticsEvents.onboardingComplete,
        AnalyticsEvents.layoutStart,
        AnalyticsEvents.boardCleared,
        AnalyticsEvents.boardAbandon,
        AnalyticsEvents.hintUsed,
        AnalyticsEvents.undoUsed,
        AnalyticsEvents.shuffleUsed,
        AnalyticsEvents.deadlockShown,
        AnalyticsEvents.dailyStart,
        AnalyticsEvents.dailyComplete,
        AnalyticsEvents.starsEarned,
        AnalyticsEvents.layoutUnlockAd,
        AnalyticsEvents.friendAdded,
        AnalyticsEvents.streakRepaired,
        AnalyticsEvents.settingsChanged,
        AnalyticsEvents.accountLinked,
      ]) {
        expect(AnalyticsSanitizer.eventName(e), e);
      }
    });

    test('invalid characters, leading digits, length', () {
      expect(AnalyticsSanitizer.eventName('board cleared!'), 'board_cleared');
      expect(AnalyticsSanitizer.eventName('ad-shown.rewarded'), 'ad_shown_rewarded');
      expect(AnalyticsSanitizer.eventName('3stars'), 'e_3stars');
      expect(AnalyticsSanitizer.eventName('x' * 60), hasLength(40));
      expect(AnalyticsSanitizer.eventName('!!!'), isNull);
      expect(AnalyticsSanitizer.eventName(''), isNull);
    });

    test('reserved prefixes and reserved events are renamed', () {
      expect(AnalyticsSanitizer.eventName('firebase_thing'), 'jw_thing');
      expect(AnalyticsSanitizer.eventName('google_x'), 'jw_x');
      expect(AnalyticsSanitizer.eventName('ga_y'), 'jw_y');
      expect(AnalyticsSanitizer.eventName('ad_reward'), 'jw_ad_reward');
      expect(AnalyticsSanitizer.eventName('screen_view'), 'jw_screen_view');
    });
  });

  group('params', () {
    test('types: bools → 0/1, enums → name, durations → ms, nulls and NaN dropped', () {
      final p = AnalyticsSanitizer.params({
        'won': true,
        'lost': false,
        'time_ms': 1234,
        'ratio': 0.5,
        'nan': double.nan,
        'mode': _Mode.daily,
        'elapsed': const Duration(seconds: 2),
        'none': null,
      });
      expect(p, {'won': 1, 'lost': 0, 'time_ms': 1234, 'ratio': 0.5, 'mode': 'daily', 'elapsed': 2000});
    });

    test('strings capped at 100 chars, keys cleaned and capped at 40', () {
      final p = AnalyticsSanitizer.params({'layout id': 'a' * 150, 'k' * 50: 'v'});
      expect(p['layout_id'], hasLength(100));
      expect(p.keys.last, hasLength(40));
    });

    test('PII keys and e-mail-looking values are dropped', () {
      final p = AnalyticsSanitizer.params({
        'email': 'x@y.z',
        'display_name': 'Jade Fox',
        'uid': 'abc',
        'friend_code': 'JW-1234',
        'note': 'contact me at someone@example.com',
        'layout': 'turtle',
        'day': '2026-11-16',
      });
      expect(p, {'layout': 'turtle', 'day': '2026-11-16'});
    });

    test('at most 25 params', () {
      final p = AnalyticsSanitizer.params({for (var i = 0; i < 40; i++) 'p$i': i});
      expect(p, hasLength(25));
    });

    test('screen names are capped', () {
      expect(AnalyticsSanitizer.screenName('s' * 200), hasLength(100));
      expect(AnalyticsSanitizer.screenName('  '), 'unknown');
    });
  });

  group('user properties', () {
    test('names capped at 24 chars and cleaned like event names', () {
      expect(AnalyticsSanitizer.userPropertyName('ads_removed'), 'ads_removed');
      expect(AnalyticsSanitizer.userPropertyName('a' * 30), 'a' * 24);
      expect(AnalyticsSanitizer.userPropertyName('firebase_x'), 'jw_x');
      expect(AnalyticsSanitizer.userPropertyName('???'), isNull);
    });

    test('values capped at 36 chars; e-mail addresses and blanks dropped', () {
      expect(AnalyticsSanitizer.userPropertyValue('google'), 'google');
      expect(AnalyticsSanitizer.userPropertyValue('x' * 40), 'x' * 36);
      expect(AnalyticsSanitizer.userPropertyValue('a@b.co'), isNull);
      expect(AnalyticsSanitizer.userPropertyValue('  '), isNull);
      expect(AnalyticsSanitizer.userPropertyValue(null), isNull);
    });

    test('every AnalyticsUserProperties name is valid and unchanged', () {
      for (final n in const [
        AnalyticsUserProperties.account,
        AnalyticsUserProperties.adsRemoved,
        AnalyticsUserProperties.onboardingDone,
        AnalyticsUserProperties.theme,
      ]) {
        expect(AnalyticsSanitizer.userPropertyName(n), n);
      }
    });

    test('account kind from the Firebase providers', () {
      expect(PlatformBridge.accountKind(const []), 'guest');
      expect(PlatformBridge.accountKind(const ['google.com']), 'google');
      expect(PlatformBridge.accountKind(const ['apple.com', 'google.com']), 'apple');
      expect(PlatformBridge.accountKind(const ['password']), 'other');
    });

    test('DebugPrintAnalytics prints the sanitised user property', () async {
      final lines = <String>[];
      final a = DebugPrintAnalytics(printer: lines.add);
      await a.setUserProperty('account', 'guest');
      await a.setUserProperty('???', 'x');
      expect(lines, ['analytics: user property account = guest', 'analytics: dropped invalid user property "???"']);
    });
  });

  test('DebugPrintAnalytics prints the sanitised event', () async {
    final lines = <String>[];
    final a = DebugPrintAnalytics(printer: lines.add);
    await a.log('board_cleared', {'layout': 'turtle', 'email': 'a@b.co', 'hints': 2});
    await a.log('???');
    await a.screen('home');
    expect(lines, [
      'analytics: board_cleared {layout: turtle, hints: 2}',
      'analytics: dropped invalid event "???"',
      'analytics: screen home',
    ]);
  });

  test('AnalyticsRouteObserver logs named page routes once per change', () {
    final rec = _Recorder();
    final obs = AnalyticsRouteObserver(rec);
    PageRouteBuilder<void> route(String? name) => PageRouteBuilder<void>(
        pageBuilder: (_, _, _) => const SizedBox(), settings: RouteSettings(name: name));
    final home = route('home');
    final game = route('game');
    obs
      ..didPush(home, null)
      ..didPush(game, home)
      ..didPop(game, home)
      ..didPush(route(null), home)
      ..didReplace(newRoute: route('home'), oldRoute: home);
    expect(rec.screens, ['home', 'game', 'home']);
  });
}

enum _Mode { daily }
