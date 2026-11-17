import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/platform/auth/auth_service.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/state/session_controller.dart';
import 'package:jadewell_flutter_app/ui/screens/account/account_screen.dart';
import 'package:material_ui/material_ui.dart' show Brightness, Size;

import '../../ui/golden_helpers.dart' show loadJwFonts;
import '../meta_checks.dart';
import '../settings/harness.dart';

void main() {
  late RecordingAnalytics analytics;

  setUpAll(loadJwFonts);
  setUp(() => analytics = RecordingAnalytics());

  Future<FakeSession> pump(
    WidgetTester tester,
    BackendSession session, {
    AuthException? linkError,
    Size size = const Size(390, 844),
    Brightness brightness = Brightness.light,
  }) async {
    final fake = FakeSession(session, linkError: linkError);
    await pumpScreen(
      tester,
      const AccountScreen(),
      size: size,
      brightness: brightness,
      overrides: [
        sessionProvider.overrideWith(() => fake),
        analyticsProvider.overrideWithValue(analytics),
      ],
    );
    await tester.pump();
    return fake;
  }

  testWidgets('guest: profile, explainer and link buttons (no Apple on Android)', (tester) async {
    await pump(tester, const BackendSession(identity: guestIdentity, user: testUser));
    expect(find.text('Jade Otter'), findsOneWidget);
    expect(find.text('@jade_otter_42'), findsOneWidget);
    expect(find.text('JW-7K3P9Q'), findsOneWidget);
    expect(find.textContaining('Your progress is saved on this device'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
    expect(find.text('Continue with Apple'), findsNothing);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('guest on iOS also gets Apple', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pump(tester, const BackendSession(identity: guestIdentity, user: testUser));
    expect(find.text('Continue with Apple'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('linked: providers and Sign out, no link buttons', (tester) async {
    await pump(tester, const BackendSession(identity: googleIdentity, user: testUser));
    expect(find.text('SIGNED IN WITH'), findsOneWidget);
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('mei@example.com'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
  });

  testWidgets('linking Google logs account_linked with the provider only', (tester) async {
    final fake = await pump(tester, const BackendSession(identity: guestIdentity, user: testUser));
    await tester.tap(find.text('Continue with Google'));
    await tester.pump();
    expect(fake.calls, contains('linkGoogle'));
    expect(analytics.events.single.$1, AnalyticsEvents.accountLinked);
    expect(analytics.events.single.$2, {'provider': 'google'});
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('credential in use offers signing in to that account instead', (tester) async {
    final fake = await pump(
      tester,
      const BackendSession(identity: guestIdentity, user: testUser),
      linkError: const AuthException(AuthErrorKind.credentialInUse),
    );
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(find.text('Already has an account'), findsOneWidget);
    expect(find.textContaining("won't be merged"), findsOneWidget);
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['linkGoogle', 'signInWithGoogle']);
    expect(analytics.events, isEmpty);
  });

  testWidgets('sign out asks first', (tester) async {
    final fake = await pump(tester, const BackendSession(identity: googleIdentity, user: testUser));
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(find.text('Sign out').last);
    await tester.pumpAndSettle();
    expect(fake.calls, contains('signOut'));
  });

  testWidgets('offline without a backend profile still renders', (tester) async {
    await pump(tester, const BackendSession(identity: guestIdentity));
    expect(find.text('Guest'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  test('display name rule matches the backend', () {
    expect(DisplayNames.isValid('Jade Otter'), isTrue);
    expect(DisplayNames.isValid('mei_92.k-x'), isTrue);
    expect(DisplayNames.isValid('Ré'), isFalse, reason: 'too short');
    expect(DisplayNames.isValid('Renée Ü'), isTrue, reason: 'any script');
    expect(DisplayNames.isValid('a' * 21), isFalse);
    expect(DisplayNames.isValid('two  spaces'), isFalse);
    expect(DisplayNames.isValid('emoji 😀'), isFalse);
  });

  const sessions = {
    'guest': BackendSession(identity: guestIdentity, user: testUser),
    'linked': BackendSession(identity: googleIdentity, user: testUser),
  };
  for (final size in layoutSizes.entries) {
    for (final scale in textScales) {
      testWidgets('account layout · ${size.key} · text ${scale}x: no overflow', (tester) async {
        setTextScale(tester, scale);
        for (final s in sessions.values) {
          await resetApp(tester);
          await pump(tester, s, size: size.value);
          await tester.pumpAndSettle();
          await expectNoOverflow(tester);
        }
        // The edit profile sheet.
        await tester.tap(find.bySemanticsLabel('Edit profile'));
        await tester.pumpAndSettle();
        await expectNoOverflow(tester);
      });
    }
  }
  for (final b in Brightness.values) {
    testWidgets('account shots ${b.name}', skip: !shotsEnabled, (tester) async {
      for (final s in sessions.entries) {
        await resetApp(tester);
        await pump(tester, s.value, brightness: b, size: const Size(390, 1000));
        await tester.pumpAndSettle();
        await maybeShot(tester, 'account_${s.key}_${b.name}');
      }
      await tester.tap(find.bySemanticsLabel('Edit profile'));
      await tester.pumpAndSettle();
      await maybeShot(tester, 'account_edit_${b.name}');
    });
  }
}
