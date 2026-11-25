import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/models/settings.dart';
import 'package:jadewell_flutter_app/data/repositories/memory_repositories.dart';
import 'package:jadewell_flutter_app/platform/ads/ad_service.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/platform/display/display_service.dart';
import 'package:jadewell_flutter_app/platform/notifications/notification_service.dart';
import 'package:jadewell_flutter_app/platform/store_listing/store_listing_service.dart';
import 'package:jadewell_flutter_app/state/app_providers.dart';
import 'package:jadewell_flutter_app/state/data_providers.dart';
import 'package:jadewell_flutter_app/state/entitlement_providers.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/state/session_controller.dart';
import 'package:jadewell_flutter_app/state/social_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/settings/settings_screen.dart';
import 'package:jadewell_flutter_app/ui/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../iap/fakes.dart' show FakePurchaseService;
import '../../state/fake_notifications.dart';
import '../../state/store_listing_controller_test.dart' show FakeStore;
import '../../ui/golden_helpers.dart' show loadJwFonts;
import '../meta_checks.dart';
import 'harness.dart';

void main() {
  late MemorySettingsRepository repo;
  late RecordingAnalytics analytics;
  late RecordingAudio audio;
  late RecordingHaptics haptics;

  setUpAll(loadJwFonts);

  setUp(() {
    repo = MemorySettingsRepository();
    analytics = RecordingAnalytics();
    audio = RecordingAudio();
    haptics = RecordingHaptics();
  });

  Future<void> pump(
    WidgetTester tester, {
    bool adsRemoved = false,
    Brightness brightness = Brightness.light,
    Size size = const Size(390, 844),
    DisplayService display = const NoOpDisplay(),
    StoreListingService store = const NoOpStoreListing(),
    NotificationService notifications = const NoOpNotifications(),
    SharedPreferences? prefs,
  }) =>
      pumpScreen(
        tester,
        const SettingsScreen(),
        brightness: brightness,
        size: size,
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repo),
          analyticsProvider.overrideWithValue(analytics),
          audioProvider.overrideWithValue(audio),
          hapticsProvider.overrideWithValue(haptics),
          adServiceProvider.overrideWithValue(FakeAdService(adsRemoved: adsRemoved)),
          purchaseServiceProvider.overrideWithValue(FakePurchaseService()), // store price $1.99
          sessionProvider.overrideWith(() => FakeSession(const BackendSession(identity: guestIdentity, user: testUser))),
          appVersionProvider.overrideWith((ref) async => '1.0.0 (1)'),
          displayServiceProvider.overrideWithValue(display),
          storeListingProvider.overrideWithValue(store),
          notificationServiceProvider.overrideWithValue(notifications),
          if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

  Finder toggleFor(String label) => find.byWidgetPredicate((w) => w is JwToggle && w.semanticLabel == label);

  testWidgets('shows every row of the design plus Music and Sound effects', (tester) async {
    await pump(tester);
    for (final text in ['Settings', 'FEEDBACK', 'Music', 'Sound effects', 'Haptics', 'DISPLAY', 'Theme', 'Show timer']) {
      expect(find.text(text), findsOneWidget, reason: text);
    }
    await tester.scrollUntilVisible(find.text('Reset progress'), 200);
    expect(find.text('Account'), findsWidgets);
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text(r'$1.99'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Ad privacy choices'), 200);
    expect(find.text('LEGAL'), findsOneWidget);
    expect(find.text('Ad privacy choices'), findsOneWidget);
  });

  for (final (label, route) in [
    ('Privacy policy', '/legal/privacy'),
    ('Terms of use', '/legal/terms'),
    ('Refund policy', '/legal/refund'),
  ]) {
    testWidgets('legal: $label opens the in-app document', (tester) async {
      await pump(tester, size: const Size(390, 1600));
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      expect(find.text('route:$route'), findsOneWidget);
    });
  }

  testWidgets('high refresh rate: shown on a 120 Hz screen, off by default, persists', (tester) async {
    final display = _FakeDisplay(const DisplayRates(current: 60, max: 120, supported: [60, 120]));
    await pump(tester, display: display);
    expect(find.text('High refresh rate'), findsOneWidget);
    expect(find.textContaining('Up to 120 Hz'), findsOneWidget);
    final t = tester.widget<JwToggle>(toggleFor('High refresh rate'));
    expect(t.value, isFalse);
    t.onChanged!(true);
    await tester.pump(const Duration(seconds: 1));
    expect((await repo.read()).highRefreshRate, isTrue);
    expect(analytics.events.last.$2, {'setting': 'high_refresh_rate'});
  });

  testWidgets('high refresh rate: hidden on a 60 Hz screen and where it cannot be controlled', (tester) async {
    await pump(tester, display: _FakeDisplay(const DisplayRates(current: 60, max: 60, supported: [60])));
    expect(find.text('High refresh rate'), findsNothing);
    await pump(tester); // NoOpDisplay: iOS, web, tests
    expect(find.text('High refresh rate'), findsNothing);
  });

  testWidgets('daily reminder: on only with permission; switching on asks the OS; off persists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final notifications = FakeNotifications();
    await pump(tester, notifications: notifications, prefs: prefs);
    expect(find.text('Daily reminder'), findsOneWidget);
    expect(find.textContaining('Never at night'), findsOneWidget);
    // On in the database, but the OS hasn't allowed it yet: shown off.
    expect(tester.widget<JwToggle>(toggleFor('Daily reminder')).value, isFalse);

    tester.widget<JwToggle>(toggleFor('Daily reminder')).onChanged!(true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(notifications.requests, 1);
    expect(tester.widget<JwToggle>(toggleFor('Daily reminder')).value, isTrue);
    expect((await repo.read()).dailyReminder, isTrue);

    tester.widget<JwToggle>(toggleFor('Daily reminder')).onChanged!(false);
    await tester.pump(const Duration(milliseconds: 100));
    expect((await repo.read()).dailyReminder, isFalse);
    expect(notifications.cancelled, isNotEmpty);
    expect(tester.widget<JwToggle>(toggleFor('Daily reminder')).value, isFalse);
    expect(analytics.events.where((e) => e.$1 == 'settings_changed').last.$2, {'setting': 'daily_reminder'});
  });

  testWidgets('daily reminder: the OS refusing leaves it off and says where to turn it on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await pump(tester, notifications: FakeNotifications(grantOnRequest: false), prefs: prefs);
    tester.widget<JwToggle>(toggleFor('Daily reminder')).onChanged!(true);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<JwToggle>(toggleFor('Daily reminder')).value, isFalse);
    expect(find.textContaining('Notifications are off for Jadewell'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('daily reminder: hidden where notifications are not supported', (tester) async {
    await pump(tester);
    expect(find.text('Daily reminder'), findsNothing);
  });

  testWidgets('support: Rate Jadewell opens the store page; App updates checks Play', (tester) async {
    final store = FakeStore(const UpdateCheck(state: UpdateState.upToDate));
    await pump(tester, store: store, size: const Size(390, 1600));
    await tester.scrollUntilVisible(find.text('App updates'), 200);
    await tester.tap(find.text('Rate Jadewell'));
    await tester.pump();
    expect(store.calls, ['listing']);
    await tester.tap(find.text('App updates'));
    await tester.pump();
    expect(store.calls.last, 'check');
    expect(find.text('You have the latest version.'), findsOneWidget);
    expect(find.text('Up to date'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('support: no Rate or App updates rows without a store', (tester) async {
    await pump(tester, size: const Size(390, 1600));
    expect(find.text('Rate Jadewell'), findsNothing);
    expect(find.text('App updates'), findsNothing);
  });

  testWidgets('support has a Contact us row and the email is not shown', (tester) async {
    await pump(tester, size: const Size(390, 1600));
    expect(find.text('Contact us'), findsOneWidget);
    expect(find.textContaining('prantadutta1997@gmail.com', findRichText: true), findsNothing);
  });

  testWidgets('toggles persist, reach the services and log the setting name', (tester) async {
    await pump(tester);

    await tester.tap(toggleFor('Music'));
    await tester.pump();
    expect((await repo.read()).music, isFalse);
    expect(audio.music, isFalse);

    await tester.tap(toggleFor('Sound effects'));
    await tester.pump();
    expect((await repo.read()).soundEffects, isFalse);
    expect(audio.sfx, isFalse);

    await tester.tap(toggleFor('Haptics'));
    await tester.pump();
    expect((await repo.read()).haptics, isFalse);
    expect(haptics.enabled, isFalse);

    await tester.tap(toggleFor('Show timer'));
    await tester.pump();
    expect((await repo.read()).showTimer, isFalse);

    await tester.tap(find.text('Dark'));
    await tester.pump();
    expect((await repo.read()).theme, ThemePreference.dark);

    expect(
      analytics.events.where((e) => e.$1 == AnalyticsEvents.settingsChanged).map((e) => e.$2['setting']),
      ['music', 'sound_effects', 'haptics', 'show_timer', 'theme'],
    );
    // Only the name: no values or anything else.
    expect(analytics.events.every((e) => e.$2.keys.toSet().containsAll({'setting'}) && e.$2.length == 1), isTrue);
  });

  testWidgets('tile face size opens a picker and persists the choice', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Tile face size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Large').last);
    await tester.pumpAndSettle();
    expect((await repo.read()).tileSize, TileSizePreference.large);
    expect(find.text('Large'), findsOneWidget);
  });

  testWidgets('reduce motion persists', (tester) async {
    await pump(tester);
    await tester.tap(toggleFor('Reduce motion'));
    await tester.pump();
    expect((await repo.read()).reduceMotion, isTrue);
  });

  testWidgets('remove ads shows Purchased once ads are removed', (tester) async {
    await pump(tester, adsRemoved: true);
    await tester.scrollUntilVisible(find.text('Reset progress'), 200);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text(r'$1.99'), findsNothing);
  });

  testWidgets('reset progress asks first', (tester) async {
    await pump(tester, size: const Size(390, 1500));
    await tester.tap(find.text('Reset progress'));
    await tester.pumpAndSettle();
    expect(find.text('Reset all progress?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Reset all progress?'), findsNothing);
  });

  testWidgets('footer shows the version', (tester) async {
    await pump(tester, brightness: Brightness.dark);
    await tester.scrollUntilVisible(find.textContaining('pranta.dev', findRichText: true), 200);
    expect(find.textContaining('1.0.0 (1)', findRichText: true), findsOneWidget);
  });

  for (final size in layoutSizes.entries) {
    for (final scale in textScales) {
      testWidgets('settings layout · ${size.key} · text ${scale}x: no overflow', (tester) async {
        setTextScale(tester, scale);
        // With the Daily reminder row and its caption (Android/iOS).
        await pump(tester, size: size.value, notifications: FakeNotifications());
        await tester.pumpAndSettle();
        await expectNoOverflow(tester);
        // The tile face size sheet (the overflow scan left the list scrolled).
        await tester.ensureVisible(find.text('Tile face size', skipOffstage: false));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Tile face size'));
        await tester.pumpAndSettle();
        await expectNoOverflow(tester);
      });
    }
  }
  for (final b in Brightness.values) {
    testWidgets('settings shots ${b.name}', skip: !shotsEnabled, (tester) async {
      await pump(tester, brightness: b, size: const Size(390, 1150));
      await tester.pumpAndSettle();
      await maybeShot(tester, 'settings_${b.name}');
      await tester.tap(find.text('Tile face size'));
      await tester.pumpAndSettle();
      await maybeShot(tester, 'settings_tile_size_${b.name}');
    });
  }
}

class _FakeDisplay implements DisplayService {
  _FakeDisplay(this.rates);

  final DisplayRates rates;
  final requests = <bool>[];

  @override
  bool get canControl => true;
  @override
  Future<DisplayRates?> read() async => rates;
  @override
  Future<void> setHighRefreshRate(bool enabled) async => requests.add(enabled);
}
