import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Shared layout checks for the restyled screens.
///
/// [layoutSizes]: the phone frame of the reference screens (390 × 844) and
/// the Galaxy Tab A9 (800 × 1340 px at 1.33 dpr ≈ 600 × 1005).
const layoutSizes = {'narrow': Size(360, 780), 'phone': Size(390, 844), 'tablet': Size(600, 1005)};

/// OS text scales every screen must survive without overflowing.
const textScales = [1.0, 1.3];

/// Sets the OS text scale for the rest of the test.
void setTextScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Scrolls every vertical scrollable to its end (so lazily built content is
/// laid out) and fails on any exception, e.g. a RenderFlex overflow.
Future<void> expectNoOverflow(WidgetTester tester) async {
  expect(tester.takeException(), isNull);
  final lists = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  for (var i = 0; i < lists.evaluate().length; i++) {
    for (var k = 0; k < 10; k++) {
      final f = lists.at(i);
      if (f.evaluate().isEmpty || !f.hitTestable().evaluate().isNotEmpty) break;
      await tester.drag(f, const Offset(0, -500), warnIfMissed: false);
      await tester.pumpAndSettle();
    }
  }
  expect(tester.takeException(), isNull);
}

/// Unmounts the app so the next pump builds a fresh ProviderScope (a
/// re-pump at the same spot would keep the old overrides and state).
Future<void> resetApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpAndSettle();
}

/// Screenshots are opt-in: `JW_SHOTS=1 flutter test <file> --update-goldens`.
final bool shotsEnabled = Platform.environment.containsKey('JW_SHOTS');

/// Writes the app to `build/phone_shots/<name>.png` (outside tracked files)
/// when [shotsEnabled], after loading every image for real. [depth] is how
/// many folders the calling test file sits below the package root; pass
/// [settle] false while something loops.
Future<void> maybeShot(WidgetTester tester, String name, {int depth = 3, bool settle = true}) async {
  if (!shotsEnabled) return;
  await tester.runAsync(() async {
    for (final e in find.byType(Image).evaluate()) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  // A looping animation (the skeleton sweep) never settles.
  settle ? await tester.pumpAndSettle() : await tester.pump(const Duration(milliseconds: 100));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('${'../' * depth}build/phone_shots/$name.png'));
}
