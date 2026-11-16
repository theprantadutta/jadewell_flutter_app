import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/repositories/entitlement_repository.dart';
import 'package:jadewell_flutter_app/platform/analytics/analytics_service.dart';
import 'package:jadewell_flutter_app/platform/haptics/haptic_service.dart';
import 'package:jadewell_flutter_app/platform/iap/purchase_service.dart';
import 'package:jadewell_flutter_app/state/entitlement_providers.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/store/store_controller.dart';
import 'package:jadewell_flutter_app/ui/screens/store/store_screen.dart';
import 'package:material_ui/material_ui.dart';

import '../screens/settings/harness.dart' show pumpScreen;
import 'fakes.dart';

class _Haptics extends NoOpHaptics {
  int successes = 0;
  @override
  void success() => successes++;
}

void main() {
  late FakePurchaseService service;
  late MemoryEntitlementRepository entitlements;
  late RecordingAnalytics analytics;
  late _Haptics haptics;

  Future<void> pump(WidgetTester tester, StoreStatus status, {Entitlement owned = Entitlement.none}) async {
    service = FakePurchaseService(status);
    entitlements = MemoryEntitlementRepository(owned);
    analytics = RecordingAnalytics();
    haptics = _Haptics();
    await pumpScreen(
      tester,
      const StoreScreen(),
      overrides: [
        purchaseServiceProvider.overrideWithValue(service),
        entitlementRepositoryProvider.overrideWithValue(entitlements),
        analyticsProvider.overrideWithValue(analytics),
        hapticsProvider.overrideWithValue(haptics),
      ],
    );
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> drainToasts(WidgetTester tester) => tester.pump(const Duration(seconds: 4));

  testWidgets('ready: hero, benefits, the store price and restore', (tester) async {
    await pump(tester, const StoreReady('1,99 €'));
    expect(find.text('Play without interruptions'), findsOneWidget);
    expect(find.text('No ads between boards'), findsOneWidget);
    expect(find.text('1,99 €'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
    expect(analytics.names, [AnalyticsEvents.iapView]);

    await tester.tap(find.text('1,99 €'));
    await tester.pump();
    expect(service.buys, 1);
  });

  testWidgets('not available yet: calm card, no price, restore still offered', (tester) async {
    await pump(tester, const StoreProductMissing());
    expect(find.text('Not available yet'), findsOneWidget);
    expect(find.textContaining('Check back soon'), findsOneWidget);
    expect(find.text(r'$1.99'), findsNothing);
    expect(find.text('Remove ads'), findsNothing);
    expect(find.text('Restore'), findsOneWidget);

    service.restoreResult = RestoreOutcome.unavailable;
    await tester.tap(find.text('Restore'));
    await tester.pump();
    await tester.pump();
    expect(find.text("Purchases aren't available right now"), findsOneWidget);
    await drainToasts(tester);
  });

  testWidgets('unavailable store looks the same as a missing product', (tester) async {
    await pump(tester, const StoreUnavailable());
    expect(find.text('Not available yet'), findsOneWidget);
  });

  testWidgets('loading and purchasing show a spinner, verifying says so', (tester) async {
    await pump(tester, const StoreLoading());
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    service.set(const StorePurchasing(r'$1.99'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(r'$1.99'), findsNothing);

    service.set(const StoreVerifying(r'$1.99'));
    await tester.pump();
    expect(find.text('Verifying purchase…'), findsOneWidget);
    await tester.tap(find.text('Verifying purchase…'));
    await tester.pump();
    expect(service.buys, 0, reason: 'busy buttons do nothing');
  });

  testWidgets('pending payment and error with retry', (tester) async {
    await pump(tester, const StorePending(r'$1.99'));
    expect(find.text('Payment pending'), findsOneWidget);

    service.set(const StoreError('network_error', price: r'$1.99'));
    await tester.pump();
    expect(find.textContaining("didn't go through"), findsOneWidget);
    await tester.ensureVisible(find.text('Try again'));
    await tester.pump();
    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(service.buys, 1);
  });

  testWidgets('a fresh purchase celebrates once', (tester) async {
    await pump(tester, const StoreReady(r'$1.99'));
    service.set(const StorePurchasing(r'$1.99'));
    await tester.pump();
    service.set(const StoreVerifying(r'$1.99'));
    await tester.pump();
    await entitlements.grantRemoveAds(source: 'play');
    service.set(const StorePurchased(price: r'$1.99'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    expect(find.text('Ads are off'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text('Thank you! Ads are off'), findsOneWidget);
    expect(find.text('Restore'), findsNothing);
    expect(haptics.successes, 1);
    await drainToasts(tester);
  });

  testWidgets('already owned (restored) shows Purchased without a celebration', (tester) async {
    await pump(tester, const StoreReady(r'$1.99'), owned: const Entitlement(removeAds: true, source: 'play'));
    expect(find.text('Ads are off'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text(r'$1.99'), findsNothing);
    expect(haptics.successes, 0);
  });

  group('StoreController.derive', () {
    StoreView view(StoreStatus s, {bool owned = false}) => StoreController.derive(s, owned: owned).view;

    test('maps every status', () {
      expect(view(const StoreLoading()), StoreView.loading);
      expect(view(const StoreUnavailable()), StoreView.notAvailable);
      expect(view(const StoreProductMissing()), StoreView.notAvailable);
      expect(view(const StoreReady('x')), StoreView.ready);
      expect(view(const StorePurchasing('x')), StoreView.purchasing);
      expect(view(const StoreVerifying('x')), StoreView.verifying);
      expect(view(const StorePending('x')), StoreView.pending);
      expect(view(const StoreError('e', price: 'x')), StoreView.error);
      expect(view(const StoreError('e')), StoreView.notAvailable);
    });

    test('the entitlement wins unless a purchase is in flight', () {
      expect(view(const StoreUnavailable(), owned: true), StoreView.purchased);
      expect(view(const StorePending('x'), owned: true), StoreView.purchased);
      expect(view(const StoreVerifying('x'), owned: true), StoreView.verifying);
      // Revoked after a purchase: selling again.
      expect(view(const StorePurchased(price: 'x')), StoreView.ready);
      expect(StoreController.derive(const StorePurchased(), owned: true).restoredOnly, isFalse);
      expect(StoreController.derive(const StoreReady('x'), owned: true).restoredOnly, isTrue);
    });
  });
}
