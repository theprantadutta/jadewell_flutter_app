import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/platform/ads/ad_service.dart';
import 'package:jadewell_flutter_app/state/platform_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/store/store_screen.dart';

import '../settings/harness.dart';

void main() {
  Future<void> pump(WidgetTester tester, {bool adsRemoved = false}) async {
    await pumpScreen(
      tester,
      const StoreScreen(),
      overrides: [adServiceProvider.overrideWithValue(FakeAdService(adsRemoved: adsRemoved))],
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hero, benefits, price and restore', (tester) async {
    await pump(tester);
    expect(find.text('Play without interruptions'), findsOneWidget);
    expect(find.text('No ads between boards'), findsOneWidget);
    expect(find.text('Supports an indie developer'), findsOneWidget);
    expect(find.text(r'$1.99'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);
  });

  testWidgets('buying says coming soon until Phase 8', (tester) async {
    await pump(tester);
    await tester.tap(find.text(r'$1.99'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Purchases are coming soon'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('purchased state', (tester) async {
    await pump(tester, adsRemoved: true);
    expect(find.text('Ads are off'), findsOneWidget);
    expect(find.text('Purchased'), findsOneWidget);
    expect(find.text(r'$1.99'), findsNothing);
    expect(find.text('Restore'), findsNothing);
  });
}
